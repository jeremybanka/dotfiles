"""Task-scoped library selection without requiring a local Nix installation."""
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = (Path(__file__).resolve().parents[1]/'templates/dirty-exec.sh').read_text()
FUNCTION = SOURCE[SOURCE.index('append_task_libraries() {'):SOURCE.index('# End task library selection.')]

class TaskLibraries(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.task = self.root/'task'; self.task.mkdir()
        self.lib = self.root/('a'*32+'-glib')/'lib'; self.lib.mkdir(parents=True)

    def run_select(self, listed=True, path=None, fixture=True):
        # Relocate only the immutable-store prefix for a portable real-dir fixture.
        fn = FUNCTION.replace('/nix/store/',str(self.root)+'/') if fixture else FUNCTION
        return subprocess.run(['bash','-eu','-c', '''
die() { echo "$*" >&2; exit 1; }
project_root="$1"
SCRUBS_TASK_LIBRARY_WORKTREES=("$2")
SCRUBS_TASK_LIBRARY_PATHS=("$3")
task_library_binds=(); task_library_env=()
'''+fn+'''
append_task_libraries
printf '%s\\n' "${task_library_binds[@]}" "${task_library_env[@]}"
''','test',str(self.task),str(self.task if listed else self.root),str(path or self.lib)],capture_output=True,text=True)

    def test_scoped_readonly_library_and_search_path(self):
        r=self.run_select(); self.assertEqual(r.returncode,0,r.stderr)
        self.assertEqual(r.stdout.splitlines(),['--ro-bind',str(self.lib),str(self.lib),'--setenv','LD_LIBRARY_PATH',str(self.lib)])

    def test_unlisted_project_gets_no_mount_or_environment(self):
        r=self.run_select(listed=False); self.assertEqual(r.returncode,0); self.assertEqual(r.stdout.strip(),'')

    def test_non_store_directory_rejected(self):
        self.assertNotEqual(self.run_select(fixture=False).returncode,0)

    def test_store_root_not_library_rejected(self):
        self.assertNotEqual(self.run_select(path=self.lib.parent).returncode,0)

    def test_symlink_directory_rejected(self):
        other=self.root/('b'*32+'-glib')/'lib'; other.parent.mkdir(); other.symlink_to(self.lib)
        self.assertNotEqual(self.run_select(path=other).returncode,0)

    def test_clean_policy_resets_inherited_authority(self):
        before=SOURCE.split('source "${SANDBOX_DEFINITION}"')[0]
        self.assertIn('SCRUBS_TASK_LIBRARY_WORKTREES=()',before)
        self.assertIn('SCRUBS_TASK_LIBRARY_PATHS=()',before)
