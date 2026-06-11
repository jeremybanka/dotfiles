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

bootstrap instance_name clean_auth_profile="personal" shim_name="" source_image="./vms/images/scrubs.qcow2" tailscale_mode="tailscale-enabled":
    nu ./vms/bootstrap.nu --source-image {{ source_image }} {{ if shim_name != "" { "--shim-name " + shim_name + " " } else { "" } }}--clean-auth-profile {{ clean_auth_profile }} {{ instance_name }} {{ tailscale_mode }}

scrubs-validation-static:
    nu ./vms/validate.nu --help >/dev/null

scrubs-validate:
    @instance_name="${SCRUBS_VALIDATE_INSTANCE_NAME:-scrubs-validate}"; \
    clean_auth_profile="${SCRUBS_VALIDATE_CLEAN_AUTH_PROFILE:-}"; \
    shim_name="${SCRUBS_VALIDATE_SHIM_NAME:-}"; \
    source_image="${SCRUBS_VALIDATE_SOURCE_IMAGE:-}"; \
    git_remote_url="${SCRUBS_VALIDATE_GIT_REMOTE_URL:-}"; \
    tailscale_mode="${SCRUBS_VALIDATE_TAILSCALE_MODE:-tailscale-disabled}"; \
    recreate="${SCRUBS_VALIDATE_RECREATE:-false}"; \
    skip_git_push_dry_run="${SCRUBS_VALIDATE_SKIP_GIT_PUSH_DRY_RUN:-false}"; \
    args=(./vms/validate.nu --tailscale-mode "$tailscale_mode"); \
    if [ -n "$clean_auth_profile" ]; then args+=(--clean-auth-profile "$clean_auth_profile"); fi; \
    if [ -n "$shim_name" ]; then args+=(--shim-name "$shim_name"); fi; \
    if [ -n "$source_image" ]; then args+=(--source-image "$source_image"); fi; \
    if [ -n "$git_remote_url" ]; then args+=(--git-remote-url "$git_remote_url"); fi; \
    if [ "$recreate" = "true" ]; then args+=(--recreate); fi; \
    if [ "$skip_git_push_dry_run" = "true" ]; then args+=(--skip-git-push-dry-run); fi; \
    if [ -n "$instance_name" ]; then args+=("$instance_name"); fi; \
    nu "${args[@]}"

download-latest-iso channel="nixos-25.11":
    nu ./vms/download-latest-iso.nu {{ channel }}

export-seed-image instance_name output_path:
    nu ./vms/export-seed-image.nu {{ instance_name }} {{ output_path }}

refresh-base-image source_image="./vms/images/scrubs.qcow2" output_path="./vms/images/scrubs.qcow2" instance_name="scrubs-refresh":
    nu ./vms/refresh-base-image.nu --source-image {{ source_image }} --output-path "{{ output_path }}" --instance-name {{ instance_name }}

audit-instances:
    nu ./vms/audit-instances.nu

seed instance_name="scrubs-seed":
    nu ./vms/seed.nu {{ instance_name }}

vm-shell instance_name:
    limactl shell {{ instance_name }}

