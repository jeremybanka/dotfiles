"""Regression tests for the pnpm cleanup mutation boundary.

Run with: python3 -B -m unittest discover -s vms/tests -p 'test_pnpm_cleanup.py'
"""
import json
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest

HELPER = Path(__file__).resolve().parents[1] / 'templates/prune-pnpm-stores.sh'
PROXY = '''#!/usr/bin/env python3
import json, os, sys
with open(os.environ['PNPM_TEST_CALLS'], 'a') as f:
    f.write(json.dumps({'cwd': os.getcwd(), 'args': sys.argv[1:]}) + '\\n')
if os.environ.get('PNPM_TEST_FAIL') == '1':
    sys.exit(9)
'''


class PnpmCleanupTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name).resolve()
        proxy = self.home / '.local/bin/scrubs-dirty-exec'
        proxy.parent.mkdir(parents=True)
        proxy.write_text(PROXY)
        proxy.chmod(0o755)
        self.calls = self.home / 'calls.jsonl'

    def project(self, name, *stores):
        root = self.home / name
        root.mkdir(parents=True)
        (root / 'package.json').write_text('{}')
        for store in stores:
            (root / store).mkdir(parents=True)
        return root

    def cleanup(self, *, dry=False, active=False, fail=False):
        return subprocess.run(
            ['bash', '-c', '''
log() { printf '%s %s\\n' "$1" "$2"; }
size_of() { printf 'fixture-size\\n'; }
dirty_space_active() { test "$PNPM_TEST_ACTIVE" = 1; }
source "$1"
scrubs_prune_pnpm_stores
''', 'test', str(HELPER)],
            env={**os.environ, 'HOME': str(self.home),
                 'FREE_DRY_RUN': str(int(dry)), 'PNPM_TEST_ACTIVE': str(int(active)),
                 'PNPM_TEST_FAIL': str(int(fail)), 'PNPM_TEST_CALLS': str(self.calls)},
            capture_output=True, text=True)

    def recorded(self):
        return [json.loads(s) for s in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def test_targets_both_exact_stores_from_package_root(self):
        root = self.project('project with spaces\nand newline', '.pnpm-store', 'node_modules/.pnpm-store')
        result = self.cleanup()
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.recorded()
        self.assertEqual(len(calls), 2)
        self.assertEqual({c['cwd'] for c in calls}, {str(root)})
        self.assertEqual({tuple(c['args']) for c in calls}, {
            ('pnpm', '--store-dir', str(root / store), 'store', 'prune')
            for store in ['.pnpm-store', 'node_modules/.pnpm-store']})

    def test_dry_run_does_not_invoke_package_manager(self):
        self.project('project', '.pnpm-store', 'node_modules/.pnpm-store')
        result = self.cleanup(dry=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('sandboxed pnpm --store-dir', result.stdout)
        self.assertEqual(self.recorded(), [])

    def test_active_dirty_process_skips_all_pruning(self):
        self.project('project', '.pnpm-store')
        result = self.cleanup(active=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('processes are active', result.stdout)
        self.assertEqual(self.recorded(), [])

    def test_skips_symlink_orphan_and_global_stores(self):
        global_store = self.home / '.local/share/pnpm/store'
        global_store.mkdir(parents=True)
        root = self.project('project', 'node_modules')
        (root / 'node_modules/.pnpm-store').symlink_to(global_store, target_is_directory=True)
        (self.home / 'orphan/.pnpm-store').mkdir(parents=True)
        result = self.cleanup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('symlinked pnpm store', result.stdout)
        self.assertIn('orphan pnpm store', result.stdout)
        self.assertIn('Keeping global pnpm store', result.stdout)
        self.assertEqual(self.recorded(), [])

    def test_finds_deep_worktrees_without_traversing_dependencies(self):
        root = self.project('.codex/worktrees/deep/group/repo', 'node_modules/.pnpm-store')
        self.project('.codex/worktrees/deep/group/repo/node_modules/dependency', '.pnpm-store')
        self.project('.cache/cached-project', '.pnpm-store')
        result = self.cleanup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([c['cwd'] for c in self.recorded()], [str(root)])

    def test_skips_virtual_store_with_hidden_registered_project(self):
        root = self.project('project', '.pnpm-store/v11/links/pkg', '.pnpm-store/v11/projects')
        other = self.project('other-project')
        (root / '.pnpm-store/v11/projects/other').symlink_to(other, target_is_directory=True)
        result = self.cleanup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('visibility', result.stdout)
        self.assertEqual(self.recorded(), [])

    def test_skips_symlinked_version_directory(self):
        root = self.project('project', '.pnpm-store')
        outside = self.home / 'outside'
        outside.mkdir()
        (root / '.pnpm-store/v11').symlink_to(outside, target_is_directory=True)
        result = self.cleanup()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('isolation', result.stdout)
        self.assertEqual(self.recorded(), [])

    def test_reports_failure_and_keeps_trying_other_stores(self):
        self.project('project', '.pnpm-store', 'node_modules/.pnpm-store')
        result = self.cleanup(fail=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(len(self.recorded()), 2)
        self.assertIn('Could not prune', result.stdout)


@unittest.skipUnless(shutil.which('nu'), 'nu is required')
class FreeScriptTests(unittest.TestCase):
    def test_embedded_helper_is_valid_bash(self):
        free = HELPER.parents[1] / 'free.nu'
        result = subprocess.run(['nu', '--no-config-file', '-c',
                                 'source "' + str(free) + '"; build-guest-script true'],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(HELPER.read_text(), result.stdout)
        syntax = subprocess.run(['bash', '-n'], input=result.stdout,
                                capture_output=True, text=True)
        self.assertEqual(syntax.returncode, 0, syntax.stderr)
        self.assertIn('exit 1', result.stdout)
