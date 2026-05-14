use ~/.config/nushell/kolo.nu *
use ~/.config/nushell/mise.nu
use ~/.config/nushell/ni-completions.nu *
use ~/.config/nushell/vite-plus.nu *

$env.PROMPT_COMMAND = { prompt }
$env.PROMPT_INDICATOR = { prompt-indicator }
$env.PROMPT_COMMAND_RIGHT = ""
$env.config.show_banner = false
$env.config.table.mode = "rounded"

alias g = git
alias lz = lazygit

if ("~/.cache/carapace/init.nu" | path exists) {
    source ~/.cache/carapace/init.nu
}
