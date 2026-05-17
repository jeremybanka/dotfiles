set shell := ["zsh", "-cu"]

default:
    @just --list

fmt:
    dprint fmt
    taplo fmt $(rg --files --hidden -g '*.toml' -g '!.git' | rg -v '^(home/\.config/nvim/|\.zed/)')
    shfmt -w -i 2 -bn -ci -sr $(rg --files -g '*.sh' -g 'setup.sh')
    just --fmt
    swift_files=(${(f)"$(rg --files --hidden -g '*.swift' -g '!.git')"}); (( ${#swift_files[@]} )) && xcrun swift-format format --in-place $swift_files

fmt-check:
    dprint check
    taplo fmt --check $(rg --files --hidden -g '*.toml' -g '!.git' | rg -v '^(home/\.config/nvim/|\.zed/)')
    shfmt -d -i 2 -bn -ci -sr $(rg --files -g '*.sh' -g 'setup.sh')
    just --fmt --check
    swift_files=(${(f)"$(rg --files --hidden -g '*.swift' -g '!.git')"}); (( ${#swift_files[@]} )) && xcrun swift-format lint --strict $swift_files

brewfile-dump:
    brew bundle dump --file=~/Brewfile --force

brewfile-use:
    brew bundle install --file=~/Brewfile

helix-theme-build output="./build/helix-theme-agent":
    mkdir -p "$(dirname {{ output }})"
    swiftc ./home/.local/libexec/com.jeremybanka.helix-theme/helix-theme-agent.swift -o {{ output }}

helix-theme-sync:
    mkdir -p ./build
    swiftc ./home/.local/libexec/com.jeremybanka.helix-theme/helix-theme-agent.swift -o ./build/helix-theme-agent
    ./build/helix-theme-agent sync

helix-theme-watch:
    mkdir -p ./build
    swiftc ./home/.local/libexec/com.jeremybanka.helix-theme/helix-theme-agent.swift -o ./build/helix-theme-agent
    ./build/helix-theme-agent watch

helix-theme-install-agent:
    mkdir -p ./build
    swiftc ./home/.local/libexec/com.jeremybanka.helix-theme/helix-theme-agent.swift -o ./build/helix-theme-agent
    ./build/helix-theme-agent install-launch-agent

helix-watch-config:
    nu ./scripts/watch-helix-config.nu

bootstrap instance_name source_image="./scrubs/qcow2/scrubs.qcow2" shim_name="":
    nu ./scrubs/bootstrap.nu --source-image {{ source_image }} {{ if shim_name != "" { "--shim-name " + shim_name + " " } else { "" } }}{{ instance_name }}

download-latest-iso channel="nixos-25.11":
    nu ./scrubs/download-latest-iso.nu {{ channel }}

export-seed-image instance_name output_path:
    nu ./scrubs/export-seed-image.nu {{ instance_name }} {{ output_path }}

refresh-base-image source_image="./scrubs/qcow2/scrubs.qcow2" output_path="./scrubs/qcow2/scrubs.qcow2" instance_name="scrubs-refresh":
    nu ./scrubs/refresh-base-image.nu --source-image {{ source_image }} --output-path "{{ output_path }}" --instance-name {{ instance_name }}

seed instance_name="scrubs-seed":
    nu ./scrubs/seed.nu {{ instance_name }}

vm-shell instance_name:
    limactl shell {{ instance_name }}

sync-base-image-to-icloud image="scrubs.qcow2":
    nu ./scrubs/sync-base-image-to-icloud.nu {{ image }}

sync-base-image-from-icloud image="scrubs.qcow2":
    nu ./scrubs/sync-base-image-from-icloud.nu {{ image }}

up:
    nu ./scripts/update.nu
