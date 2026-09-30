# Local Node commands

The Nushell configuration requires Nu 0.116 or newer. It finds the closest
`node_modules/.bin` by walking upward from the current working directory. This
works in a package directory, its `src` directory, and a monorepo. Exactly one
bin directory is selected; missing commands do not fall through to another
ancestor's bin directory.

Discovery runs on directory changes and before each prompt, so installing or
removing packages takes effect at the next prompt. Existing ancestor `.bin`
entries added by mise are replaced by the selected directory. You do not need
an `[env] _.path` entry for interactive local Node commands. Other mise PATH
entries and tool selection remain in place.

On ordinary hosts, the selected directory is added to PATH. On Scrubs guests,
only clean-owned launchers enter the shell's PATH. They resolve the command
again at execution time and enter the dirty sandbox. Discovery stops at the
Git worktree boundary; symlinks outside that boundary are rejected. Clean
system commands and the clean `git`, `gh`, `codex`, `nu`, `carapace`, and `mise`
commands cannot be replaced by project-local launchers. `which break-check`
therefore reports a Scrubs proxy, while `break-check` executes the local package.

Scrubs proxy directories are separate for each shell, normally under
`/run/user/<uid>/scrubs-node-proxies` (falling back to `~/.cache/scrubs/node-proxies`
when no user runtime directory exists). New shells remove directories belonging
to exited processes. These directories are not mounted into dirty space.

## Comline completions

Install a Comline-based CLI such as `break-check` as a normal project dependency.
Then register its native Nushell completion protocol once:

```nu
node-completion add break-check
```

Registration takes effect immediately and persists in
`~/.config/local-node/completions.nuon`. It records command names, not package
paths, options, or executable shell code. The same registration follows local
versions as you change directories. Package upgrades update candidates without
reinstalling an adapter, as long as the Comline protocol remains compatible.

```nu
node-completion list
node-completion remove break-check
```

Command-name completion uses PATH. Argument completion for registered local
commands calls the selected executable's `_comline nushell` endpoint with the
current directory and exact argument boundaries preserved. In Scrubs that call
uses the same sandbox launcher as ordinary execution. Requests have a two-second
timeout, a 256 KiB response limit, and a 1,000-candidate limit. Errors produce no
candidates. Other commands retain the previously configured completer, including
Carapace. This integration does not enable external completions if you disabled
them, auto-probe arbitrary executables, or install package-generated shell code.

Use this registration instead of a per-command Comline `completion install
nushell` adapter. In Scrubs, a package installer sees the synthetic dirty home
and cannot configure the clean interactive shell. Existing native adapters for
the same command should be removed from their reported autoload locations before
using this integration; later autoload registrations can supersede the shared
provider. Native registration also avoids requiring a Carapace spec per CLI.

## Validation

With Nu 0.116+ on PATH:

```sh
python3 -B -m unittest discover -s scripts/tests -p 'test_local_node.py' -v
```

The optional live Scrubs test uses `limactl shell`, stages temporary launcher
copies and a disposable Git project, and removes them afterward. It does not
replace the guest's installed shell configuration. It also queries an installed
`~/lasertag/node_modules/.bin/break-check` when available:

```sh
python3 scripts/tests/test_local_node_guest.py wayforge
```
