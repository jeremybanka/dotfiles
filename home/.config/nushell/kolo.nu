# ~/.config/nushell/kolo.nu

def git-dots [] {
    if (git rev-parse --is-inside-work-tree | complete | get stdout | str trim) == "true" {
        let status = (git status --porcelain)
        mut dots = ""

        if ($status | str contains "^[AMDR]." | into bool) {
            $dots = $"($dots)(ansi green)●(ansi reset)"
        }
        if ($status | str contains "^.[MD]" | into bool) {
            $dots = $"($dots)(ansi yellow)●(ansi reset)"
        }
        if ($status | lines | where { |line| $line | str starts-with "??" } | length) > 0 {
            $dots = $"($dots)(ansi red)●(ansi reset)"
        }

        let branch = (git rev-parse --abbrev-ref HEAD | str trim)
        return $" (ansi green)[($branch)(ansi reset)($dots)(ansi green)](ansi reset)"
    } else {
        return ""
    }
}

export def prompt [] {
    let dir = (pwd | path basename)
    let gitinfo = (git-dots)
    $"(ansi magenta)($dir)(ansi reset)($gitinfo) "
}

export def prompt-indicator [] { $"\r\n(ansi magenta)>(ansi reset) " }
