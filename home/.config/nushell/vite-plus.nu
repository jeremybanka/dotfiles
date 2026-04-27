def "nu-complete vp args" [context?: string] {
    let args = (
        $context
        | default ""
        | split row " "
        | skip 1
        | where {|part| $part | is-not-empty }
    )

    if ($args | length) <= 1 {
        let help_outputs = [
            (do -i { ^vp help | complete })
            (do -i { ^vp --help | complete })
        ]

        let commands = (
            $help_outputs
            | where exit_code == 0
            | each {|result| [$result.stdout $result.stderr] | str join (char newline) }
            | str join (char newline)
            | ansi strip
            | lines
            | parse --regex '^\s*(?:[-*]\s*)?(?<value>[a-z][a-z0-9:_-]*)(?:\s{2,}|\s+-\s+|\s+--\s+|\s*:\s+)(?<description>.+)$'
            | where value !~ '^-'
            | group-by value
            | transpose value entries
            | each {|row| $row.entries | first }
        )

        return ($commands | sort-by value)
    }

    []
}

export extern "vp" [
    ...args: string@"nu-complete vp args"
]

export def --env vp-use [...args: string] {
    let result = (
        with-env {
            VITE_PLUS_ENV_USE_EVAL_ENABLE: "1"
            VP_ENV_USE_EVAL_ENABLE: "1"
        } {
            ^vp env use ...$args
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
        error make { msg: $"vp env use exited with code ($result.exit_code)" }
    }
}
