use ~/.config/nushell/kolo.nu *
use ~/.config/nushell/mise.nu

$env.PROMPT_COMMAND = { prompt }
$env.PROMPT_INDICATOR = { prompt-indicator }
$env.PROMPT_COMMAND_RIGHT = ""
$env.config.buffer_editor = "codium"
$env.config.show_banner = false
$env.config.table.mode = 'rounded'

alias g = git

source ~/.cache/carapace/init.nu
