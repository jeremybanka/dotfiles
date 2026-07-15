{ pkgs, ... }:
let
  # Keep the Playwright browser closure to Chromium while preserving the exact
  # browser revision paired with the pinned nixpkgs Playwright driver.
  playwrightBrowsers = pkgs.playwright-driver.selectBrowsers {
    withFirefox = false;
    withWebkit = false;
  };
  playwrightDriver = pkgs.playwright-driver // {
    browsers = playwrightBrowsers;
  };
  playwrightTest = pkgs.playwright-test.overrideAttrs (oldAttrs: {
    postFixup = (oldAttrs.postFixup or "") + ''
      substituteInPlace $out/bin/playwright \
        --replace-fail '${pkgs.playwright-driver.browsers}' '${playwrightBrowsers}'
    '';
  });
  playwrightMcp = pkgs.playwright-mcp.override {
    playwright-driver = playwrightDriver;
    playwright-test = playwrightTest;
  };

  browserRuntimeClosure = pkgs.closureInfo {
    rootPaths = [
      playwrightMcp
      pkgs.coreutils
      pkgs.file
      pkgs.glibc.bin
      pkgs.gnugrep
      pkgs.gnused
      pkgs.which
    ];
  };

  codexPlaywrightMcp = pkgs.writeShellApplication {
    name = "codex-playwright-mcp";
    runtimeInputs = [
      pkgs.bubblewrap
      pkgs.coreutils
      pkgs.git
    ];
    text = ''
      current_user="$(id -un)"
      current_uid="$(id -u)"
      real_home="''${HOME:-/home/$current_user}"
      working_dir="$(pwd -P)"
      workspace_root="$(${pkgs.git}/bin/git -C "$working_dir" rev-parse --show-toplevel 2>/dev/null || true)"

      if [[ -z "$workspace_root" ]]; then
        workspace_root="$working_dir"
      fi

      # Never project the real home or a known clean credential surface into
      # the browser sandbox. Codex can still start from those locations, but
      # Playwright receives only its empty synthetic home in that case.
      case "$workspace_root" in
        /|"$real_home"|"$real_home/.codex"|"$real_home/.codex/"*|"$real_home/.ssh"|"$real_home/.ssh/"*|"$real_home/.local/share/scrubs"|"$real_home/.local/share/scrubs/"*)
          workspace_root=""
          ;;
      esac

      runtime_parent="''${XDG_RUNTIME_DIR:-/tmp}/scrubs-playwright-mcp-$current_uid"
      install -d -m 700 "$runtime_parent"
      runtime_dir="$(mktemp -d "$runtime_parent/session.XXXXXXXX")"
      trap 'rm -rf "$runtime_dir"' EXIT INT TERM

      fake_home="$runtime_dir/home"
      mkdir -p "$fake_home"
      chmod 700 "$fake_home"

      declare -a store_binds=()
      while IFS= read -r store_path; do
        [[ -n "$store_path" ]] || continue
        store_binds+=(--ro-bind "$store_path" "$store_path")
      done < ${browserRuntimeClosure}/store-paths

      declare -a workspace_bind=()
      sandbox_working_dir="/home/$current_user"
      if [[ -n "$workspace_root" ]]; then
        workspace_bind=(--bind "$workspace_root" "$workspace_root")
        sandbox_working_dir="$working_dir"
      fi

      sandbox_path="${pkgs.coreutils}/bin:${pkgs.file}/bin:${pkgs.glibc.bin}/bin:${pkgs.gnugrep}/bin:${pkgs.gnused}/bin:${pkgs.which}/bin"

      exec ${pkgs.bubblewrap}/bin/bwrap \
        --die-with-parent \
        --new-session \
        --clearenv \
        --unshare-user \
        --unshare-ipc \
        --unshare-pid \
        --unshare-uts \
        --unshare-cgroup-try \
        --tmpfs / \
        --proc /proc \
        --dev /dev \
        --dir /dev/shm \
        --tmpfs /dev/shm \
        --tmpfs /tmp \
        --dir /nix \
        --dir /nix/store \
        --dir /etc \
        --dir /etc/ssl \
        --dir /etc/ssl/certs \
        --ro-bind /etc/passwd /etc/passwd \
        --ro-bind /etc/group /etc/group \
        --ro-bind /etc/nsswitch.conf /etc/nsswitch.conf \
        --ro-bind /etc/hosts /etc/hosts \
        --ro-bind /etc/resolv.conf /etc/resolv.conf \
        --ro-bind /etc/localtime /etc/localtime \
        --ro-bind /etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-bundle.crt \
        --dir /home \
        --dir "/home/$current_user" \
        --bind "$fake_home" "/home/$current_user" \
        "''${workspace_bind[@]}" \
        "''${store_binds[@]}" \
        --chdir "$sandbox_working_dir" \
        --setenv HOME "/home/$current_user" \
        --setenv USER "$current_user" \
        --setenv LOGNAME "$current_user" \
        --setenv PATH "$sandbox_path" \
        --setenv PWD "$sandbox_working_dir" \
        --setenv SHELL ${pkgs.bash}/bin/bash \
        --setenv TMPDIR /tmp \
        --setenv XDG_CACHE_HOME /tmp/cache \
        --setenv XDG_CONFIG_HOME /tmp/config \
        --setenv XDG_RUNTIME_DIR /tmp/runtime \
        --setenv SSL_CERT_FILE /etc/ssl/certs/ca-bundle.crt \
        -- \
        ${playwrightMcp}/bin/playwright-mcp \
          --headless \
          --isolated \
          --sandbox \
          --output-dir "/home/$current_user/.playwright-mcp" \
          "$@"
    '';
  };
in
{
  environment.systemPackages = [ codexPlaywrightMcp ];
}
