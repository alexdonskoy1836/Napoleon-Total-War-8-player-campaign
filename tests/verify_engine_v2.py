"""Verify all guarded engine patches including campaign-only map-lookup bypass.

Read-only against game files. Requires pefile, capstone and unicorn.
Does not prove actual multiplayer success.
"""
from pathlib import Path
import sys, struct, json, hashlib
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'deps'))
import pefile, capstone
from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
from unicorn.x86_const import *
from verify_engine import verify, ORIGINAL_SHA256

ROOT = Path(__file__).resolve().parent
exe = Path(sys.argv[1]) if len(sys.argv)>1 else Path(r'C:\Program Files (x86)\Steam\steamapps\common\Napoleon Total War\Napoleon.exe')
descriptor_checks = verify(exe)
data = exe.read_bytes()
manifest = json.loads((ROOT.parent/'source'/'engine-patches.json').read_text())
assert hashlib.sha256(data).hexdigest() == manifest['original_sha256'] == ORIGINAL_SHA256
pe = pefile.PE(data=data)
new = bytearray(data)
modified = set()
md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
relocs = [entry.rva for block in pe.DIRECTORY_ENTRY_BASERELOC for entry in block.entries if entry.type == 3]
for patch in manifest['patches']:
    off = patch['file_offset']; before = bytes.fromhex(patch['before']); after = bytes.fromhex(patch['after'])
    assert len(before) == len(after)
    assert data[off:off+len(before)] == before
    assert not modified.intersection(range(off, off+len(before)))
    modified.update(range(off,off+len(before)))
    new[off:off+len(after)] = after
    if patch['va'] is not None:
        rva = patch['va'] - pe.OPTIONAL_HEADER.ImageBase
        assert pe.get_offset_from_rva(rva) == off
        assert not any(rel < rva+len(after) and rva < rel+4 for rel in relocs)
        assert sum(insn.size for insn in md.disasm(after, patch['va'])) == len(after)
assert hashlib.sha256(new).hexdigest() == manifest['patched_sha256']
patched_pe = pefile.PE(data=bytes(new))
assert patched_pe.OPTIONAL_HEADER.SizeOfImage == pe.OPTIONAL_HEADER.SizeOfImage
assert patched_pe.FILE_HEADER.NumberOfSections == pe.FILE_HEADER.NumberOfSections
assert patched_pe.sections[0].Misc_VirtualSize == 0xf05a00
assert patched_pe.sections[0].Characteristics & 0x20000000
assert len(new) == len(data)

def execute(path, mode, players, rebase, patched):
    cpu = Uc(UC_ARCH_X86, UC_MODE_32)
    source = bytes(new) if patched else data
    for page in (0x4a8000, 0x4a9000, 0x1306000):
        cpu.mem_map(page+rebase, 0x1000)
        off=pe.get_offset_from_rva(page-0x400000)
        cpu.mem_write(page+rebase, source[off:off+0x1000])
    session=0x20000000; descriptor=0x20060000; stack=0x30000000
    cpu.mem_map(session,0x61000); cpu.mem_map(stack,0x2000)
    cpu.mem_write(session+0x583b4, struct.pack('<I', mode))
    cpu.mem_write(descriptor+0x34, struct.pack('<I', players))
    regs={UC_X86_REG_EAX:0x55555555, UC_X86_REG_EBX:session,
          UC_X86_REG_ESI:descriptor, UC_X86_REG_EDI:players//2,
          UC_X86_REG_ECX:0x11111111, UC_X86_REG_EDX:0x22222222,
          UC_X86_REG_EBP:0x33333333, UC_X86_REG_ESP:stack+0x1000}
    if path=='host':
        start=0x4a8703; lookup=0x4a8711; skip=0x4a874b
    else:
        start=0x4a9e72; lookup=0x4a9e7b; skip=0x4a9f10
        regs[UC_X86_REG_EAX]=players; regs[UC_X86_REG_ESI]=session
    for reg,value in regs.items(): cpu.reg_write(reg,value)
    reached=[]
    def stop_at_exit(cpu,address,size,context):
        if address in (lookup+rebase,skip+rebase):
            reached.append(address-rebase); cpu.emu_stop()
    cpu.hook_add(UC_HOOK_CODE,stop_at_exit)
    cpu.emu_start(start+rebase,0,count=30)
    expected=skip if players<=2 or (patched and mode==3) else lookup
    assert reached==[expected],(path,mode,players,rebase,patched,reached,hex(expected))
    for reg,value in regs.items(): assert cpu.reg_read(reg)==value
    memory=bytes(cpu.mem_read(stack+0x1000,0x1000)); expected_memory=bytearray(0x1000)
    if path=='host':
        struct.pack_into('<II',expected_memory,0x14,players//2,players//2)
    assert memory==expected_memory
    return {'path':path,'mode':mode,'players':players,'rebase':rebase,
            'patched':patched,'exit':hex(expected)}

cases=[execute(path,mode,players,rebase,patched)
       for path in ('host','client') for mode in (0,1,2,3)
       for players in (2,4,8) for rebase in (0,0x2000000) for patched in (False,True)]
report={'passed': True,'descriptor_instruction_cases':8,'lobby_branch_cases':len(cases),
        'patched_sha256':manifest['patched_sha256'],'relocation_overlap':False,
        'same_file_size_image_size_and_section_count':True,
        'campaign_mode':3,'campaign_host_client_skip_battle_lookup':True,
        'other_modes_preserve_original_branch_results':True,
        'all_general_registers_and_expected_stack_writes_preserved':True,
        'runtime_validation':'Not performed; networking, gameplay and real save/reload are untested.'}
# Report is printed; the verifier does not modify the package or game.
print(json.dumps(report,indent=2))
