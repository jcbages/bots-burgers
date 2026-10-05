#!/usr/bin/env python3
import fcntl
import hashlib
import json
import os
import shlex
import stat
from pathlib import Path
import subprocess
import sys
import tempfile


def git(*args, data=None):
    return subprocess.check_output(['git', *args], input=data, stderr=subprocess.DEVNULL)


def blob(data):
    return '-' if data is None else git('hash-object', '-w', '--stdin', data=data).decode().strip()


def head_mode(name):
    entry = git('ls-tree', 'HEAD', '--', name).decode().split()
    return entry[0] if entry else '100644'


def worktree_mode(path):
    return '100755' if path.stat().st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH) else '100644'


def read(path):
    if path.is_symlink():
        raise ValueError('symlink edits require explicit manual review')
    return path.read_bytes() if path.exists() else None


def target(name, cwd, root):
    cwd = Path(os.path.abspath(cwd))
    cwd_relative = cwd.resolve().relative_to(root)
    lexical_root = cwd
    for _ in cwd_relative.parts:
        lexical_root = lexical_root.parent
    path = Path(name)
    if path.is_absolute():
        try:
            relative = path.relative_to(lexical_root)
        except ValueError:
            relative = path.relative_to(root)
    else:
        relative = (cwd.resolve() / path).relative_to(root)
    path = root / relative
    relative = str(relative)
    if any(c in relative for c in '\t\n\r') or '..' in path.relative_to(root).parts or '.git' in path.relative_to(root).parts:
        raise ValueError('unsupported path')
    parent = root
    for part in path.relative_to(root).parts:
        parent /= part
        if parent.is_symlink():
            raise ValueError('symlink path')
    return relative


def patch_changes(patch, cwd, root):
    lines = patch.splitlines(keepends=True)
    if not lines or lines.pop(0).rstrip('\r\n') != '*** Begin Patch':
        raise ValueError('invalid patch')
    changes = []
    while lines and lines[0].rstrip('\r\n') != '*** End Patch':
        header = lines.pop(0).rstrip('\r\n')
        action, name = header.split(': ', 1)
        name = target(name, cwd, root)
        before = read(root / name)
        if action == '*** Add File':
            if before is not None:
                raise ValueError('add target exists')
            content = []
            while lines and lines[0].startswith('+'):
                content.append(lines.pop(0)[1:].rstrip('\r\n') + '\n')
            after = ''.join(content).encode()
        elif action == '*** Delete File':
            if before is None:
                raise ValueError('delete target missing')
            after = None
        elif action == '*** Update File':
            if before is None:
                raise ValueError('update target missing')
            content = before.decode().splitlines(keepends=True)
            cursor = 0
            while lines and (lines[0].startswith('@@') or lines[0][:1] in (' ', '+', '-')):
                if lines[0].startswith('@@'):
                    lines.pop(0)
                old, new = [], []
                while lines and lines[0][:1] in (' ', '+', '-') and not lines[0].startswith('***'):
                    line = lines.pop(0)
                    if line[0] in ' -':
                        old.append(line[1:])
                    if line[0] in ' +':
                        new.append(line[1:])
                eof = bool(lines and lines[0].rstrip('\r\n') == '*** End of File')
                if eof:
                    lines.pop(0)
                if not old:
                    raise ValueError('patch needs unique context')
                matches = [i for i in range(cursor, len(content) - len(old) + 1)
                           if content[i:i + len(old)] == old and (not eof or i + len(old) == len(content))]
                if len(matches) != 1:
                    raise ValueError('ambiguous patch context')
                start = matches[0]
                content[start:start + len(old)] = new
                cursor = start + len(new)
            after = ''.join(content).encode()
        else:
            raise ValueError('unsupported patch operation')
        changes.append((name, before, after))
    if not lines or lines.pop(0).rstrip('\r\n') != '*** End Patch' or lines:
        raise ValueError('invalid patch ending')
    if len({name for name, _, _ in changes}) != len(changes):
        raise ValueError('repeated patch target')
    return changes


def changes_for(payload, root):
    tool = payload.get('tool_name', '')
    args = payload.get('tool_input', {})
    cwd = Path(payload.get('cwd') or root)
    if tool == 'apply_patch':
        patch = args if isinstance(args, str) else args.get('patch', args.get('input', args.get('command', '')))
        return patch_changes(patch, cwd, root)
    if tool not in ('Edit', 'Write'):
        return []
    name = target(args['file_path'], cwd, root)
    before = read(root / name)
    if tool == 'Write':
        after = args['content'].encode()
    else:
        old, new = args['old_string'].encode(), args['new_string'].encode()
        if before is None or not old or not before.count(old):
            raise ValueError('edit target missing')
        if not args.get('replace_all') and before.count(old) != 1:
            raise ValueError('ambiguous edit')
        after = before.replace(old, new, -1 if args.get('replace_all') else 1)
    return [(name, before, after)]


def merge(current, base, other):
    with tempfile.TemporaryDirectory() as directory:
        files = [Path(directory) / name for name in ('current', 'base', 'other')]
        for path, sha in zip(files, (current, base, other)):
            path.write_bytes(b'' if sha == '-' else git('cat-file', '-p', sha))
        result = subprocess.run(['git', 'merge-file', '-p', *map(str, files)], capture_output=True)
        return blob(result.stdout) if result.returncode == 0 else None