scrubs-auth-status profile="":
    @clean_profiles=(personal work); \
    if [ -n "{{ profile }}" ]; then \
        clean_profiles=({{ profile }}); \
    elif [ -f ./vms/settings.env ]; then \
        while IFS= read -r discovered_profile; do \
            clean_profiles+=("$discovered_profile"); \
        done < <(sed -n 's/^SCRUBS_GH_TOKEN_KEYCHAIN_SERVICE__\([A-Z0-9_][A-Z0-9_]*\)=.*/\1/p' ./vms/settings.env | tr '[:upper:]' '[:lower:]' | tr '_' '-'); \
    fi; \
    clean_profiles=(${(u)clean_profiles}); \
    for clean_profile in "${clean_profiles[@]}"; do \
        gh_status=missing; \
        legacy_fragment=""; \
        service="scrubs-gh-token-${clean_profile}"; \
        security find-generic-password -s "$service" -a github.com > /dev/null 2>&1 && gh_status=present; \
        if [ "$clean_profile" = personal ] && [ "$gh_status" = missing ]; then \
            legacy_service="scrubs-gh-token"; \
            if security find-generic-password -s "$legacy_service" -a github.com > /dev/null 2>&1; then \
                gh_status=present; \
                legacy_fragment=" (legacy service $legacy_service/github.com)"; \
            fi; \
        fi; \
        echo "GitHub Keychain item ($service/github.com): $gh_status$legacy_fragment"; \
    done; \
    tailscale_status=missing; \
    tailscale_fragment=""; \
    tailscale_service="scrubs-tailscale-oauth-secret"; \
    legacy_tailscale_service="scrubs-tailscale-auth-key"; \
    deprecated_personal_tailscale_service="scrubs-tailscale-oauth-secret-personal"; \
    deprecated_personal_legacy_tailscale_service="scrubs-tailscale-auth-key-personal"; \
    if security find-generic-password -s "$tailscale_service" -a tailscale > /dev/null 2>&1; then \
        tailscale_status=present; \
    elif security find-generic-password -s "$deprecated_personal_tailscale_service" -a tailscale > /dev/null 2>&1; then \
        tailscale_status=present; \
        tailscale_fragment=" (deprecated profile-scoped service $deprecated_personal_tailscale_service/tailscale)"; \
    elif security find-generic-password -s "$legacy_tailscale_service" -a tailscale > /dev/null 2>&1; then \
        tailscale_status=present; \
        tailscale_fragment=" (legacy auth-key service $legacy_tailscale_service/tailscale)"; \
    elif security find-generic-password -s "$deprecated_personal_legacy_tailscale_service" -a tailscale > /dev/null 2>&1; then \
        tailscale_status=present; \
        tailscale_fragment=" (deprecated profile-scoped legacy auth-key service $deprecated_personal_legacy_tailscale_service/tailscale)"; \
    fi; \
    echo "Tailscale OAuth secret ($tailscale_service/tailscale): $tailscale_status$tailscale_fragment"; \
    codex_status=missing; \
    codex_path="${SCRUBS_CODEX_AUTH_JSON_PATH:-$HOME/.codex/auth.json}"; \
    if [ -s "$codex_path" ] && grep -Eq '"auth_mode"[[:space:]]*:[[:space:]]*"chatgpt"' "$codex_path"; then codex_status=present; fi; \
    echo "Codex auth bundle ($codex_path): $codex_status"

scrubs-auth-set-gh profile="personal":
    @read -s "?GitHub token: " token; \
    service="scrubs-gh-token-{{ profile }}"; \
    echo; \
    security add-generic-password -U -s "$service" -a github.com -w "$token"; \
    echo "Stored GitHub token in macOS Keychain as $service/github.com"

scrubs-auth-set-tailscale profile="":
    @read -s "?Tailscale OAuth client secret: " key; \
    service="scrubs-tailscale-oauth-secret"; \
    echo; \
    security add-generic-password -U -s "$service" -a tailscale -w "$key"; \
    echo "Stored Tailscale OAuth client secret in macOS Keychain as $service/tailscale"

scrubs-auth-set-codex:
    @echo "Codex clean auth is sourced from the host ChatGPT login bundle, not an API key."; \
    echo "Run 'codex login' on the host, then re-run 'just scrubs-auth-status'."

scrubs-auth-delete-gh profile="personal":
    @service="scrubs-gh-token-{{ profile }}"; \
    security delete-generic-password -s "$service" -a github.com || true

scrubs-auth-delete-tailscale profile="":
    @service="scrubs-tailscale-oauth-secret"; \
    deprecated_personal_service="scrubs-tailscale-oauth-secret-personal"; \
    legacy_service="scrubs-tailscale-auth-key"; \
    deprecated_personal_legacy_service="scrubs-tailscale-auth-key-personal"; \
    security delete-generic-password -s "$service" -a tailscale || true; \
    security delete-generic-password -s "$deprecated_personal_service" -a tailscale || true; \
    security delete-generic-password -s "$legacy_service" -a tailscale || true; \
    security delete-generic-password -s "$deprecated_personal_legacy_service" -a tailscale || true

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
