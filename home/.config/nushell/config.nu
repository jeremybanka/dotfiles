source ~/.config/nushell/config.shared.nu

let host_os = ((sys host).name | str downcase)

if $host_os == "macos" {
    source ~/.config/nushell/config.darwin.nu
}

if $host_os == "linux" {
    source ~/.config/nushell/config.linux.nu
}
