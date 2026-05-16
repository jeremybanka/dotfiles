use std/util "path add"

path add "/nix/var/nix/profiles/default/bin"
path add "~/.bun/bin"

$env.CARAPACE_BRIDGES = "zsh,fish,bash,inshellisense"

let carapace_cache = ($env.HOME | path join ".cache" "carapace")
let carapace_init = ($carapace_cache | path join "init.nu")

mkdir $carapace_cache

if (which carapace | is-not-empty) {
    carapace _carapace nushell | save --force $carapace_init
} else {
    "" | save --force $carapace_init
}

source ~/.config/nushell/carapace-init.nu

let mise_path = $nu.default-config-dir | path join "mise.nu"
if not ($mise_path | path exists) {
    ^mise activate nu | save $mise_path
}
