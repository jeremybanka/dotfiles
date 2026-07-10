source ~/.config/nushell/env.shared.nu

const host_os = ($nu.os-info.name | str lowercase)
const host_env = if $host_os == "macos" {
    "~/.config/nushell/env.darwin.nu"
} else if $host_os == "linux" {
    "~/.config/nushell/env.linux.nu"
} else {
    null
}

source $host_env
