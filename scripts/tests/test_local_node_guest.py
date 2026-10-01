"""Opt-in live Scrubs test, using staged launchers and disposable projects.

python3 scripts/tests/test_local_node_guest.py wayforge
Requires limactl on PATH. Never replaces the guest's installed shell/launcher.
"""
import io
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tarfile
import uuid

ROOT = Path(__file__).resolve().parents[2]
instance = sys.argv[1]
run_id = 'local-node-test-' + uuid.uuid4().hex
lima = os.environ.get('LIMACTL', 'limactl')


def guest(command, **kwargs):
    return subprocess.run([lima, 'shell', instance, '--',
                           '/run/current-system/sw/bin/bash', '-lc', command],
                          check=True, **kwargs)


home = guest('printf %s "$HOME"', capture_output=True, text=True).stdout
stage = home + '/.local/libexec/scrubs/' + run_id
fixture = home + '/.cache/' + run_id
module = (ROOT / 'home/.config/nushell/local-node.nu').read_text()
module = module.replace('scrubs dirty-exec.sh', f'scrubs {run_id}/dirty-exec.sh')
module = module.replace('scrubs/dirty-exec.sh', f'scrubs/{run_id}/dirty-exec.sh')
module = module.replace('.config comline completions.nuon', f'.config {run_id} completions.nuon')
launcher = (ROOT / 'vms/templates/dirty-exec.sh').read_text().replace(
    '${HOME}/.config/nushell/local-node-path.nu', stage + '/local-node-path.nu')
probe = '''#!/usr/bin/env node
const fs = require('node:fs');
if (process.argv[2] === '_comline') {
  console.log(JSON.stringify([{value:'--local', display:'--local', description:'sandbox'}]));
} else {
  const home = process.env.HOME;
  console.log(JSON.stringify({cwd:process.cwd(), args:process.argv.slice(2),
    path:process.env.PATH, cleanAuth:fs.existsSync(home+'/.local/share/scrubs/clean-auth'),
    cleanGh:fs.existsSync(home+'/.local/bin/gh'),
    cleanConfig:fs.existsSync(home+'/.config/nushell/config.nu'),
    script:__filename}));
}
'''
driver = '''use ./local-node.nu *
use std/assert

def main [fixture: string] {
    cd $fixture
    local-node-refresh
    let proxy = (which probe | get 0.path)
    assert ($proxy | str contains scrubs-node-proxies)
    assert ((which gh | get 0.path) != ($env.LOCAL_NODE_PATH | path join gh))
    assert ((which not-executable | is-empty))
    assert ((which ls | get 0.path) != ($env.LOCAL_NODE_PATH | path join ls))
    let child_proxy = (^/run/current-system/sw/bin/nu --no-config-file ($env.FILE_PWD | path join child.nu) | str trim)
    assert ($child_proxy != $env.LOCAL_NODE_PROXY_DIR)
    assert ($proxy | path exists)
    rm --recursive $child_proxy
    let result = (^probe 'two words' '' '--literal' | from json)
    assert equal $result.args ['two words' '' '--literal']
    assert equal $result.cwd $fixture
    assert (not $result.cleanAuth)
    assert (not $result.cleanGh)
    assert (not $result.cleanConfig)
    assert ($result.path | str starts-with ($fixture | path join node_modules .bin))
    comline-completion add probe
    let elapsed = (timeit {
        let candidates = (local-node-candidates probe [--])
        assert equal $candidates.0.value '--local'
    })
    print $"Sandbox completion latency: ($elapsed)"
    cd child/src
    local-node-refresh
    let nested = (^probe | from json)
    assert ($nested.script | str contains '/child/node_modules/.bin/')
    assert equal $nested.cwd ($fixture | path join child src)
    let node_path = (^($env.FILE_PWD | path join node) -p process.env.PATH | str trim)
    assert ($node_path | str starts-with ($fixture | path join child node_modules .bin))
    # Remove the nearest executable: do not fall back to the root's probe.
    rm ../node_modules/.bin/probe
    # An already-held proxy must also fail, even before a prompt refresh.
    let stale = (^$proxy | complete)
    assert ($stale.exit_code != 0)
    local-node-refresh
    assert (which probe | is-empty)
    assert ((local-node-candidates probe []) == null)
    # Reject a local command whose symlink escapes the project mount.
    let escaped = (^($env.FILE_PWD | path join dirty-exec.sh) --local-node escaped | complete)
    assert ($escaped.exit_code != 0)
    cd $env.HOME
    local-node-refresh
    assert equal $env.LOCAL_NODE_PATH ''
    let consumer = ($env.HOME | path join lasertag)
    if ($consumer | path join node_modules .bin break-check | path exists) {
        cd $consumer
        comline-completion add break-check
        local-node-refresh
        assert (which break-check | is-not-empty)
        let candidates = (local-node-candidates break-check [--])
        assert ('--base-dir' in ($candidates | get display))
        print 'Installed break-check completion: passed'
    }
    rm --recursive $env.LOCAL_NODE_PROXY_DIR
    print 'Scrubs local-node integration: passed'
}
'''
files = {'local-node.nu': module, 'dirty-exec.sh': launcher,
         'local-node-path.nu': (ROOT / 'home/.config/nushell/local-node-path.nu').read_text(),
         'driver.nu': driver, 'probe': probe,
         'child.nu': 'use ./local-node.nu *\nlocal-node-refresh\nprint $env.LOCAL_NODE_PROXY_DIR\n'}
archive = io.BytesIO()
with tarfile.open(fileobj=archive, mode='w') as tar:
    for name, text in files.items():
        data = text.encode()
        info = tarfile.TarInfo(name)
        info.size = len(data)
        info.mode = 0o755 if name in ['dirty-exec.sh', 'probe'] else 0o644
        tar.addfile(info, io.BytesIO(data))
q = shlex.quote
try:
    guest(f'mkdir -p {q(stage)}; tar -xf - -C {q(stage)}', input=archive.getvalue())
    guest(f'''set -eu
mkdir -p {q(fixture)}/node_modules/.bin {q(fixture)}/child/node_modules/.bin {q(fixture)}/child/src
cd {q(fixture)}
/run/current-system/sw/bin/git init -q
printf '[tools]\\nnode = "26.10.0"\\n' > mise.toml
cp {q(stage)}/probe node_modules/.bin/probe
cp {q(stage)}/probe node_modules/.bin/gh
cp {q(stage)}/probe node_modules/.bin/ls
ln -s ./dirty-exec.sh {q(stage)}/node
cp {q(stage)}/probe child/node_modules/.bin/probe
printf 'not executable' > node_modules/.bin/not-executable
ln -s /run/current-system/sw/bin/true child/node_modules/.bin/escaped
export MISE_TRUSTED_CONFIG_PATHS={q(fixture)}
/run/current-system/sw/bin/nu --no-config-file {q(stage)}/driver.nu {q(fixture)}
''')
finally:
    guest(f'rm -rf {q(stage)} {q(fixture)} {q(home + "/.config/" + run_id)}')
