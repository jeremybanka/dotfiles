$env.PATH = (
    $env.PATH
    | where {|entry|
        $entry != ($env.HOME | path join ".local" "bin")
        and $entry != "/run/current-system/sw/bin"
    }
    | prepend ($env.HOME | path join ".local" "bin")
    | append "/run/current-system/sw/bin"
)
