def load-package-json [] {
    do -i { open package.json }
}

def ni-cache-dir [] {
    $env.HOME | path join ".cache" "nushell" "ni"
}

def ni-cache-key [query: string] {
    $query | str downcase | str replace -ra '[^a-z0-9._-]' '_'
}

def ni-package-cache-path [query: string] {
    ni-cache-dir | path join $"packages-(ni-cache-key $query).json"
}

def ni-popular-packages [] {
    [
        { value: "@changesets/cli", description: "declarative release management" }
        { value: "@types/node", description: "types for Node.js" }
        { value: "@js-temporal/polyfill", description: "temporal implementation" }
        { value: "atom.io", description: "state engine" }
        { value: "arktype", description: "fast data validation" }
        { value: "biome", description: "formatter and linter" }
        { value: "cspell", description: "spell checker" }
        { value: "drizzle-orm", description: "ORM runtime" }
        { value: "drizzle-kit", description: "ORM toolkit" }
        { value: "esbuild", description: "bundler" }
        { value: "eslint", description: "linter" }
        { value: "hono", description: "edge web framework" }
        { value: "happy-dom", description: "DOM implementation" }
        { value: "jiti", description: "runtime loader" }
        { value: "jsdom", description: "DOM implementation" }
        { value: "pin-dependencies-checker", description: "keep everything pinned" }
        { value: "playwright", description: "browser testing" }
        { value: "preact", description: "UI library" }
        { value: "react", description: "UI library" }
        { value: "react-dom", description: "UI renderer" }
        { value: "rimraf", description: "cross-platform directory deletion" }
        { value: "shadcn-ui", description: "component tooling" }
        { value: "solid-js", description: "UI library" }
        { value: "tailwindcss", description: "utility CSS" }
        { value: "three", description: "3D rendering" }
        { value: "treetrunks", description: "typesafe routing primitives" }
        { value: "tsdown", description: "library builder" }
        { value: "turbo", description: "monorepo task runner" }
        { value: "typescript", description: "typed JavaScript" }
        { value: "vite", description: "frontend build tool" }
        { value: "vitest", description: "test runner" }
        { value: "zod", description: "popular data validation" }
    ]
}

def ni-package-query [context?: string] {
    ($context | default "")
    | split row " "
    | last
    | default ""
    | str trim
}

def ni-filter-packages [query: string] {
    let packages = $in
    let filtered = if ($query | is-empty) {
        $packages
    } else {
        let lowered = ($query | str downcase)
        $packages | where {|pkg|
            let name = ($pkg.value | str downcase)
            ($name | str starts-with $lowered) or ($name | str contains $lowered)
        }
    }

    $filtered
    | group-by value
    | transpose value entries
    | each {|row| $row.entries | first }
    | sort-by value
    | first 25
}

def ni-dedupe-packages [] {
    $in
    | group-by value
    | transpose value entries
    | each {|row| $row.entries | first }
    | first 25
}

def ni-read-package-cache [query: string] {
    let cache_path = (ni-package-cache-path $query)
    if not ($cache_path | path exists) {
        return []
    }

    do -i { open $cache_path } | default []
}

def ni-write-package-cache [query: string, packages: list] {
    let cache_path = (ni-package-cache-path $query)
    try {
        mkdir (ni-cache-dir)
        $packages | to json | save --force $cache_path
    } catch {
        null
    }
}

def ni-fetch-packages [query: string] {
    if (($query | str length) < 2) {
        return []
    }

    let query_string = ({
        text: $query
        size: 20
    } | url build-query)
    let url = $"https://registry.npmjs.org/-/v1/search?($query_string)"
    let response = (do -i { http get --max-time 800ms $url })

    if ($response | is-empty) {
        return []
    }

    let packages = (
        $response.objects?
        | default []
        | each {|item|
            let package = $item.package
            {
                value: $package.name
                description: $"npm ($package.version)"
            }
        }
    )

    if not ($packages | is-empty) {
        ni-write-package-cache $query $packages
    }

    $packages
}

export def "nu-complete nr scripts" [] {
    let pkg = (load-package-json)
    if ($pkg | is-empty) {
        return []
    }

    let scripts = ($pkg.scripts? | default {})
    if (($scripts | columns | length) == 0) {
        return []
    }

    $scripts
    | transpose value description
}

export def "nu-complete nun dependencies" [] {
    let pkg = (load-package-json)
    if ($pkg | is-empty) {
        return []
    }

    let dependencies = ($pkg.dependencies? | default {} | columns)
    let dev_dependencies = ($pkg.devDependencies? | default {} | columns)
    let optional_dependencies = ($pkg.optionalDependencies? | default {} | columns)
    let peer_dependencies = ($pkg.peerDependencies? | default {} | columns)

    [$dependencies, $dev_dependencies, $optional_dependencies, $peer_dependencies]
    | flatten
    | uniq
    | sort
    | each {|name| { value: $name description: "dependency" } }
}

export def "nu-complete na bins" [] {
    let bin_dir = ("node_modules" | path join ".bin")
    let entries = (do -i { ls $bin_dir })

    if ($entries | is-empty) {
        return []
    }

    $entries
    | where type == symlink or type == file
    | get name
    | path basename
    | uniq
    | sort
    | each {|name| { value: $name description: "local binary" } }
}

export def "nu-complete ni packages" [context?: string] {
    let query = (ni-package-query $context)
    let popular = (ni-popular-packages | ni-filter-packages $query)
    let cached = (ni-read-package-cache $query)
    let fetched = if ($cached | is-empty) {
        ni-fetch-packages $query
    } else {
        $cached
    }

    [$fetched, $popular]
    | flatten
    | ni-dedupe-packages
}

export extern "ni" [
    -E
    -D
    package?: string@"nu-complete ni packages"
    ...packages: string@"nu-complete ni packages"
]

export extern "nci" []

export extern "nr" [
    script?: string@"nu-complete nr scripts"
    ...args: string
]

export extern "nun" [
    -g
    -m
    dependency?: string@"nu-complete nun dependencies"
    ...dependencies: string
]

export extern "nup" [
    -i
    package?: string
    ...packages: string
]

export extern "nlx" [
    package?: string
    ...args: string
]

export extern "na" [
    bin?: string@"nu-complete na bins"
    ...args: string
]

export extern "nd" [
    -c
    ...args: string
]
