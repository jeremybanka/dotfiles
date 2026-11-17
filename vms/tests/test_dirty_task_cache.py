"""Exercise the exact task-cache validator without needing a Linux namespace."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

TEMPLATE = Path(__file__).resolve().parents[1] / 'templates/dirty-exec.sh'
SOURCE = TEMPLATE.read_text()
VALIDATOR = SOURCE[SOURCE.index('configure_task_cache() {'):SOURCE.index('# End task-cache validation.')]


class TaskCacheTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve() / 'task with spaces'
        self.root.mkdir()
        self.cache = self.root / '.scrubs-dirty-cache'

    def run_validator(self, override, root=None):
        return subprocess.run(['bash', '-eu', '-c', '''
die() { echo "$*" >&2; exit 1; }
project_root="$1"
dirty_cache_root=original
runtime_cache_root=runtime
helper_closure_cache_root=closures
mise_cache_root=mise
''' + VALIDATOR + '''
configure_task_cache
printf '%s\\n' "$dirty_cache_root" "$runtime_cache_root" "$helper_closure_cache_root" "$mise_cache_root"
''', 'test', str(self.root) if root is None else root],
                              env={**os.environ, 'SCRUBS_DIRTY_CACHE_ROOT': override},
                              text=True, capture_output=True)

    def test_default_unchanged(self):
        result = self.run_validator('')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ['original', 'runtime', 'closures', 'mise'])

    def test_exact_reserved_task_directory_selects_payload_caches_without_mutation(self):
        result = self.run_validator(str(self.cache))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), [str(self.cache), 'runtime', 'closures', str(self.cache / 'mise')])
        self.assertFalse(self.cache.exists())

    def test_arbitrary_or_ambiguous_paths_refused(self):
        for path in (str(self.root), str(self.root.parent), '/tmp/cache', '.scrubs-dirty-cache',
                     str(self.cache) + '/', str(self.root) + '/x/../.scrubs-dirty-cache'):
            with self.subTest(path=path):
                self.assertNotEqual(self.run_validator(path).returncode, 0)
        self.assertNotEqual(self.run_validator(str(self.cache), root='').returncode, 0)

    def test_symlink_root_and_nested_cache_refused(self):
        outside = self.root.parent / 'outside'
        outside.mkdir()
        self.cache.symlink_to(outside, target_is_directory=True)
        self.assertNotEqual(self.run_validator(str(self.cache)).returncode, 0)
        self.cache.unlink()
        self.cache.mkdir()
        (self.cache / 'bun').symlink_to(outside, target_is_directory=True)
        self.assertNotEqual(self.run_validator(str(self.cache)).returncode, 0)
        self.assertEqual(list(outside.iterdir()), [])

    def test_existing_file_refused_and_preserved(self):
        self.cache.write_text('user data')
        self.assertNotEqual(self.run_validator(str(self.cache)).returncode, 0)
        self.assertEqual(self.cache.read_text(), 'user data')

    def test_existing_owned_directories_allowed(self):
        (self.cache / 'bun/install/cache').mkdir(parents=True)
        self.assertEqual(self.run_validator(str(self.cache)).returncode, 0)

    def test_namespace_isolation_flags_preserved(self):
        for flag in ('--clearenv', '--unshare-user', '--unshare-ipc', '--unshare-pid',
                     '--unshare-uts', '--tmpfs /', '--ro-bind "${mise_root}"'):
            self.assertIn(flag, SOURCE)
        self.assertIn('--setenv MISE_CACHE_DIR "${mise_cache_root}"', SOURCE)
        self.assertNotIn('--bind "${HOME}"', SOURCE)


if __name__ == '__main__':
    unittest.main()
