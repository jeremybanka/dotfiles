use ~/.config/nushell/kolo.nu *
use ~/.config/nushell/mise.nu

$env.PROMPT_COMMAND = { prompt }
$env.PROMPT_INDICATOR = { prompt-indicator }
$env.PROMPT_COMMAND_RIGHT = ""
$env.config.buffer_editor = "codium"
$env.config.show_banner = false
$env.config.table.mode = 'rounded'

def --env vp [...args: string] {
    let vp_bin = ($env.HOME | path join ".vite-plus" "bin" "vp")
    let is_env_use = (($args | length) >= 2) and ($args.0 == "env") and ($args.1 == "use")
    let wants_help = ($args | any {|arg| $arg in ["-h", "--help"] })

    if ($is_env_use and not $wants_help) {
        let result = (
            with-env { VITE_PLUS_ENV_USE_EVAL_ENABLE: "1" } {
                ^$vp_bin ...$args
            } | complete
        )

        for line in ($result.stdout | lines) {
            if ($line | str starts-with "export ") {
                let assignment = ($line | str replace "export " "")
                let parts = ($assignment | split row "=")
                let key = ($parts | first)
                let value = (
                    $parts
                    | skip 1
                    | str join "="
                    | str trim --char "'"
                    | str trim --char '"'
                )
                load-env { ($key): $value }
            } else if ($line | str starts-with "unset ") {
                let key = ($line | str replace "unset " "")
                hide-env $key
            } else if ($line | str trim | is-not-empty) {
                print $line
            }
        }

        if ($result.stderr | str trim | is-not-empty) {
            print --stderr $result.stderr
        }

        if $result.exit_code != 0 {
            error make { msg: $"vp exited with code ($result.exit_code)" }
        }

        return
    }

    ^$vp_bin ...$args
}

alias g = git
def c [path: string] {
    ^open $path -a "VSCodium"
}

source ~/.cache/carapace/init.nu
