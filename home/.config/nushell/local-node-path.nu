# Shared by the interactive integration and the clean Scrubs launcher.
export def node-bin-search-paths [directory: string, --root: string] {
    mut current = ($directory | path expand)
    let boundary = if $root == null { null } else { $root | path expand }
    if $boundary != null and $current != $boundary and not ($current | str starts-with $"($boundary)/") {
        return []
    }
    mut paths = []
    loop {
        $paths = ($paths | append ($current | path join node_modules .bin))
        if $current == $boundary { break }
        let parent = ($current | path dirname)
        if $parent == $current { break }
        $current = $parent
    }
    $paths
}

export def nearest-node-bin [directory: string, --root: string] {
    let boundary = if $root == null { null } else { $root | path expand }
    for candidate in (node-bin-search-paths $directory --root $root) {
        let resolved = ($candidate | path expand)
        if ($resolved | path type) == "dir" {
            # Never make an out-of-workspace symlink visible in dirty space.
            if $boundary == null or ($resolved | str starts-with $"($boundary)/") {
                return $candidate
            }
            return null
        }
    }
    null
}

def main [directory: string, --root: string] {
    nearest-node-bin $directory --root $root | default "" | print -n
}
