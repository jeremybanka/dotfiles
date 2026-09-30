use ./local-node-path.nu [nearest-node-bin node-bin-search-paths]

# These names retain their clean-space meaning even if a dependency exports them.
const reserved = [git gh codex nu carapace mise scrubs-dirty-exec node-completion]

def scrubs-launcher [] {
    $env.HOME | path join .local libexec scrubs dirty-exec.sh
}

def is-scrubs [] {
    $nu.os-info.name == "linux" and (scrubs-launcher | path exists)
}

def registry-path [] {
    $env.HOME | path join .config local-node completions.nuon
}

def registered-commands [] {
    let file = (registry-path)
    if not ($file | path exists) { return [] }
    try { open $file | where {|name| ($name | describe) == "string" } } catch { [] }
}

def clean-command [name: string] {
    $name in $reserved or (is-scrubs) and (
        ($"/run/current-system/sw/bin/($name)" | path exists) or
        ($"/run/wrappers/bin/($name)" | path exists)
    )
}

def check-name [name: string] {
    if $name !~ '^[a-zA-Z0-9][a-zA-Z0-9._+-]*$' or (clean-command $name) {
        error make {msg: $"Unsupported or reserved local command: ($name)"}
    }
}

# Registration is clean-owned data. Never source scripts supplied by a package.
export def "node-completion add" [name: string] {
    check-name $name
    let file = (registry-path)
    mkdir ($file | path dirname)
    let temporary = $"($file).(random uuid)"
    registered-commands | append $name | uniq | sort | to nuon | save $temporary
    mv --force $temporary $file
    print $"Registered Comline completion for ($name)."
}

export def "node-completion remove" [name: string] {
    let file = (registry-path)
    if ($file | path exists) {
        let temporary = $"($file).(random uuid)"
        registered-commands | where {|item| $item != $name } | to nuon | save $temporary
        mv --force $temporary $file
    }
}

export def "node-completion list" [] { registered-commands }

export def --env local-node-refresh [] {
    let previous = ($env.LOCAL_NODE_PATH? | default "")
    $env.PATH = ($env.PATH | where {|entry| $entry != $previous })
    $env.LOCAL_NODE_PATH = ""
    let scrubs = (is-scrubs)
    let root = if $scrubs {
        let result = (^/run/current-system/sw/bin/git rev-parse --show-toplevel | complete)
        if $result.exit_code != 0 { return }
        $result.stdout | str trim
    } else { null }
    # Mise activation or a parent shell may already have added ancestor bins.
    # This integration owns their precedence: choose exactly one directory.
    let ancestors = (node-bin-search-paths $env.PWD | path expand)
    $env.PATH = ($env.PATH | where {|entry| ($entry | path expand) not-in $ancestors })
    let bin = (nearest-node-bin $env.PWD --root $root)
    if $bin == null { return }
    if not $scrubs {
        $env.LOCAL_NODE_PATH = $bin
        $env.PATH = ($env.PATH | where {|entry| $entry != $bin } | prepend $bin)
        return
    }

    # One directory per shell: concurrent shells never overwrite each other's
    # active command set. It is outside every dirty-writable mount.
    if ($env.LOCAL_NODE_PROXY_PID? | default 0) != $nu.pid {
        $env.LOCAL_NODE_PROXY_PID = $nu.pid
        let uid = (^/run/current-system/sw/bin/id -u | str trim)
        let runtime = $"/run/user/($uid)"
        let base = if ($runtime | path type) == "dir" {
            $runtime | path join scrubs-node-proxies
        } else {
            $env.HOME | path join .cache scrubs node-proxies
        }
        mkdir $base
        let live_pids = (ps | get pid)
        for old in (ls $base | where type == dir | get name) {
            let pid = (try { $old | path basename | split row "-" | first | into int } catch { null })
            if $pid != null and $pid not-in $live_pids { rm --recursive $old }
        }
        $env.LOCAL_NODE_PROXY_DIR = ($base | path join $"($nu.pid)-(random uuid)")
    }
    let proxies = $env.LOCAL_NODE_PROXY_DIR
    mkdir $proxies
    let names = (ls --all $bin
        | where {|entry| $entry.type in [file symlink] }
        | where {|entry|
            let mode = (^/run/current-system/sw/bin/test -x $entry.name | complete)
            $mode.exit_code == 0
        }
        | get name
        | path basename
        | where {|name| $name =~ '^[a-zA-Z0-9][a-zA-Z0-9._+-]*$' and $name not-in $reserved and not (clean-command $name) })
    for stale in (ls --all $proxies | get name) {
        if ($stale | path basename) not-in $names { rm $stale }
    }
    for name in $names {
        let proxy = ($proxies | path join $name)
        if not ($proxy | path exists) {
            let temporary = $"($proxy).(random uuid)"
            [
                '#!/bin/sh'
                $'exec "$HOME/.local/libexec/scrubs/dirty-exec.sh" --local-node "($name)" "$@"'
                ''
            ] | str join (char newline) | save $temporary
            ^/run/current-system/sw/bin/chmod 755 $temporary
            mv $temporary $proxy
        }
    }
    $env.LOCAL_NODE_PATH = $proxies
    $env.PATH = ($env.PATH | prepend $proxies)
}

# Query only explicitly registered local CLIs. The executable is always resolved
# again from PWD; completion and execution cannot select different packages.
export def local-node-candidates [name: string, words: list<string>] {
    if $name not-in (registered-commands) or (clean-command $name) { return null }
    let scrubs = (is-scrubs)
    let root = if $scrubs {
        let result = (^/run/current-system/sw/bin/git rev-parse --show-toplevel | complete)
        if $result.exit_code != 0 { return null }
        $result.stdout | str trim
    } else { null }
    let bin = (nearest-node-bin $env.PWD --root $root)
    if $bin == null { return null }
    let executable = ($bin | path join $name)
    if not ($executable | path exists) { return null }
    let launcher = (scrubs-launcher)
    let receiver = (job id)
    let worker = (job spawn {
        let result = try {
            let payload = if $scrubs {
                ^$launcher --local-node $name _comline nushell ...$words err> /dev/null | first 256kb | decode utf-8
            } else {
                ^$executable _comline nushell ...$words err> /dev/null | first 256kb | decode utf-8
            }
            let candidates = ($payload | from json)
            # Only data crosses back into the clean completion provider.
            $candidates | first 1000 | each {|candidate|
                {
                    value: ($candidate.value | into string)
                    display: ($candidate.display? | default $candidate.value | into string)
                    description: ($candidate.description? | default "" | into string)
                }
            }
        } catch { [] }
        $result | job send $receiver --tag (job id)
    })
    let result = try { job recv --tag $worker --timeout 2sec } catch { [] }
    try { job kill $worker }
    job flush --tag $worker
    $result
}

export def --env local-node-init [] {
    let previous = $env.config.completions.external.completer
    $env.config.completions.external.completer = {|place: record, buffer: string|
        let spans = $place.command
        if ($spans | is-empty) { return [] }
        # Explicit executable paths and aliases retain their existing providers.
        let result = if ($spans.0 | path basename) == $spans.0 {
            local-node-candidates $spans.0 ($spans | skip 1)
        } else { null }
        if $result != null { $result } else if $previous != null {
            do {
                $env.config.completions.external.completer = $previous
                $buffer | commandline complete --detailed
            }
        } else { null }
    }
    $env.config.hooks.pre_prompt = ($env.config.hooks.pre_prompt | append { local-node-refresh })
    $env.config.hooks.env_change.PWD = ($env.config.hooks.env_change.PWD? | default [] | append { local-node-refresh })
    local-node-refresh
}
