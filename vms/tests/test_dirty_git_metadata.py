"""Fixture tests for clean-policy-authorized linked-worktree metadata selection."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

TEMPLATE = Path(__file__).resolve().parents[1] / 'templates/dirty-exec.sh'
SOURCE = TEMPLATE.read_text()
FUNCTION = SOURCE[SOURCE.index('append_readonly_git_metadata() {'):SOURCE.index('# End read-only Git metadata selection.')]


class GitMetadataTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(); self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name).resolve()
        self.repo = self.root/'repo'; self.repo.mkdir()
        self.git('init', '-q', cwd=self.repo)
        (self.repo/'file').write_text('fixture')
        self.git('add', 'file', cwd=self.repo)
        self.git('-c','user.name=Fixture','-c','user.email=fixture@example.invalid', 'commit','-qm','fixture',cwd=self.repo)
        self.git('tag','baseline',cwd=self.repo)
        self.work = self.root/'task'
        self.git('worktree','add','-qb','task',str(self.work),cwd=self.repo)
        self.common=self.repo/'.git'; self.slot=self.common/'worktrees/task'

    def git(self, *args, cwd):
        return subprocess.run(['git',*args],cwd=cwd,text=True,capture_output=True,check=True).stdout.strip()

    def select(self, authorized=True, listed=True):
        return subprocess.run(['bash','-eu','-c', '''
die() { echo "$*" >&2; exit 1; }
project_root="$1"
SCRUBS_GIT_METADATA_ROOTS=()
SCRUBS_GIT_METADATA_WORKTREES=()
[[ "$3" == no ]] || SCRUBS_GIT_METADATA_WORKTREES=("$3")
[[ "$2" == no ]] || SCRUBS_GIT_METADATA_ROOTS=("$2")
git_metadata_binds=()
''' + FUNCTION + '''
append_readonly_git_metadata
printf '%s\\0' "${git_metadata_binds[@]}"
''','test',str(self.work),str(self.common) if authorized else 'no', str(self.work) if listed is True else str(listed) if listed else 'no'],capture_output=True)

    def test_unauthorized_indirection_exposes_nothing(self):
        result=self.select(False)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout,b'\0')

    def test_allowlisted_repository_does_not_authorize_unlisted_worktrees(self):
        for listed in (False, self.repo):
            result=self.select(listed=listed)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(result.stdout,b'\0')
        sibling=self.root/'sibling'
        self.git('worktree','add','-qb','sibling',str(sibling),cwd=self.repo)
        result=self.select(listed=sibling)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(result.stdout,b'\0')

    def test_exact_metadata_only_all_mounts_readonly(self):
        result=self.select(); self.assertEqual(result.returncode,0,result.stderr)
        args=result.stdout.decode().rstrip('\0').split('\0')
        self.assertNotIn('--bind',args)
        expected=[self.common/x for x in ('HEAD','objects','refs')]+[self.slot/x for x in ('HEAD','commondir','gitdir','index')]
        mounted=[Path(args[i+1]) for i,x in enumerate(args) if x=='--ro-bind']
        self.assertEqual(set(mounted),set(expected))
        for excluded in ('config','hooks','logs'):
            self.assertNotIn(str(self.common/excluded),args)

    def test_symlink_entry_and_bad_backlink_refused(self):
        head=self.slot/'HEAD'; data=head.read_bytes(); head.unlink()
        head.symlink_to(self.common/'HEAD')
        self.assertNotEqual(self.select().returncode,0)
        head.unlink(); head.write_bytes(data)
        (self.slot/'gitdir').write_text(str(self.root/'other/.git'))
        self.assertNotEqual(self.select().returncode,0)

    def test_sparse_metadata_supports_git_history_and_diff_without_config(self):
        # Model the mounted subset in a separate fixture directory; never alter
        # real repository data or invoke namespace/security changes in tests.
        common=self.root/'sparse'; common.mkdir()
        slot=common/'worktrees/task'; slot.mkdir(parents=True)
        for name in ('HEAD','objects','refs'):
            src=self.common/name; dst=common/name
            shutil.copytree(src,dst) if src.is_dir() else shutil.copyfile(src,dst)
        for name in ('HEAD','commondir','gitdir','index'):
            shutil.copyfile(self.slot/name,slot/name)
        work=self.root/'sparse-task'; work.mkdir()
        (work/'file').write_text('fixture')
        (work/'.git').write_text('gitdir: '+str(slot)+'\n')
        (slot/'gitdir').write_text(str(work/'.git')+'\n')
        self.assertEqual(self.git('show','baseline:file',cwd=work),'fixture')
        self.assertEqual(self.git('diff','--name-only','baseline',cwd=work),'')
        self.assertFalse((common/'config').exists())

    def test_metadata_mounts_follow_home_and_project_mounts(self):
        self.assertGreater(SOURCE.index('  "${git_metadata_binds[@]}"'),
                           SOURCE.index('  --bind "${project_root}"'))
        self.assertIn('SCRUBS_GIT_METADATA_ROOTS=()\nSCRUBS_GIT_METADATA_WORKTREES=()\nSCRUBS_TASK_LIBRARY_WORKTREES=()\nSCRUBS_TASK_LIBRARY_PATHS=()\nsource "${SANDBOX_DEFINITION}"',SOURCE)


if __name__=='__main__': unittest.main()
