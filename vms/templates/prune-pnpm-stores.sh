# Sourced by free.nu's clean-side Bash script. Package-manager execution still
# goes through the project's mise runtime and dirty sandbox.
scrubs_prune_pnpm_stores() {
  local scan_root="${1:-$HOME}"
  local dirty_exec="$HOME/.local/bin/scrubs-dirty-exec"
  local candidate store_dir project_dir size version_dir registry registered_project
  local unsafe_store registered_count
  local failed=0

  if dirty_space_active; then
    log WARN "Dirty-space processes are active; skipping pnpm store cleanup"
    return 0
  fi

  if [[ ! -x "$dirty_exec" ]]; then
    log WARN "scrubs-dirty-exec is missing; skipping pnpm store cleanup"
    return 0
  fi

  # Do not descend into installed packages, Git objects, tool installs, or
  # unrelated user caches. Inspect node_modules/.pnpm-store directly instead.
  # NUL delimiters support project paths containing spaces or newlines.
  while IFS= read -r -d '' candidate; do
    case "$candidate" in
      */node_modules) store_dir="$candidate/.pnpm-store" ;;
      */.pnpm-store) store_dir="$candidate" ;;
      *) continue ;;
    esac
    [[ -d "$store_dir" ]] || continue
    if [[ -L "$store_dir" ]]; then
      log WARN "Skipping symlinked pnpm store at $store_dir"
      continue
    fi

    project_dir="${store_dir%/.pnpm-store}"
    case "$project_dir" in
      */node_modules) project_dir="${project_dir%/node_modules}" ;;
    esac
    if [[ ! -f "$project_dir/package.json" ]]; then
      log WARN "Skipping orphan pnpm store at $store_dir; no package.json at $project_dir"
      continue
    fi

    # Even a repo-local store may have been shared with another worktree.
    # Never let global-virtual-store GC operate with an incomplete project view.
    unsafe_store=0
    for version_dir in "$store_dir"/v*; do
      [[ -d "$version_dir" ]] || continue
      if [[ -L "$version_dir" ]]; then
        unsafe_store=1
        break
      fi
      [[ -d "$version_dir/links" ]] || continue
      [[ -n "$(find "$version_dir/links" -mindepth 1 -print -quit)" ]] || continue
      registered_count=0
      for registry in "$version_dir/projects"/*; do
        [[ -L "$registry" ]] || continue
        registered_count=$((registered_count + 1))
        registered_project="$(readlink -f "$registry")" || registered_project=""
        case "$registered_project" in
          "$project_dir" | "$project_dir"/*) ;;
          *) unsafe_store=1 ;;
        esac
      done
      [[ "$registered_count" -gt 0 ]] || unsafe_store=1
    done
    if [[ "$unsafe_store" == "1" ]]; then
      log WARN "Skipping $store_dir; virtual-store project visibility or version-directory isolation is incomplete"
      continue
    fi

    size="$(size_of "$store_dir")"
    log INFO "Pruning exact pnpm store $store_dir ($size)"
    if [[ "$FREE_DRY_RUN" == "1" ]]; then
      log INFO "dry-run: would run sandboxed pnpm --store-dir $store_dir store prune from $project_dir"
    elif ! (cd "$project_dir" && "$dirty_exec" pnpm --store-dir "$store_dir" store prune); then
      log WARN "Could not prune $store_dir with this project's mise-managed pnpm"
      failed=1
    fi
  done < <(find "$scan_root" -type d \( \
    -name node_modules -o -name .pnpm-store -o -name .git -o \
    -name .local -o -name .cache -o -name .bun -o -name .rustup -o \
    -name target \
    \) -prune -print0)

  # A shared/global store can register projects outside the dirty sandbox's
  # view. Pruning it there could garbage-collect a live global virtual store.
  # Leave it intact instead of exposing unrelated projects or clean home data.
  if [[ -d "$HOME/.local/share/pnpm/store" ]]; then
    log INFO "Keeping global pnpm store; its registered projects are outside a single dirty worktree"
  fi
  return "$failed"
}
