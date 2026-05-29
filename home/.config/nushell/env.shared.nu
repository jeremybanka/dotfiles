use std/util "path add"

path add "/nix/var/nix/profiles/default/bin"

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
