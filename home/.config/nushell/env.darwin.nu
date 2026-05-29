use std/util "path add"

path add "/opt/homebrew/bin"

let appearance = (do -i { ^defaults read -g AppleInterfaceStyle | complete })
$env.BAT_THEME = if $appearance.exit_code == 0 and (($appearance.stdout | str trim) == "Dark") {
    "Monokai Extended"
} else {
    "GitHub"
}
