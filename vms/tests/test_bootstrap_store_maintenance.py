"""Check bootstrap cleanup ordering and failure handling without a real guest.

Run: python3 -B -m unittest discover -s vms/tests -p 'test_bootstrap_store_maintenance.py'
"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

VMS = Path(__file__).resolve().parents[1]
NU = shutil.which('nu')
FAKE_TOOL = '''#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
root = pathlib.Path(os.environ['BOOTSTRAP_TEST_ROOT'])
mode = os.environ.get('BOOTSTRAP_TEST_MODE', '')
event = name
if name == 'ssh':
    command = args[-1]
    if 'bootstrap-store-maintenance.sh' in command:
        event = 'maintenance-before' if ' before' in command else 'maintenance-after'
    elif 'guest-apply.sh' in command:
        event = 'apply'
with (root / 'calls').open('a') as f:
    f.write(json.dumps([event, *args]) + '\\n')
if name == 'limactl':
    if args[0] == 'list':
        print(json.dumps({'status': 'Running', 'sshLocalPort': 60022}))
elif name == 'scp':
    payload = pathlib.Path(args[-2])
    if not (payload / 'bootstrap-store-maintenance.sh').is_file():
        sys.exit(88)
elif name == 'ssh':
    if mode == event + '-failure':
        print('injected failure', file=sys.stderr)
        sys.exit(9)
elif name == 'sudo':
    assert args.pop(0) == '-n'
    sys.exit(subprocess.run(args).returncode)
elif name == 'nix-store':
    if mode == 'gc-failure':
        sys.exit(9)
elif name == 'fstrim':
    if mode == 'trim-failure':
        sys.exit(9)
elif name == 'df':
    print('fixture disk usage')
'''


class Fixture(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.env = {k: v for k, v in os.environ.items()
                    if not k.startswith('SCRUBS_')}
        self.env.update(BOOTSTRAP_TEST_ROOT=str(self.root),
                        HOME=str(self.root / 'operator'),
                        PATH=str(self.bin) + os.pathsep + os.environ['PATH'])
        Path(self.env['HOME']).mkdir()

    def tools(self, *names):
        for name in names:
            p = self.bin / name
            p.write_text(FAKE_TOOL)
            p.chmod(0o755)

    def calls(self):
        p = self.root / 'calls'
        return [json.loads(s) for s in p.read_text().splitlines()] if p.exists() else []


class StoreMaintenanceTests(Fixture):
    def setUp(self):
        super().setUp()
        self.tools('sudo', 'nix-store', 'fstrim', 'df')
        self.env.update(SCRUBS_NIX_STORE=str(self.bin / 'nix-store'),
                        SCRUBS_FSTRIM=str(self.bin / 'fstrim'))

    def run_maintenance(self, phase, mode=''):
        return subprocess.run(
            ['sh', str(VMS / 'templates/bootstrap-store-maintenance.sh'), phase],
            env={**self.env, 'BOOTSTRAP_TEST_MODE': mode},
            capture_output=True, text=True)

    def test_collects_without_deleting_profile_generations(self):
        for phase in ('before', 'after'):
            with self.subTest(phase=phase):
                (self.root / 'calls').unlink(missing_ok=True)
                result = self.run_maintenance(phase)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual([c for c in self.calls() if c[0] == 'nix-store'],
                                 [['nix-store', '--gc']])
                self.assertEqual([c for c in self.calls() if c[0] == 'fstrim'],
                                 [['fstrim', '-av']])

    def test_gc_failure_stops_before_trim(self):
        result = self.run_maintenance('before', 'gc-failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('check guest disk usage', result.stderr)
        self.assertFalse(any(c[0] == 'fstrim' for c in self.calls()))

    def test_unsupported_trim_warns_without_failing_bootstrap(self):
        result = self.run_maintenance('after', 'trim-failure')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('freed blocks may remain allocated on the host', result.stderr)

    def test_missing_trim_is_optional(self):
        (self.bin / 'fstrim').unlink()
        result = self.run_maintenance('after')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(c[0] == 'fstrim' for c in self.calls()))

    def test_invalid_phase_does_not_collect(self):
        result = self.run_maintenance('invalid')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])


@unittest.skipUnless(NU, 'nu is required')
class BootstrapMaintenanceOrderingTests(Fixture):
    def setUp(self):
        super().setUp()
        self.tools('limactl', 'ssh', 'scp')
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        shutil.copytree(VMS, self.repo / 'vms',
                        ignore=shutil.ignore_patterns('images', 'keys', 'settings.env', '__pycache__'))
        # Bootstrap only reads these source files; all generated state stays in
        # this test's repository, LIMA_HOME, and temporary cache.
        (self.repo / 'home').symlink_to(VMS.parent / 'home', target_is_directory=True)
        keys = self.repo / 'vms/keys'
        keys.mkdir()
        (keys / 'scrubs-dev').write_text('fixture key')
        (keys / 'scrubs-dev.pub').write_text('ssh-ed25519 fixture')
        self.lima = self.root / 'lima'
        (self.lima / 'maintenance').mkdir(parents=True)
        self.image = self.root / 'seed.qcow2'
        self.image.write_bytes(b'fixture image')
        self.env.update(LIMA_HOME=str(self.lima), TMPDIR=str(self.root / 'cache'),
                        SCRUBS_SSH_PORT='60022')

    def run_bootstrap(self, mode=''):
        return subprocess.run(
            [NU, str(self.repo / 'vms/bootstrap.nu'), '--for-base-image',
             '--source-image', str(self.image), 'maintenance'],
            env={**self.env, 'BOOTSTRAP_TEST_MODE': mode},
            capture_output=True, text=True, timeout=30)

    def events(self):
        return [c[0] if c[0] != 'limactl' else 'lima-' + c[1]
                for c in self.calls()]

    def test_maintenance_surrounds_apply_and_restart(self):
        result = self.run_bootstrap()
        self.assertEqual(result.returncode, 0, result.stderr)
        events = self.events()
        self.assertLess(events.index('scp'), events.index('maintenance-before'))
        self.assertLess(events.index('maintenance-before'), events.index('apply'))
        self.assertLess(events.index('apply'), events.index('lima-stop'))
        self.assertLess(events.index('lima-stop'), events.index('maintenance-after'))
        self.assertIn('Scrubs guest is ready.', result.stdout)

    def test_pre_cleanup_failure_does_not_apply_or_reboot(self):
        result = self.run_bootstrap('maintenance-before-failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('apply', self.events())
        self.assertNotIn('lima-stop', self.events())
        self.assertIn('free.nu maintenance --dry-run', result.stderr)

    def test_post_cleanup_failure_is_not_reported_as_ready(self):
        result = self.run_bootstrap('maintenance-after-failure')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('apply', self.events())
        self.assertIn('lima-stop', self.events())
        self.assertNotIn('Scrubs guest is ready.', result.stdout)


if __name__ == '__main__':
    unittest.main()
