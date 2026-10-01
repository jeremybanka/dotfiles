"""Nushell integration tests. Run with Nu 0.116+ on PATH.

python3 -B -m unittest discover -s scripts/tests -p 'test_local_node.py' -v
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
MODULE = ROOT / 'home/.config/nushell/local-node.nu'
RESOLVER = MODULE.with_name('local-node-path.nu')
NU = shutil.which('nu')


def literal(value):
    return "'" + str(value).replace("'", "''") + "'"


@unittest.skipUnless(NU, 'requires Nushell 0.116+')
class LocalNodeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='local node ')
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name).resolve()
        self.project = self.home / 'project'
        self.project.mkdir()
        self.env = {**os.environ, 'HOME': str(self.home)}
        self.prefix = f'use {literal(MODULE)} *; '

    def run_nu(self, code, cwd=None):
        result = subprocess.run([NU, '-n', '-c', self.prefix + code],
                                env=self.env, cwd=cwd or self.project,
                                capture_output=True, text=True, timeout=12)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout

    def tool(self, directory, name='demo', value='outer'):
        bindir = directory / 'node_modules/.bin'
        bindir.mkdir(parents=True, exist_ok=True)
        tool = bindir / name
        tool.write_text('#!/bin/sh\nprintf \'%s\\n\' ' + "'" +
                        json.dumps([{'value': value, 'description': 'fixture',
                                     'display': 'friendly'}]) + "'\n")
        tool.chmod(0o755)
        return tool

    def register(self, name='demo'):
        directory = self.home / '.config/comline'
        directory.mkdir(parents=True, exist_ok=True)
        # JSON is a subset of NUON for these simple values.
        (directory / 'completions.nuon').write_text(json.dumps([name]))

    def test_nearest_directory_and_pwd_preserved(self):
        self.tool(self.project)
        child = self.project / 'packages/child'
        self.tool(child, value='inner')
        src = child / 'src'
        src.mkdir()
        output = self.run_nu('local-node-refresh; {path: $env.LOCAL_NODE_PATH, pwd: $env.PWD} | to json', src)
        self.assertEqual(json.loads(output), {'path': str(child / 'node_modules/.bin'), 'pwd': str(src)})

    def test_new_nearer_bin_and_removal_at_same_pwd(self):
        self.tool(self.project)
        child = self.project / 'child'
        child.mkdir()
        code = '''local-node-refresh
let before = $env.LOCAL_NODE_PATH
mkdir node_modules/.bin
local-node-refresh
let after = $env.LOCAL_NODE_PATH
rm -r node_modules
local-node-refresh
[$before $after $env.LOCAL_NODE_PATH] | to json'''
        result = json.loads(self.run_nu(code, child))
        self.assertEqual(result, [str(self.project / 'node_modules/.bin'),
                                  str(child / 'node_modules/.bin'),
                                  str(self.project / 'node_modules/.bin')])

    def test_leaving_project_removes_own_path(self):
        self.tool(self.project)
        output = self.run_nu(f'local-node-refresh; let old = $env.LOCAL_NODE_PATH; cd {literal(self.home)}; local-node-refresh; $old in $env.PATH | to json')
        self.assertFalse(json.loads(output))

    def test_root_boundary_and_escape_symlink(self):
        self.tool(self.home)
        code = f'use {literal(RESOLVER)} nearest-node-bin; nearest-node-bin $env.PWD --root $env.PWD | to json'
        self.assertIsNone(json.loads(self.run_nu(code)))
        (self.project / 'node_modules').symlink_to(self.home / 'node_modules')
        self.assertIsNone(json.loads(self.run_nu(code)))

    def test_registration_persists_and_removes(self):
        self.run_nu('comline-completion add demo')
        self.assertEqual(json.loads(self.run_nu('comline-completion list | to json')), ['demo'])
        self.run_nu('comline-completion remove demo')
        self.assertEqual(json.loads(self.run_nu('comline-completion list | to json')), [])

    def test_completion_selects_current_local_version(self):
        self.register()
        self.tool(self.project)
        child = self.project / 'child'
        self.tool(child, value='inner')
        for cwd, expected in [(self.project, 'outer'), (child, 'inner')]:
            result = json.loads(self.run_nu('local-node-candidates demo [--] | to json', cwd))
            self.assertEqual(result[0]['value'], expected)
            self.assertEqual(result[0]['display'], 'friendly')

    def test_no_per_command_parent_fallback(self):
        self.register()
        self.tool(self.project)
        child = self.project / 'child'
        self.tool(child, name='other')
        self.assertIsNone(json.loads(self.run_nu('local-node-candidates demo [] | to json', child)))

    def test_existing_mise_ancestor_path_is_removed(self):
        self.tool(self.project)
        child = self.project / 'child'
        self.tool(child, name='other')
        parent_bin = self.project / 'node_modules/.bin'
        result = self.run_nu(f'$env.PATH = ($env.PATH | prepend {literal(parent_bin)}); local-node-refresh; which demo | to json', child)
        self.assertEqual(json.loads(result), [])

    def test_symlinked_bin_within_boundary(self):
        target = self.project / 'tools'
        self.tool(target)
        (self.project / 'node_modules').mkdir()
        (self.project / 'node_modules/.bin').symlink_to(target / 'node_modules/.bin')
        code = f'use {literal(RESOLVER)} nearest-node-bin; nearest-node-bin $env.PWD --root $env.PWD | to json'
        self.assertEqual(json.loads(self.run_nu(code)), str(self.project / 'node_modules/.bin'))

    def test_only_registered_commands_are_executed(self):
        tool = self.tool(self.project)
        tool.write_text('#!/bin/sh\ntouch ran\n')
        self.assertIsNone(json.loads(self.run_nu('local-node-candidates demo [] | to json')))
        self.assertFalse((self.project / 'ran').exists())

    def test_timeout_and_invalid_output_are_quiet(self):
        self.register()
        tool = self.tool(self.project)
        for body in ['sleep 10', 'echo not-json', 'echo broken >&2; exit 1']:
            tool.write_text('#!/bin/sh\n' + body + '\n')
            self.assertEqual(json.loads(self.run_nu('local-node-candidates demo [] | to json')), [])

    def test_response_and_candidate_limits(self):
        self.register()
        tool = self.tool(self.project)
        data = [{'value': str(i)} for i in range(1100)]
        tool.write_text("#!/bin/sh\nprintf '%s' '" + json.dumps(data) + "'\n")
        result = json.loads(self.run_nu('local-node-candidates demo [] | to json'))
        self.assertEqual(len(result), 1000)
        tool.write_text("#!/bin/sh\nprintf '%s' '" + json.dumps([{'value': 'x' * 300000}]) + "'\n")
        self.assertEqual(json.loads(self.run_nu('local-node-candidates demo [] | to json')), [])

    def test_real_completion_dispatch_and_fallback(self):
        self.register()
        self.tool(self.project, value='--fixture')
        code = '''$env.config.completions.external.completer = {|buffer: string, place: record| [{value: '--fallback'}] }
local-node-init
{local: ('demo --' | commandline complete --detailed), fallback: ('unknown --' | commandline complete --detailed)} | to json'''
        result = json.loads(self.run_nu(code))
        self.assertIn('--fixture', [item['value'] for item in result['local']])
        self.assertIn('--fallback', [item['value'] for item in result['fallback']])

    def test_argument_boundaries(self):
        self.register()
        tool = self.tool(self.project)
        tool.write_text('#!/bin/sh\nprintf \'%s\\n\' "$@" > args\necho \'[]\'\n')
        self.run_nu('local-node-candidates demo ["two words" "" "$(touch bad)"] | to json')
        self.assertEqual((self.project / 'args').read_text().splitlines(),
                         ['_comline', 'nushell', 'two words', '', '$(touch bad)'])
        self.assertFalse((self.project / 'bad').exists())
