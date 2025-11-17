$env.CARAPACE_BRIDGES = 'zsh,fish,bash,inshellisense' # optional
mkdir ~/.cache/carapace
carapace _carapace nushell | save --force ~/.cache/carapace/init.nu
let mise_path = $nu.default-config-dir | path join mise.nu
^mise activate nu | save $mise_path --force
