"""Compile Lua 5.1 with Lupa and convert its chunk to Napoleon's float32 ABI.

Development tool only. The installer uses the resulting checked-in bytecode.
"""
from pathlib import Path
import struct
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent / 'deps'))


def convert(data, size_t=4, number=4):
    if data[:6] != b'\x1bLua\x51\x00':
        raise ValueError('Expected standard Lua 5.1 chunk')
    endian, int_size, src_size_t, instruction, src_number, integral = data[6:12]
    if (endian, int_size, instruction, integral) != (1, 4, 4, 0):
        raise ValueError('Unsupported input ABI')
    p = 12
    out = bytearray(b'\x1bLua\x51\x00' + bytes([1,4,size_t,4,number,0]))

    def raw(n):
        nonlocal p
        if p + n > len(data):
            raise ValueError('Truncated chunk')
        v=data[p:p+n]; p+=n
        return v

    def integer():
        v=raw(4); out.extend(v)
        n=struct.unpack('<I',v)[0]
        if n > 10000000:
            raise ValueError('Unreasonable chunk count')
        return n

    def string():
        n=int.from_bytes(raw(src_size_t),'little')
        out.extend(n.to_bytes(size_t,'little'))
        out.extend(raw(n))

    def function():
        string()
        out.extend(raw(12))  # two line ints, nups/params/vararg/stack
        out.extend(raw(integer()*4))
        for _ in range(integer()):
            tag=raw(1); out.extend(tag)
            if tag == b'\x00':
                pass
            elif tag == b'\x01':
                out.extend(raw(1))
            elif tag == b'\x03':
                v=struct.unpack('<f' if src_number==4 else '<d',raw(src_number))[0]
                out.extend(struct.pack('<f' if number==4 else '<d',v))
            elif tag == b'\x04':
                string()
            else:
                raise ValueError('Unknown constant type')
        for _ in range(integer()): function()
        out.extend(raw(integer()*4))
        for _ in range(integer()):
            string(); out.extend(raw(8))
        for _ in range(integer()): string()

    function()
    if p != len(data): raise ValueError('Trailing chunk bytes')
    return bytes(out)


def compile_source(source, name='@napoleon8/main_panel.lua'):
    from lupa.lua51 import LuaRuntime
    lua=LuaRuntime(encoding=None)
    compiled=lua.eval(b'function(s,n) return string.dump(assert(loadstring(s,n))) end')(source, name.encode())
    result=convert(compiled)
    # Check parseability after conversion back to the host runtime ABI.
    back=convert(result,size_t=compiled[8],number=compiled[10])
    lua.eval(b'function(s) assert(loadstring(s)); return true end')(back)
    return result


if __name__=='__main__':
    source,target=map(Path,sys.argv[1:3])
    result=compile_source(source.read_bytes(), '@'+source.name)
    target.write_bytes(result)
    print(f'Compiled {source.name}: {len(result)} bytes; ABI {result[:12].hex()}')
