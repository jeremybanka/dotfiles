**Scrubs Spec**
Preamble: current Scrubs-style dev VMs are convenient, but a single credentialed user collapses too many trust zones. In the test VM, code running as the normal user could read GitHub CLI auth, Codex auth, Supermaven config, editor/session state, and other user secrets. The same user also had passwordless root, so compromise of the dev shell meant compromise of the VM. The central fix is not better chmod alone; it is separating “clean operator authority” from “dirty project execution.”

The core model is **clean versus dirty**.

- `doc` is clean.
- `gloves` is dirty.
- The human operator is both, but the system routes commands automatically.

**Trust Model**
`doc` owns trusted system/operator tools and secrets. This includes Nix, GitHub auth, Codex auth, SSH keys, editor identity, and orchestration commands.

`gloves` owns untrusted project execution. This includes mise, Node, npm, pnpm, yarn, bun, Cargo/Rust, Python/pip, Go, Ruby, project scripts, package CLIs, test runners, build scripts, and dev servers.

Project code is assumed hostile. Anything installed or run through package ecosystems is “dirty” by default.

**Policy**
Nix is clean. Mise is dirty.

`doc` may use Nix tools but must not use mise or mise-installed tools directly.

`gloves` may use mise and dirty project tools but must not use Nix as an operator/control plane and must not read `doc` secrets.

`gloves` can do application-like work: bind network ports, run dev servers, read/write `/tmp`, read/write approved project directories, use project-local caches, and execute project toolchains.

`gloves` should not see the whole filesystem. At minimum, it must not be able to traverse `/home/doc`, read clean credentials, use `doc`’s agent sockets, or access clean tool state.

**Users**
Create two primary accounts:

```text
doc     clean operator account
gloves  dirty execution account
```

No shared passwordless root for routine work.

`doc` may have tightly controlled admin escalation for system maintenance.

`gloves` has no sudo, no admin groups, no Docker socket access, no systemd system control, no write access to clean executable locations, and no read access to `doc`’s home.

**Filesystem**
Suggested layout:

```text
/home/doc              mode 0700, clean secrets and operator config
/home/gloves           mode 0700, dirty tool state
/workspaces/<project>  shared project directories
/tmp                   normal shared temp
```

Project directories should be group-shared between `doc` and `gloves`, or otherwise mediated so both can edit/read as needed.

Dirty-generated state should be owned by `gloves` where possible:

```text
node_modules/
target/
dist/
build/
.coverage/
.mise/
```

Clean secrets stay under `doc`:

```text
/home/doc/.config/gh
/home/doc/.codex
/home/doc/.ssh
/home/doc/.gitconfig
```

`gloves` gets separate dirty caches:

```text
/home/gloves/.local/share/mise
/home/gloves/.cache
/home/gloves/.npm
/home/gloves/.pnpm-store
/home/gloves/.cargo
```

**Command Routing**
The operator should not need to think “am I doc or gloves?” Normal command use should route automatically.

Dirty commands should execute as `gloves`:

```text
node npm npx pnpm yarn bun
cargo rustc rustup
python pip pipx uv
go ruby bundle gem
vite vitest jest playwright eslint prettier
make task just
mise
```

Clean commands should execute as `doc`:

```text
nix nixos-rebuild home-manager
git gh ssh scp rsync
codex
editor/shell utilities
security/admin tooling
```

There should be an explicit escape hatch:

```text
as-clean <cmd>   force doc
as-dirty <cmd>   force gloves
```

But common commands should not require it.

**Shell Integration**
Use aliases/functions for interactive ergonomics, but do not rely on aliases alone.

Use PATH shims as the enforcement and compatibility layer. For each dirty command, install a shim earlier in `doc`’s PATH that delegates to `gloves`.

Example behavior:

```bash
npm install
```

runs as:

```bash
sudo -u gloves --set-home --working-directory "$PWD" npm install
```

or through the preferred launcher:

```bash
scrubs-dirty npm install
```

The shim must preserve completion behavior. Carapace should still complete `node _` as if `node` were the real command. The completion layer should know the command identity is `node`, even though execution delegates to `gloves`.

Requirement: Nushell completions must work for dirty shims. `node _`, `npm _`, `pnpm _`, `cargo _`, etc. should complete using the dirty user’s installed tools and metadata.

Possible implementation approach:

- Shim reports the original command name.
- Completion calls are proxied to `gloves`.
- Carapace specs remain keyed by the visible command name.
- Nushell wrappers expose the same command names but execute via `scrubs-dirty`.

**Dirty Launcher**
Implement a central launcher:

```text
scrubs-dirty <cmd> [args...]
```

Responsibilities:

- run as `gloves`
- set `HOME=/home/gloves`
- set working directory to caller’s `$PWD`
- preserve a minimal safe environment
- drop clean env vars and tokens
- preserve terminal behavior
- preserve network ability
- optionally set dirty cache variables
- log routing decisions at debug level without logging secrets

