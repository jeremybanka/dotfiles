def load-package-json [] {
    do -i { open package.json }
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

export def "nu-complete na agents" [] {
    [
        { value: "npm", description: "Use npm directly" }
        { value: "pnpm", description: "Use pnpm directly" }
        { value: "yarn", description: "Use yarn classic directly" }
        { value: "yarn@berry", description: "Use Yarn Berry directly" }
        { value: "bun", description: "Use Bun directly" }
        { value: "deno", description: "Use Deno directly" }
    ]
}

export extern "ni" [
    -D
    -P
    -g
    -i
    --frozen
    --frozen-if-present
    package?: string
    ...packages: string
]

export extern "nci" [
    -D
    -P
    -g
    -i
    package?: string
    ...packages: string
]

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
    agent?: string@"nu-complete na agents"
    ...args: string
]

export extern "nd" [
    -c
    ...args: string
]
