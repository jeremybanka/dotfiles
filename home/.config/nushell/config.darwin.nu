use ~/.config/nushell/mise.darwin.nu

$env.config.buffer_editor = "codium"

def c [path: string] {
    ^open $path -a "VSCodium"
}

# Bottom's default theme assumes a dark terminal. Match the macOS appearance
# each time it starts, while preserving an explicitly requested theme.
def --wrapped btm [...args: string] {
    let has_theme = (
        $args
        | any {|arg|
            ($arg == "--theme") or ($arg == "-t") or ($arg | str starts-with "--theme=")
        }
    )
    let appearance = (do -i { ^defaults read -g AppleInterfaceStyle } | complete).stdout | str trim
    let theme = if $appearance == "Dark" { "default" } else { "default-light" }

    if $has_theme {
        ^/opt/homebrew/bin/btm ...$args
    } else {
        ^/opt/homebrew/bin/btm --theme $theme ...$args
    }
}