def save(directory, state, sid):
    path = directory / 'state'
    temp = directory / 'state.tmp'
    temp.write_text(''.join('\t'.join((name, *entry)) + '\n' for name, entry in state.items()))
    temp.replace(path)
    hashes = sorted({sha for entry in state.values() for sha in entry[:2] if sha != '-'})
    tree = git('mktree', data=''.join(f'100644 blob {sha}\tb{i}\n' for i, sha in enumerate(hashes)).encode()).decode().strip()
    git('update-ref', f'refs/agent-ledger/{sid}', tree)


def capture(mode, payload, directory, root, sid):
    tool_id = payload.get('tool_use_id')
    if not tool_id:
        return
    pending = directory / ('pending.' + hashlib.sha256(tool_id.encode()).hexdigest())
    if mode in ('pre', 'codex-pre'):
        pending.unlink(missing_ok=True)
        changes = changes_for(payload, root)
        if changes:
            recorded = []
            for name, before, after in changes:
                origin_mode = head_mode(name) if before is not None else '100644'
                mode_conflict = before is not None and worktree_mode(root / name) != origin_mode
                recorded.append((name, blob(before), blob(after), origin_mode, mode_conflict))
            pending.write_text(json.dumps(recorded))
        return
    if mode != 'post' or not pending.exists():
        return
    changes = json.loads(pending.read_text())
    pending.unlink()
    path = directory / 'state'
    state = dict((line.split('\t')[0], line.split('\t')[1:]) for line in path.read_text().splitlines()) if path.exists() else {}
    for change in changes:
        name, before, expected = change[:3]
        origin_mode = change[3] if len(change) > 3 else head_mode(name) if before != '-' else '100644'
        mode_conflict = len(change) > 4 and change[4]
        entry = state.get(name, [before, before, 'contested' if mode_conflict else 'verified', origin_mode])
        origin, shadow, status = entry[:3]
        mode = entry[3] if len(entry) > 3 else '100644'
        if mode_conflict:
            status = 'contested'
        try:
            matches = blob(read(root / name)) == expected
        except (OSError, ValueError):
            matches = False
        if not matches:
            status = 'contested'
        elif before != expected:
            merged = expected if shadow == before else merge(shadow, before, expected)
            if merged is None:
                status = 'contested'
            else:
                shadow = merged
        state[name] = [origin, shadow, status, mode]
    save(directory, state, sid)


def main():
    mode = sys.argv[1]
    payload = {} if mode == 'run' else json.load(sys.stdin)
    sid = payload.get('session_id') or os.environ.get('LEDGER_SESSION') or os.environ.get('CLAUDE_CODE_SESSION_ID')
    if not sid or any(c in sid for c in '/\\\t\n\r ') or sid in ('.', '..'):
        if mode == 'run':
            raise ValueError('no valid session id')
        return
    if mode == 'codex-context':
        if payload.get('cwd'):
            os.chdir(payload['cwd'])
        try:
            root = Path(git('rev-parse', '--show-toplevel').decode().strip()).resolve()
            git_dir = Path(git('rev-parse', '--absolute-git-dir').decode().strip())
        except subprocess.CalledProcessError:
            return
        directory = git_dir / 'agent-ledger' / sid
        directory.mkdir(parents=True, exist_ok=True)
        with (directory / 'lock').open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            context = directory / 'codex-context-shown'
            if not context.exists():
                context.touch()
                print(json.dumps({'hookSpecificOutput': {
                    'hookEventName': 'UserPromptSubmit',
                    'additionalContext': 'For ledger commands in ' + str(root) + ', prefix gene scripts/mine and scripts/commit-mine with LEDGER_SESSION=' + shlex.quote(sid) + '.'}}))
        return
    if mode != 'run' and payload.get('tool_name') not in ('Edit', 'Write', 'apply_patch'):
        return
    if payload.get('cwd'):
        os.chdir(payload['cwd'])
    root = Path(git('rev-parse', '--show-toplevel').decode().strip()).resolve()
    directory = Path(git('rev-parse', '--absolute-git-dir').decode().strip()) / 'agent-ledger' / sid
    directory.mkdir(parents=True, exist_ok=True)
    read_only = mode == 'run' and Path(sys.argv[2]).name == 'mine'
    lock_path = directory / 'lock'
    if read_only and not lock_path.exists():
        subprocess.call(sys.argv[2:], env=dict(os.environ, LEDGER_LOCKED='1'))
        return
    with lock_path.open('r' if read_only else 'a') as lock:
        fcntl.flock(lock, fcntl.LOCK_SH if read_only else fcntl.LOCK_EX)
        if mode == 'run':
            environment = dict(os.environ, LEDGER_LOCKED='1')
            raise SystemExit(subprocess.call(sys.argv[2:], env=environment))
        os.chdir(root)
        capture(mode, payload, directory, root, sid)
if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        print(f'ledger: automatic attribution skipped: {error}', file=sys.stderr)
        sys.exit(1)
