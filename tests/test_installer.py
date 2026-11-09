"""Exercise installation against disposable COPIES, never the source game.

Python standard library + Windows PowerShell 5.1. Supply a new --work-dir.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import stat
import struct
import subprocess

PACKAGE = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def extract(pack, wanted):
    with pack.open('rb') as f:
        magic, flags, deps, dep_bytes, count, index_bytes = struct.unpack('<4s5I', f.read(24))
        assert magic == b'PFH0'
        f.seek(24 + dep_bytes)
        index = f.read(index_bytes)
        offset = f.tell()
        p = 0
        for _ in range(count):
            size = struct.unpack_from('<I', index, p)[0]
            p += 4
            end = index.index(0, p)
            name = index[p:end].decode('cp1252')
            p = end + 1
            if name.lower() == wanted.lower():
                f.seek(offset)
                result = f.read(size)
                assert len(result) == size
                return result
            offset += size
    raise AssertionError(wanted)


def make_pack(entries):
    index = b''.join(struct.pack('<I', len(v)) + k.encode() + b'\0' for k, v in entries)
    return struct.pack('<4s5I', b'PFH0', 0, 0, 0, len(entries), len(index)) + index + b''.join(v for _, v in entries)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--game-root', type=Path, required=True)
    parser.add_argument('--work-dir', type=Path, required=True)
    args = parser.parse_args()
    original = args.game_root.resolve()
    work = args.work_dir.resolve()
    assert not work.exists(), 'Use a new work directory; existing files are never removed'
    assert original not in work.parents and work not in original.parents and work != original
    profile = json.loads((PACKAGE / 'supported-build.json').read_text())
    fixture = work / 'game'
    fixture.mkdir(parents=True)
    for item in profile['patchedFiles']:
        src = original / item['path']
        assert sha(src) == item['originalSha256'], f'Source is not original: {src}'
        dst = fixture / item['path']
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
    entries = [(e['entry'], extract(original / e['pack'], e['entry'])) for e in profile['packInputs']]
    (fixture / 'data' / 'data.pack').write_bytes(make_pack(entries))
    sentinel = fixture / 'ntwfix.ini'
    sentinel.write_bytes(b'unrelated user configuration\r\n')
    report = []
    mod_pack = fixture / profile['packPath']

    def invoke(*options, success=True, package=PACKAGE):
        result = subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File',
                                 str(package / 'install.ps1'), '-GamePath', str(fixture), *options],
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        with (work / 'commands.log').open('a', encoding='utf-8') as f:
            f.write('\nCOMMAND ' + repr(options) + '\n' + result.stdout)
        assert (result.returncode == 0) == success, result.stdout
        assert sentinel.read_bytes() == b'unrelated user configuration\r\n'
        return result

    def check_files(installed):
        for item in profile['patchedFiles']:
            assert sha(fixture / item['path']) == item['patchedSha256' if installed else 'originalSha256']
        assert sha(mod_pack) == (profile['packSha256'] if installed else None)

    def passed(name):
        report.append(name)
        print('PASS', name, flush=True)

    invoke(); check_files(True)
    for item in profile['patchedFiles']:
        assert sha(fixture / 'napoleon8_backup' / item['path']) == item['originalSha256']
    passed('install builds exact files, verifies originals, and preserves unrelated files')
    invoke('-VerifyOnly'); invoke(); check_files(True)
    passed('verify and repeated install are idempotent')
    invoke('-Uninstall'); check_files(False); invoke('-Uninstall'); check_files(False)
    passed('uninstall restores byte-identical originals; repeated uninstall is harmless')
    invoke(); check_files(True)
    passed('reinstall reuses verified retained backups')

    engine = fixture / 'Napoleon.exe'
    good = engine.read_bytes()
    bad = bytearray(good); bad[-1] ^= 1; engine.write_bytes(bad)
    before = [sha(fixture / f['path']) for f in profile['patchedFiles']] + [sha(mod_pack)]
    invoke('-Uninstall', success=False)
    assert before == [sha(fixture / f['path']) for f in profile['patchedFiles']] + [sha(mod_pack)]
    passed('uninstall refuses externally changed files without partial restoration')
    engine.write_bytes(good); invoke('-Uninstall'); check_files(False)

    good = engine.read_bytes(); bad = bytearray(good); bad[-1] ^= 1; engine.write_bytes(bad)
    invoke(success=False); assert engine.read_bytes() == bad and not mod_pack.exists()
    engine.write_bytes(good)
    passed('unsupported executable rejected before installation')
    mod_pack.write_bytes(b'preexisting unrelated pack')
    invoke(success=False); assert mod_pack.read_bytes() == b'preexisting unrelated pack'
    mod_pack.unlink(); check_files(False)
    passed('existing destination pack is never overwritten')

    damaged_package = work / 'damaged-package'
    shutil.copytree(PACKAGE, damaged_package)
    payload = damaged_package / profile['payloads'][0]['file']
    payload.write_bytes(payload.read_bytes() + b'x')
    invoke(success=False, package=damaged_package); check_files(False)
    passed('corrupt payload rejected before any game replacement')

    # Windows ReplaceFile should fail on a read-only second destination, after
    # replacing the first. This exercises rollback using real filesystem errors.
    startpos = fixture / profile['patchedFiles'][1]['path']
    startpos.chmod(stat.S_IREAD)
    try:
        result = invoke(success=False)
        check_files(False)
        assert 'original game files restored' in result.stdout, result.stdout
        assert not (fixture / 'napoleon8_backup' / 'installed.json').exists()
        assert not list((fixture / 'data').glob('*.pending'))
        passed('failed second replacement rolls back executable and leaves no active pack')
    finally:
        startpos.chmod(stat.S_IWRITE | stat.S_IREAD)
    invoke(); check_files(True); invoke('-Uninstall'); check_files(False)
    passed('installation works after rollback and uninstalls cleanly')

    # Explicitly recheck the actual source game was never changed.
    for item in profile['patchedFiles']:
        assert sha(original / item['path']) == item['originalSha256']
    (work / 'installer-validation.json').write_text(json.dumps({'passed': True, 'tests': report,
        'source_game_unchanged': True, 'fixture': str(fixture)}, indent=2))
    print('All installer checks passed. Actual source game unchanged.')


if __name__ == '__main__':
    main()
