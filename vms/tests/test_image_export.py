"""Exercise export failure boundaries without touching a real Lima guest.

Run with: python3 -B -m unittest discover -s vms/tests -p 'test_image_export.py'
Requires nu on PATH. Fake tools are confined to a temporary LIMA_HOME.
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
import json, os, pathlib, sys
root = pathlib.Path(os.environ['LIMA_HOME'])
mode = os.environ.get('EXPORT_TEST_MODE', '')
args = sys.argv[1:]
name = pathlib.Path(sys.argv[0]).name
with (root / 'calls').open('a') as f:
    f.write(json.dumps([name, *args]) + '\\n')
if name == 'limactl':
    if args[0] == 'list':
        if mode == 'status-failure':
            sys.exit(1)
        stopped = (root / 'stopped').exists()
        status = 'Stopped' if stopped else 'Running'
        if mode == 'still-running':
            status = 'Running'
        print(json.dumps({'status': status}))
    elif args[0] == 'shell':
        (root / 'cleanup-input').write_text(sys.stdin.read())
        if mode == 'cleanup-failure':
            sys.exit(1)
    elif args[0] == 'stop':
        if mode == 'stop-failure':
            sys.exit(1)
        (root / 'stopped').touch()
    else:
        sys.exit(99)
elif name == 'qemu-img':
    if args[0] == 'convert':
        pathlib.Path(args[-1]).write_bytes(b'candidate')
        if mode == 'convert-failure':
            sys.exit(1)
    elif args[0] == 'check' and mode == 'check-failure':
        sys.exit(1)
'''


@unittest.skipUnless(NU, 'nu is required')
class ImageExportTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / 'maintenance').mkdir()
        (self.root / 'maintenance' / 'disk').write_bytes(b'guest disk')
        bindir = self.root / 'bin'
        bindir.mkdir()
        for name in ('limactl', 'qemu-img'):
            tool = bindir / name
            tool.write_text(FAKE_TOOL)
            tool.chmod(0o755)
        self.env = {**os.environ, 'LIMA_HOME': str(self.root),
                    'PATH': str(bindir) + os.pathsep + os.environ['PATH']}
        self.output = self.root / 'candidate.qcow2'

    def run_export(self, mode=''):
        return subprocess.run([NU, str(VMS / 'export-seed-image.nu'),
                               'maintenance', str(self.output)],
                              env={**self.env, 'EXPORT_TEST_MODE': mode},
                              capture_output=True, text=True)

    def calls(self):
        p = self.root / 'calls'
        return [json.loads(s) for s in p.read_text().splitlines()] if p.exists() else []

    def test_success_checks_before_publishing(self):
        result = self.run_export()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.output.read_bytes(), b'candidate')
        self.assertEqual([c[:2] for c in self.calls()], [
            ['limactl', 'list'], ['limactl', 'shell'], ['limactl', 'stop'],
            ['limactl', 'list'], ['qemu-img', 'convert'], ['qemu-img', 'check']])
        self.assertEqual((self.root / 'cleanup-input').read_text(),
                         (VMS / 'templates' / 'prepare-base-image.sh').read_text())
        self.assertFalse(list(self.root.glob('*.partial-*')))

    def test_existing_output_is_untouched(self):
        self.output.write_bytes(b'previous image')
        result = self.run_export()
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.output.read_bytes(), b'previous image')
        self.assertEqual(self.calls(), [])

    def test_failed_cleanup_or_shutdown_never_converts(self):
        for mode in ('status-failure', 'cleanup-failure', 'stop-failure', 'still-running'):
            with self.subTest(mode=mode):
                (self.root / 'calls').unlink(missing_ok=True)
                (self.root / 'stopped').unlink(missing_ok=True)
                result = self.run_export(mode)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertFalse(self.output.exists())
                self.assertFalse(any(c[0] == 'qemu-img' for c in self.calls()))

    def test_failed_conversion_or_check_leaves_no_candidate(self):
        for mode in ('convert-failure', 'check-failure'):
            with self.subTest(mode=mode):
                (self.root / 'stopped').unlink(missing_ok=True)
                result = self.run_export(mode)
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertFalse(self.output.exists())
                self.assertFalse(list(self.root.glob('*.partial-*')))

    def test_refresh_refuses_existing_instance_or_source_overwrite(self):
        source = self.root / 'source.qcow2'
        source.write_bytes(b'original')
        for instance, output in [('maintenance', self.output), ('new', source)]:
            result = subprocess.run([
                NU, str(VMS / 'refresh-base-image.nu'), '--source-image', str(source),
                '--output-path', str(output), '--instance-name', instance],
                env=self.env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0, result.stdout)
            self.assertEqual(source.read_bytes(), b'original')
            self.assertEqual(self.calls(), [])


if __name__ == '__main__':
    unittest.main()
