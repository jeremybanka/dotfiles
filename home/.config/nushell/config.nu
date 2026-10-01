source ~/.config/nushell/config.shared.nu

const host_os = ($nu.os-info.name | str lowercase)
const host_config = if $host_os == "macos" {
    "~/.config/nushell/config.darwin.nu"
} else if $host_os == "linux" {
    "~/.config/nushell/config.linux.nu"
} else {
    null
}

source $host_config

# Register after platform integration so mise updates PATH before our hook.
use ~/.config/nushell/local-node.nu *
local-node-init
