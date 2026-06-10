use ~/.config/nushell/mise.darwin.nu

$env.config.buffer_editor = "codium"

def c [path: string] {
    ^open $path -a "VSCodium"
}
