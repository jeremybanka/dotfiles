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

bootstrap instance_name shim_name="" source_image="./vms/images/scrubs.qcow2":
    nu ./vms/bootstrap.nu --source-image {{ source_image }} {{ if shim_name != "" { "--shim-name " + shim_name + " " } else { "" } }}{{ instance_name }}

download-latest-iso channel="nixos-25.11":
    nu ./vms/download-latest-iso.nu {{ channel }}

export-seed-image instance_name output_path:
    nu ./vms/export-seed-image.nu {{ instance_name }} {{ output_path }}

refresh-base-image source_image="./vms/images/scrubs.qcow2" output_path="./vms/images/scrubs.qcow2" instance_name="scrubs-refresh":
    nu ./vms/refresh-base-image.nu --source-image {{ source_image }} --output-path "{{ output_path }}" --instance-name {{ instance_name }}

seed instance_name="scrubs-seed":
    nu ./vms/seed.nu {{ instance_name }}

vm-shell instance_name:
    limactl shell {{ instance_name }}

scrubs-auth-status:
    @gh_status=missing; \
    codex_status=missing; \
    codex_path="${SCRUBS_CODEX_AUTH_JSON_PATH:-$HOME/.codex/auth.json}"; \
    security find-generic-password -s scrubs-gh-token -a github.com > /dev/null 2>&1 && gh_status=present; \
    if [ -s "$codex_path" ] && grep -Eq '"auth_mode"[[:space:]]*:[[:space:]]*"chatgpt"' "$codex_path"; then codex_status=present; fi; \
    echo "GitHub Keychain item (scrubs-gh-token/github.com): $gh_status"; \
    echo "Codex auth bundle ($codex_path): $codex_status"

scrubs-auth-set-gh account="github.com":
    @read -s "?GitHub token for {{ account }}: " token; \
    echo; \
    security add-generic-password -U -s scrubs-gh-token -a {{ account }} -w "$token"; \
    echo "Stored GitHub token in macOS Keychain as scrubs-gh-token/{{ account }}"

scrubs-auth-set-codex:
    @echo "Codex clean auth is sourced from the host ChatGPT login bundle, not an API key."; \
    echo "Run 'codex login' on the host, then re-run 'just scrubs-auth-status'."

scrubs-auth-delete-gh account="github.com":
    @security delete-generic-password -s scrubs-gh-token -a {{ account }} || true

scrubs-auth-delete-codex:
    @echo "Codex clean auth is sourced from the host ChatGPT login bundle."; \
    echo "Run 'codex logout' on the host if you want to remove that source auth."

sync-base-image-to-icloud image="scrubs.qcow2":
    nu ./vms/sync-base-image-to-icloud.nu {{ image }}

sync-base-image-from-icloud image="scrubs.qcow2":
    nu ./vms/sync-base-image-from-icloud.nu {{ image }}

up:
    nu ./scripts/update.nu

upgrade-workflows:
    nu ./scripts/upgrade-workflows.nu

upgrade-workflows-dry-run:
    nu ./scripts/upgrade-workflows.nu --dry-run

lima-ports instance_name="":
    nu ./scripts/lima-ports.nu {{ if instance_name == "" { "" } else { instance_name } }}
