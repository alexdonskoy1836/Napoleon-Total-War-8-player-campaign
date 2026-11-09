"""Read-only verification of the Napoleon campaign-capacity patch.

Requirements: pefile, capstone, unicorn (parent workspace has work/deps).
No game file is written. Results cover static structure and two instructions,
not a running game, networking, campaign simulation, or save compatibility.
"""
import argparse
import hashlib
import json
import struct
from pathlib import Path
import sys

deps = Path(__file__).resolve().parents[1] / 'deps'
if deps.exists():
    sys.path.insert(0, str(deps))
import capstone
import pefile
from unicorn import Uc, UC_ARCH_X86, UC_MODE_32
from unicorn.x86_const import UC_X86_REG_ESP

ORIGINAL_SHA256 = '44880ec1770f600163a336eec83b4366901484c5cceec83dc326e2932f02a054'
PATCHED_SHA256 = '52164b361050f73ea15ea338ddff35c2d06125cab176e72c1086d9d3897e10cd'
SITES = [
    (0x473811, 0xac, 0x72c18, 'New campaign capacity'),
    (0x4a8027, 0xd8, 0xa742e, 'Resume campaign capacity'),
]

def verify(executable):
    original = executable.read_bytes()
    assert hashlib.sha256(original).hexdigest() == ORIGINAL_SHA256, 'Unsupported original executable'
    pe = pefile.PE(data=original)
    assert pe.FILE_HEADER.Machine == 0x14c
    assert pe.OPTIONAL_HEADER.ImageBase == 0x400000
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    md.detail = True
    patched = bytearray(original)
    patches = []
    relocations = [entry.rva for block in pe.DIRECTORY_ENTRY_BASERELOC
                   for entry in block.entries if entry.type == 3]
    for va, displacement, expected_offset, label in SITES:
        offset = pe.get_offset_from_rva(va - 0x400000)
        assert offset + 7 == expected_offset
        before = original[offset:offset + 11]
        assert before == b'\xc7\x84\x24' + struct.pack('<II', displacement, 2)
        patched[offset + 7] = 8
        after = bytes(patched[offset:offset + 11])
        insn = list(md.disasm(after, va))
        assert len(insn) == 1 and insn[0].mnemonic == 'mov' and insn[0].size == 11
        rva = va - 0x400000 + 7
        assert not any(rel < rva + 4 and rva < rel + 4 for rel in relocations)
        cases = []
        for code, expected in [(before, 2), (after, 8)]:
            for rebase in [0, 0x1000000]:
                cpu = Uc(UC_ARCH_X86, UC_MODE_32)
                cpu.mem_map((va + rebase) & ~0xfff, 0x1000)
                cpu.mem_map(0x8000000, 0x2000)
                cpu.reg_write(UC_X86_REG_ESP, 0x8001000)
                cpu.mem_write(va + rebase, code)
                cpu.emu_start(va + rebase, va + rebase + len(code))
                stack = bytes(cpu.mem_read(0x8001000, 0x1000))
                expected_stack = bytearray(0x1000)
                struct.pack_into('<I', expected_stack, displacement, expected)
                assert stack == expected_stack, 'Unexpected memory write'
                assert cpu.reg_read(UC_X86_REG_ESP) == 0x8001000
                cases.append({'rebased_by': hex(rebase), 'value': expected})
        patches.append({'name': label, 'instruction_va': hex(va),
                        'immediate_va': hex(va + 7), 'file_offset': hex(offset + 7),
                        'expected_instruction': before.hex(), 'patched_instruction': after.hex(),
                        'emulator': cases})
    changes = [index for index, (a, b) in enumerate(zip(original, patched)) if a != b]
    assert changes == [0x72c18, 0xa742e]
    assert len(original) == len(patched)
    assert hashlib.sha256(patched).hexdigest() == PATCHED_SHA256
    return {'original_sha256': ORIGINAL_SHA256, 'patched_sha256': PATCHED_SHA256,
            'patches': patches, 'changed_offsets': [hex(x) for x in changes],
            'relocation_overlap': False,
            'status': 'Static and instruction emulation only; no multiplayer runtime validation'}

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('executable', nargs='?', type=Path,
                        default=Path(r'C:\Program Files (x86)\Steam\steamapps\common\Napoleon Total War\Napoleon.exe'))
    args = parser.parse_args()
    print(json.dumps(verify(args.executable), indent=2))
