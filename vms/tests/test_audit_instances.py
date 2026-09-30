"""Check Codex pin drift without contacting real Lima guests. Requires nu on PATH."""
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

VMS = Path(__file__).resolve().parents[1]
NU = shutil.which('nu')
FAKE_LIMA = '''#!/usr/bin/env python3
import json, os, sys
if sys.argv[1] == 'list':
    print(json.dumps({'name': 'fixture', 'status': 'Running'}))
elif 'nixos-version' in sys.argv[-1]:
    print(os.environ['AUDIT_TEST_VERSION'])
else:
    print(os.environ['AUDIT_TEST_LOCK'])
'''


@unittest.skipUnless(NU, 'nu is required')
class AuditInstancesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        tool = root / 'limactl'
        tool.write_text(FAKE_LIMA)
        tool.chmod(0o755)
        self.target = json.loads((VMS / 'flake.lock').read_text())
        self.guest = copy.deepcopy(self.target)
        self.env = {**os.environ, 'PATH': f'{root}{os.pathsep}{os.environ["PATH"]}'}
        release = self.target['nodes']['nixpkgs']['original']['ref'].removeprefix('nixos-')
        self.version = {
            'nixosVersion': release,
            'nixpkgsRevision': self.target['nodes']['nixpkgs']['locked']['rev'],
        }

    def audit(self):
        result = subprocess.run(
            [NU, '--no-config-file', str(VMS / 'audit-instances.nu'), '--json'],
            env={**self.env, 'AUDIT_TEST_VERSION': json.dumps(self.version),
                 'AUDIT_TEST_LOCK': json.dumps(self.guest)},
            capture_output=True, text=True, check=True,
        )
        return json.loads(result.stdout)[0]

    def test_matching_codex_pin_is_current(self):
        self.assertEqual(self.audit()['assessment'], 'current')

    def test_codex_only_drift_is_stale(self):
        self.guest['nodes']['nixpkgs-codex']['locked']['rev'] = '0' * 40
        row = self.audit()
        self.assertEqual(row['assessment'], 'stale')
        self.assertIn('nixpkgs-codex:', row['note'])

    def test_full_revision_is_compared(self):
        rev = self.guest['nodes']['nixpkgs-codex']['locked']['rev']
        self.guest['nodes']['nixpkgs-codex']['locked']['rev'] = rev[:7] + '0' * 33
        self.assertEqual(self.audit()['assessment'], 'stale')

    def test_legacy_guest_is_unknown(self):
        del self.guest['nodes']['nixpkgs-codex']
        row = self.audit()
        self.assertEqual(row['assessment'], 'unknown')
        self.assertIn('re-bootstrap', row['note'])

    def test_mismatched_running_system_does_not_trust_codex_pin(self):
        self.guest['nodes']['nixpkgs']['locked']['rev'] = '0' * 40
        row = self.audit()
        self.assertEqual(row['assessment'], 'unknown')
        self.assertEqual(row['nixpkgs_codex'], '')


if __name__ == '__main__':
    unittest.main()
