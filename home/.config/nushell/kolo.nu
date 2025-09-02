def git-dots [] {
    let result = (git status --porcelain --branch | complete)

    if $result.exit_code != 0 {
        return ""
    }

    # let status = (git status --porcelain)
    let lines = ($result.stdout | lines)
    let branch = ($lines | first | str replace '## ' '' | str trim)
    mut dots = ""

    if ($lines | where { |line| $line =~ ^[AMDRC] } | length) > 0 {
        $dots = $"($dots)(ansi green)●(ansi reset)"
    }
    if ($lines | where { |line| $line =~ ^.[MD] } | length) > 0 {
        $dots = $"($dots)(ansi yellow)●(ansi reset)"
    }
    if ($lines | where { |line| $line | str starts-with "??" } | length) > 0 {
        $dots = $"($dots)(ansi red)●(ansi reset)"
    }

    let branch = (git rev-parse --abbrev-ref HEAD | str trim)
    return $" (ansi green)[($branch)(ansi reset)($dots)(ansi green)](ansi reset)"
   
}

export def prompt [] {
    let dir = (pwd | path basename)
    let gitinfo = (git-dots)
    $"(ansi magenta)($dir)(ansi reset)($gitinfo) "
}

export def prompt-indicator [] { $"\r\n(ansi magenta)>(ansi reset) " }
