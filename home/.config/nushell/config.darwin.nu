$env.config.buffer_editor = "codium"

def c [path: string] {
    ^open $path -a "VSCodium"
}
