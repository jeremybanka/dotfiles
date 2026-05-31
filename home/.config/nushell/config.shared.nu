use ~/.config/nushell/kolo.nu *
use ~/.config/nushell/ni-completions.nu *
use ~/.config/nushell/vite-plus.nu *

$env.PROMPT_COMMAND = { prompt }
$env.PROMPT_INDICATOR = { prompt-indicator }
$env.PROMPT_COMMAND_RIGHT = ""
$env.config.show_banner = false
$env.config.table.mode = "rounded"

alias b = brew
alias g = git
alias gg = lazygit
alias j = just
alias l = limactl
alias m = mise
alias mi = mise install
alias n = nix