Environment policy:

```text
Preserve:
TERM
COLORTERM
LANG
LC_*
TZ
PWD-like context
editor-neutral display vars only if needed

Drop:
GITHUB_TOKEN
GH_TOKEN
OPENAI_API_KEY
SSH_AUTH_SOCK
CODEX_*
NPM_TOKEN
any *_TOKEN, *_SECRET, *_KEY unless explicitly allowlisted for dirty use
```

**Clean Launcher**
Implement:

```text
scrubs-clean <cmd> [args...]
```

This is mostly an explicit operator escape hatch and may be used internally by login/session plumbing.

**Nix/Mise Boundary**
Nix belongs to `doc`.

Mise belongs to `gloves`.

`doc` should not have mise activated in shell startup. If `doc` invokes `mise`, the shim routes to `gloves` or refuses unsafe forms.

`gloves` should not have access to Nix control operations. Whether `gloves` can execute immutable `/nix/store` binaries is a practical implementation question on NixOS, but it must not be able to modify Nix profiles, run `nix develop` as an authority boundary bypass, or access clean credentials through Nix-managed tooling.

The policy goal is:

```text
Nix tools operate the workstation.
Mise tools execute project code.
Project code runs with gloves on.
```

**Mistake Prevention**
In `doc` sessions:

- Dirty command names are shims, not raw binaries.
- Running dirty tools directly as `doc` should either auto-delegate or fail loudly.
- Direct paths into mise stores should be blocked where feasible.
- `doc` shell startup should warn if mise activation is detected.
- `doc` should not have dirty tool paths in PATH except shim directories.
- Editor tasks and debug profiles should default to dirty routing.

In `gloves` sessions:

- Clean secret paths are unreadable.
- Clean command shims should refuse or proxy back to `doc` only for explicitly safe actions.
- No sudo.

**Editor Integration**
The editor may run as `doc` for access to credentials and extensions, but project execution tasks must route to `gloves`.

VS Code tasks, debug launch configs, integrated terminal profiles, npm script explorer, test runner integrations, and language servers need review.

Default rule:

```text
Editing and auth: doc.
Build/test/run/language toolchains: gloves.
```

Language servers are tricky because they often execute project code or load project plugins. Prefer running language servers as `gloves` if they load project dependencies.

**Security Goals**
A malicious npm package running during `npm install` as `gloves` must not be able to read:

```text
/home/doc/.config/gh
/home/doc/.codex
/home/doc/.ssh
doc SSH agent
doc GitHub token
doc Codex refresh/access tokens
```

A malicious package may read/write the project directory and dirty caches. That is acceptable.

A malicious package may bind local dev ports. That is acceptable.

A malicious package should not become root. That is mandatory.

A malicious package should not modify clean tool configuration. That is mandatory.

**Non-Goals**
This is not intended to make hostile code safe in an absolute sense.

It does not prevent dirty code from exfiltrating dirty-project data over the network.

It does not fully replace containers, MAC policy, or network sandboxing.

It is primarily a practical, durable trust boundary for credential protection during normal development.

**Acceptance Tests**
From a dirty npm script running as `gloves`:

```bash
test ! -r /home/doc/.config/gh/hosts.yml
test ! -r /home/doc/.codex/auth.json
test ! -r /home/doc/.ssh/id_ed25519
test "$(id -un)" = "gloves"
sudo -n true should fail
```

From `doc`:

```bash
npm install
```

must execute as `gloves`.

From `doc`:

```bash
node -p 'process.getuid && process.getuid()'
```

must report `gloves`’ UID.

From `doc`:

```bash
gh auth status
codex ...
```

must execute as `doc`.

Completions:

```text
node <TAB>
npm <TAB>
pnpm <TAB>
cargo <TAB>
```

must still work through Nushell/Carapace with the visible command names.

Tool boundary:

```bash
which npm
```

from `doc` should resolve to a Scrubs shim.

```bash
which npm
```

from `gloves` should resolve to mise-managed dirty tooling.

**Open Design Questions**
How should project ownership work: `doc` owns source and `gloves` owns generated artifacts, or both use a shared group?

Should dirty commands run directly as `gloves`, or inside an additional `bubblewrap`/systemd sandbox?

Should network egress be unrestricted for `gloves`, or profile-controlled later?

Should language servers run as `gloves` by default?

How strict should Nix denial for `gloves` be, given `/nix/store` is naturally world-readable/executable on NixOS?

**First Implementation Slice**
Create users and permissions.

Create `scrubs-dirty`.

Create dirty command shims for Node/npm/pnpm/bun/cargo/python/go/ruby/mise.

Ensure Nushell and Carapace completions work through shims.

Move mise activation to `gloves`.

Remove mise from `doc`.

Move credentials to `doc`, lock down `/home/doc`.

Make `gloves` unable to sudo.

Add tests proving dirty scripts cannot read clean secrets.

Then iterate into editor integration and optional sandboxing.