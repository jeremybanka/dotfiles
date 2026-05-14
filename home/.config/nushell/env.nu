source ~/.config/nushell/env.shared.nu

let host_os = ((sys host).name | str downcase)

if $host_os == "macos" {
    source ~/.config/nushell/env.darwin.nu
}

if $host_os == "linux" {
    source ~/.config/nushell/env.linux.nu
}
