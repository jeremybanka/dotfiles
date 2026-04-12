def git-mode [git_dir: string] {
    if ($git_dir | path join "BISECT_LOG" | path exists) {
        return " <B>"
    }

    if ($git_dir | path join "MERGE_HEAD" | path exists) {
        return " >M<"
    }

    let rebase_merge = ($git_dir | path join "rebase-merge")
    let rebase_apply = ($git_dir | path join "rebase-apply")
    let dotest = ($git_dir | path join ".." ".dotest")

    if ($rebase_merge | path exists) {
        let step = (open ($rebase_merge | path join "msgnum") | str trim)
        let total = (open ($rebase_merge | path join "end") | str trim)

        if ($step | is-not-empty) and ($total | is-not-empty) {
            return $" >R ($step)/($total)<"
        }

        return " >R>"
    }

    if ($rebase_apply | path exists) or ($dotest | path exists) {
        return " >R>"
    }

    ""
}

def git-branch-label [status_line: string, git_dir: string] {
    if ($status_line | str starts-with "## No commits yet on ") {
        return ($status_line | str replace "## No commits yet on " "" | str trim)
    }

    if ($status_line | str starts-with "## Initial commit on ") {
        return ($status_line | str replace "## Initial commit on " "" | str trim)
    }

    let branch_from_status = (
        $status_line
        | str replace -r '^## ' ''
        | split row '...'
        | first
        | split row ' ['
        | first
        | str trim
    )

    if $branch_from_status != "HEAD (no branch)" {
        return $branch_from_status
    }

    let rebase_head = ($git_dir | path join "rebase-merge" "head-name")
    if ($rebase_head | path exists) {
        return (
            open $rebase_head
            | str trim
            | str replace 'refs/heads/' ''
        )
    }

    let symbolic_ref = (^git symbolic-ref --short HEAD | complete)
    if $symbolic_ref.exit_code == 0 {
        return ($symbolic_ref.stdout | str trim)
    }

    let tag_ref = (^git describe --tags --exact-match HEAD | complete)
    if $tag_ref.exit_code == 0 {
        return $"◈ ($tag_ref.stdout | str trim)"
    }

    let short_head = (^git rev-parse --short HEAD | complete)
    if $short_head.exit_code == 0 {
        return $"➦ ($short_head.stdout | str trim)"
    }

    "HEAD"
}

def git-dots [] {
    let result = (git status --porcelain --branch | complete)

    if $result.exit_code != 0 {
        return "\r\n"
    }

    let lines = ($result.stdout | lines)
    let git_dir = ((^git rev-parse --git-dir | complete).stdout | str trim)
    let branch = (git-branch-label ($lines | first) $git_dir)
    let mode = (git-mode $git_dir)
    mut dots = ""

    if ($lines | where { |line| $line =~ ^[AMDRC] } | length) > 0 {
        $dots = $"($dots)(ansi green_bold)●(ansi reset)"
    }
    if ($lines | where { |line| $line =~ ^.[MD] } | length) > 0 {
        $dots = $"($dots)(ansi yellow_bold)●(ansi reset)"
    }
    if ($lines | where { |line| $line | str starts-with "??" } | length) > 0 {
        $dots = $"($dots)(ansi red_bold)●(ansi reset)"
    }

    return $" (ansi green)[($branch)($mode)(ansi reset)($dots)(ansi green)](ansi reset)\r\n"
}

export def prompt [] {
    let dir = (pwd | path basename)
    let gitinfo = (git-dots)
    $"(ansi magenta)($dir)(ansi reset)($gitinfo)"
}

export def prompt-indicator [] { $"(ansi magenta)>(ansi reset) " }
