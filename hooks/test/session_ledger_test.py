import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
HOOK = ROOT / 'hooks/session_ledger.sh'


class LedgerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.git('init', '-q', '-b', 'main')
        self.git('config', 'user.email', 't@t')
        self.git('config', 'user.name', 't')
        self.file = self.root / 'shared'
        self.file.write_text(''.join(f'line{i}\n' for i in range(40)))
        self.git('add', '.')
        self.git('commit', '-qm', 'base')

    def run_command(self, *args, env=None):
        return subprocess.check_output(args, cwd=self.root, env=env, text=True, stderr=subprocess.STDOUT)

    def git(self, *args):
        return self.run_command('git', *args)

    def payload(self, sid='A', tool='Edit', **args):
        return dict(session_id=sid, cwd=str(self.root), tool_use_id=sid + '-call', tool_name=tool, tool_input=args)

    def hook(self, mode, payload):
        return subprocess.check_output([str(HOOK), mode], input=json.dumps(payload), cwd=self.root, text=True)

    def edit(self, old, new, sid='A', path='shared'):
        payload = self.payload(sid, file_path=path, old_string=old, new_string=new)
        self.hook('pre', payload)
        file = self.root / path
        file.write_text(file.read_text().replace(old, new, 1))
        self.hook('post', payload)

    def command(self, command, sid='A', *args):
        return self.run_command(str(ROOT / 'bin' / command), *args, env=dict(os.environ, LEDGER_SESSION=sid))

    def test_read_never_owns_concurrent_writer(self):
        payload = self.payload('reader', 'Bash', command='cat shared')
        self.hook('pre', payload)
        self.file.write_text('someone else\n')
        self.hook('post', payload)
        self.assertIn('no verified explicit edits', self.command('mine', 'reader', '--files'))

    def test_two_sessions_commit_only_their_edits(self):
        self.edit('line10\n', 'line10 A\n')
        self.edit('line13\n', 'line13 B\n', 'B')
        self.assertNotIn('+line13 B', self.command('mine', 'A'))
        self.command('commit-mine', 'A', '-m', 'A')
        self.assertIn('+line10 A', self.git('show', '--format=', '-U0'))
        self.assertNotIn('line13 B', self.git('show', '--format=', '-U0'))
        self.command('commit-mine', 'B', '-m', 'B')
        self.assertIn('+line13 B', self.git('show', '--format=', '-U0'))
        self.assertIn('line10\n', self.git('show', ':shared'))
        self.assertIn('line13\n', self.git('show', ':shared'))

    def test_same_target_concurrent_write_is_contested(self):
        payload = self.payload(file_path='shared', old_string='line10\n', new_string='line10 A\n')
        self.hook('pre', payload)
        self.file.write_text(self.file.read_text().replace('line10\n', 'line10 A\n').replace('line13\n', 'line13 OTHER\n'))
        self.hook('post', payload)
        before = self.git('rev-parse', 'HEAD')
        self.assertIn('tangled', self.command('commit-mine', 'A', '-m', 'A'))
        self.assertEqual(before, self.git('rev-parse', 'HEAD'))

    def test_unrelated_concurrent_write_is_not_recorded(self):
        payload = self.payload(file_path='shared', old_string='line10\n', new_string='line10 A\n')
        self.hook('pre', payload)
        (self.root / 'other').write_text('OTHER')
        self.file.write_text(self.file.read_text().replace('line10\n', 'line10 A\n'))
        self.hook('post', payload)
        self.assertEqual('shared\n', self.command('mine', 'A', '--files'))

    def test_write_creation_and_staged_index_preserved(self):
        payload = self.payload(tool='Write', file_path='with space', content='new\n')
        self.hook('pre', payload)
        (self.root / 'with space').write_text('new\n')
        self.hook('post', payload)
        self.file.write_text('OTHER STAGED\n')
        self.git('add', 'shared')
        index = self.git('show', ':shared')
        self.command('commit-mine', 'A', '-m', 'A')
        self.assertEqual('new\n', self.git('show', 'HEAD:with space'))
        self.assertEqual(index, self.git('show', ':shared'))
        self.assertNotIn('OTHER STAGED', self.git('show', 'HEAD:shared'))

    def test_overlap_with_uncommitted_change_cannot_land(self):
        self.edit('line5\n', 'line5 FIRST\n')
        self.edit('line5 FIRST\n', 'line5 SECOND\n', 'B')
        before = self.git('rev-parse', 'HEAD')
        self.assertIn('conflicts', self.command('commit-mine', 'B', '-m', 'B'))
        self.assertEqual(before, self.git('rev-parse', 'HEAD'))

    def test_undo_own_edit_no_commit(self):
        before = self.git('rev-parse', 'HEAD')
        self.edit('line5\n', 'line5 A\n')
        self.edit('line5 A\n', 'line5\n')
        self.assertIn('nothing to commit', self.command('commit-mine', 'A', '-m', 'A'))
        self.assertEqual(before, self.git('rev-parse', 'HEAD'))

    def test_codex_patch_update_add_delete(self):
        patch = '*** Begin Patch\n*** Update File: shared\n@@\n line9\n-line10\n+line10 CODEX\n line11\n*** Add File: new\n+new content\n*** End Patch\n'
        payload = self.payload(tool='apply_patch', input=patch)
        self.hook('codex-pre', payload)
        self.file.write_text(self.file.read_text().replace('line10\n', 'line10 CODEX\n'))
        (self.root / 'new').write_text('new content\n')
        self.hook('post', payload)
        self.command('commit-mine', 'A', '-m', 'patch')
        self.assertEqual('new content\n', self.git('show', 'HEAD:new'))
        payload = self.payload(tool='apply_patch', patch='*** Begin Patch\n*** Delete File: new\n*** End Patch\n')
        self.hook('pre', payload)
        (self.root / 'new').unlink()
        self.hook('post', payload)
        self.command('commit-mine', 'A', '-m', 'delete')
        self.assertNotIn('new', self.git('ls-tree', '--name-only', 'HEAD'))

    def test_codex_absolute_patch_through_symlinked_workspace(self):
        alias = Path(self.temp.name) / 'workspace'
        alias.symlink_to(self.root, target_is_directory=True)
        patch = f'*** Begin Patch\n*** Add File: {alias}/new\n+new\n*** End Patch'
        payload = self.payload(tool='apply_patch', command=patch)
        payload['cwd'] = str(alias)
        self.hook('codex-pre', payload)
        (self.root / 'new').write_text('new\n')
        self.hook('post', payload)
        self.assertEqual('new\n', self.command('mine', 'A', '--files'))

    def test_codex_patch_cannot_escape_repository(self):
        outside = Path(self.temp.name).parent / (Path(self.temp.name).name + '-outside')
        outside.write_text('original\n')
        self.addCleanup(lambda: outside.unlink(missing_ok=True))
        patch = f'*** Begin Patch\n*** Update File: ../{outside.name}\n@@\n-original\n+changed\n*** End Patch'
        payload = self.payload(tool='apply_patch', command=patch)
        self.hook('codex-pre', payload)
        self.hook('post', payload)
        self.assertEqual('original\n', outside.read_text())
        self.assertIn('no verified explicit edits recorded', self.command('mine', 'A', '--files'))

    def test_recreated_file_not_deleted(self):
        payload = self.payload(tool='apply_patch', patch='*** Begin Patch\n*** Delete File: shared\n*** End Patch\n')
        self.hook('pre', payload)
        self.file.unlink()
        self.hook('post', payload)
        self.file.write_text('recreated')
        self.assertIn('present in the tree', self.command('commit-mine', 'A', '-m', 'delete'))

    def test_deletion_does_not_erase_concurrent_mode_change(self):
        payload = self.payload(tool='apply_patch', patch='*** Begin Patch\n*** Delete File: shared\n*** End Patch\n')
        self.hook('pre', payload)
        blob = self.git('rev-parse', 'HEAD:shared').strip()
        self.git('update-index', '--cacheinfo', f'100755,{blob},shared')
        self.git('commit', '-m', 'make executable')
        self.file.unlink()
        self.hook('post', payload)
        before = self.git('rev-parse', 'HEAD')
        output = self.command('commit-mine', 'A', '-m', 'delete')
        self.assertIn('changed in HEAD since deletion was recorded', output)
        self.assertEqual(before, self.git('rev-parse', 'HEAD'))
        self.assertTrue(self.git('ls-tree', 'HEAD', 'shared').startswith('100755'))

    def test_deletion_is_unverified_when_worktree_mode_differs_from_head(self):
        self.file.chmod(0o755)
        payload = self.payload(tool='apply_patch', patch='*** Begin Patch\n*** Delete File: shared\n*** End Patch\n')
        self.hook('pre', payload)
        self.file.unlink()
        self.hook('post', payload)
        before = self.git('rev-parse', 'HEAD')
        output = self.command('commit-mine', 'A', '-m', 'delete')
        self.assertIn('unverified or tangled', output)
        self.assertEqual(before, self.git('rev-parse', 'HEAD'))

    def test_codex_prompt_context_is_once_without_permission_override(self):
        payload = dict(session_id='Codex', cwd=str(self.root))
        output = json.loads(subprocess.check_output([str(HOOK), 'codex-context'], input=json.dumps(payload), cwd=self.root, text=True))
        context = output['hookSpecificOutput']['additionalContext']
        self.assertIn("LEDGER_SESSION=Codex", context)
        self.assertEqual('UserPromptSubmit', output['hookSpecificOutput']['hookEventName'])
        self.assertNotIn('permissionDecision', output['hookSpecificOutput'])
        self.assertNotIn('updatedInput', output['hookSpecificOutput'])
        self.assertEqual('', subprocess.check_output([str(HOOK), 'codex-context'], input=json.dumps(payload), cwd=self.root, text=True))

    def test_codex_prompt_context_is_silent_outside_git(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        payload = dict(session_id='Codex', cwd=directory.name)
        self.assertEqual('', subprocess.check_output([str(HOOK), 'codex-context'], input=json.dumps(payload), cwd=directory.name, text=True))

    def test_codex_patch_capture_does_not_emit_context_or_change_permissions(self):
        payload = self.payload('Codex', 'apply_patch', command='*** Begin Patch\n*** Add File: new\n+new\n*** End Patch\n')
        self.assertEqual('', self.hook('codex-pre', payload))
        (self.root / 'new').write_text('new\n')
        self.hook('post', payload)
        self.assertEqual('new\n', self.command('mine', 'Codex', '--files'))
        second = self.payload('Codex', 'apply_patch', command='*** Begin Patch\n*** Add File: next\n+next\n*** End Patch\n')
        self.assertEqual('', self.hook('codex-pre', second))

    def test_codex_bash_is_not_rewritten(self):
        payload = self.payload('Codex', 'Bash', command='cat shared')
        self.assertEqual('', self.hook('codex-pre', payload))

    def test_nested_cwd(self):
        nested = self.root / 'nested'
        nested.mkdir()
        payload = self.payload(tool='Write', file_path='new', content='nested\n')
        payload['cwd'] = str(nested)
        self.hook('pre', payload)
        (nested / 'new').write_text('nested\n')
        self.hook('post', payload)
        self.assertEqual('nested/new\n', self.command('mine', 'A', '--files'))

    def test_symlink_commit_mode_preserved(self):
        (self.root / 'new-link').symlink_to('missing-target')
        sha = subprocess.check_output(['git', 'hash-object', '-w', '--stdin'], input=b'missing-target', cwd=self.root).decode().strip()
        directory = self.root / '.git/agent-ledger/A'
        directory.mkdir(parents=True)
        (directory / 'state').write_text(f'new-link\t-\t{sha}\tverified\t120000\n')
        self.command('commit-mine', 'A', '-m', 'link')
        self.assertTrue(self.git('ls-tree', 'HEAD', 'new-link').startswith('120000'))
        self.assertEqual('missing-target', self.git('show', 'HEAD:new-link'))

    def test_new_file_mode_does_not_follow_later_symlink(self):
        payload = self.payload(tool='Write', file_path='new', content='regular contents')
        self.hook('pre', payload)
        path = self.root / 'new'
        path.write_text('regular contents')
        self.hook('post', payload)
        path.unlink()
        path.symlink_to('another-target')
        self.command('commit-mine', 'A', '-m', 'regular')
        self.assertTrue(self.git('ls-tree', 'HEAD', 'new').startswith('100644'))
        self.assertEqual('regular contents', self.git('show', 'HEAD:new'))

    def test_legacy_snapshot_record_is_not_committed(self):
        sha = self.git('rev-parse', 'HEAD:shared').strip()
        directory = self.root / '.git/agent-ledger/A'
        directory.mkdir(parents=True)
        (directory / 'state').write_text(f'shared\t-\t{sha}\tok\n')
        before = self.git('rev-parse', 'HEAD')
        self.assertIn('unverified', self.command('commit-mine', 'A', '-m', 'legacy'))
        self.assertEqual(before, self.git('rev-parse', 'HEAD'))

    def test_ambiguous_patch_is_not_attributed(self):
        self.file.write_text('same\nsame\n')
        payload = self.payload(tool='apply_patch', command='*** Begin Patch\n*** Update File: shared\n@@\n-same\n+changed\n*** End Patch\n')
        self.hook('pre', payload)
        self.file.write_text('changed\nsame\n')
        self.hook('post', payload)
        self.assertIn('no verified explicit edits', self.command('mine', 'A', '--files'))

    def test_codex_command_payload_and_failed_post(self):
        payload = self.payload(tool='apply_patch', command='*** Begin Patch\n*** Update File: shared\n@@\n-line10\n+line10 A\n*** End Patch\n')
        self.hook('codex-pre', payload)
        self.hook('post', payload)
        self.assertIn('tangled', self.command('commit-mine', 'A', '-m', 'failed'))

    def test_parallel_post_updates_preserve_both_entries(self):
        payloads = []
        for name in ('one', 'two'):
            payload = self.payload(tool='Write', file_path=name, content=name)
            payload['tool_use_id'] = name
            self.hook('pre', payload)
            (self.root / name).write_text(name)
            payloads.append(payload)
        processes = [subprocess.Popen([str(HOOK), 'post'], stdin=subprocess.PIPE, cwd=self.root, text=True) for _ in payloads]
        for process, payload in zip(processes, payloads):
            process.stdin.write(json.dumps(payload))
            process.stdin.close()
        for process in processes:
            self.assertEqual(0, process.wait())
        self.assertEqual({'one', 'two'}, set(self.command('mine', 'A', '--files').splitlines()))


if __name__ == '__main__':
    unittest.main(verbosity=2)
