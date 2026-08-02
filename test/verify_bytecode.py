#!/usr/bin/env python3
"""Validate all generated .class files — parse structure + verify branch targets."""
import struct, os, sys

TMP = '/tmp/dart_jvm_test'

def parse_cp(data):
    cp_count = struct.unpack('>H', data[8:10])[0]
    pos = 10
    cp = {}
    for i in range(1, cp_count):
        tag = data[pos]
        if tag == 1:  # UTF8
            l = struct.unpack('>H', data[pos+1:pos+3])[0]
            cp[i] = ('U', data[pos+3:pos+3+l].decode('utf-8', errors='replace'))
            pos += 3 + l
        elif tag == 3: cp[i] = ('I', struct.unpack('>i', data[pos+1:pos+5])[0]); pos += 5
        elif tag == 7: cp[i] = ('C', struct.unpack('>H', data[pos+1:pos+3])[0]); pos += 3
        elif tag == 8: cp[i] = ('S', struct.unpack('>H', data[pos+1:pos+3])[0]); pos += 3
        elif tag == 9: cp[i] = ('F', struct.unpack('>HH', data[pos+1:pos+5])); pos += 5
        elif tag == 10: cp[i] = ('M', struct.unpack('>HH', data[pos+1:pos+5])); pos += 5
        elif tag == 11: cp[i] = ('IM', struct.unpack('>HH', data[pos+1:pos+5])); pos += 5
        elif tag == 12: cp[i] = ('NT', struct.unpack('>HH', data[pos+1:pos+5])); pos += 5
        else:
            print(f'  FATAL: Unknown CP tag {tag} at #{i}')
            return None, 0
    return cp, pos

def resolve_utf8(cp, idx):
    entry = cp.get(idx)
    if entry and entry[0] == 'U': return entry[1]
    if entry and entry[0] == 'C': return resolve_utf8(cp, entry[1])
    if entry and entry[0] == 'S': return resolve_utf8(cp, entry[1])
    return f'#{idx}'

def validate_class(filepath):
    data = open(filepath, 'rb').read()

    # Magic
    if data[:4] != b'\xca\xfe\xba\xbe':
        return False, "Bad magic"

    minor = struct.unpack('>H', data[4:6])[0]
    major = struct.unpack('>H', data[6:8])[0]

    cp, pos = parse_cp(data)
    if cp is None:
        return False, "Bad constant pool"

    # Access flags + this_class + super_class
    af = struct.unpack('>H', data[pos:pos+2])[0]; pos += 2
    tc = struct.unpack('>H', data[pos:pos+2])[0]; pos += 2
    sc = struct.unpack('>H', data[pos:pos+2])[0]; pos += 2

    # Interfaces
    ic = struct.unpack('>H', data[pos:pos+2])[0]; pos += 2
    if ic > 0: pos += ic * 2

    # Fields
    fc = struct.unpack('>H', data[pos:pos+2])[0]; pos += 2
    for _ in range(fc):
        pos += 8  # access + name + desc + attrs_count
        fac = struct.unpack('>H', data[pos-2:pos])[0]
        for __ in range(fac):
            al = struct.unpack('>I', data[pos+2:pos+6])[0]; pos += 6 + al

    # Methods
    mc = struct.unpack('>H', data[pos:pos+2])[0]; pos += 2

    errors = []

    for mi in range(mc):
        maf = struct.unpack('>H', data[pos:pos+2])[0]; pos += 2
        mn = struct.unpack('>H', data[pos:pos+2])[0]; pos += 2
        md = struct.unpack('>H', data[pos:pos+2])[0]; pos += 2
        mac = struct.unpack('>H', data[pos:pos+2])[0]; pos += 2

        mn_str = resolve_utf8(cp, mn)

        for ai in range(mac):
            an = struct.unpack('>H', data[pos:pos+2])[0]; pos += 2
            al = struct.unpack('>I', data[pos:pos+4])[0]; pos += 4
            an_str = resolve_utf8(cp, an)

            if an_str == 'Code':
                ms = struct.unpack('>H', data[pos:pos+2])[0]
                ml = struct.unpack('>H', data[pos+2:pos+4])[0]
                cl = struct.unpack('>I', data[pos+4:pos+8])[0]

                cs = pos + 8
                ce = cs + cl

                # Disassemble and verify branches
                pc = cs
                while pc < ce:
                    op = data[pc]
                    off = pc - cs

                    if op in (0xa7, 0xc6, 0xc7, 0x99, 0x9a, 0xa1, 0xa2):
                        bo = struct.unpack('>h', data[pc+1:pc+3])[0]
                        target = pc + bo
                        names = {0xa7:'goto', 0xc6:'ifnull', 0xc7:'ifnonnull',
                                 0x99:'ifeq', 0x9a:'ifne', 0xa1:'if_icmplt', 0xa2:'if_icmpge'}
                        name = names.get(op, f'br_0x{op:02x}')

                        if target < cs or target >= ce:
                            errors.append(
                                f'{mn_str}: pc={off} {name} ->{target-cs} '
                                f'(out of [0,{cl}) — offset={bo})'
                            )
                        pc += 3
                    elif op == 0x10: pc += 2   # bipush
                    elif op == 0x11: pc += 3   # sipush
                    elif op == 0x12: pc += 2   # ldc
                    elif op == 0x13: pc += 3   # ldc_w
                    elif op == 0x19: pc += 2   # aload
                    elif op == 0x15: pc += 2   # iload
                    elif op == 0x36: pc += 2   # istore
                    elif op == 0x3a: pc += 2   # astore
                    elif op == 0x84: pc += 3   # iinc
                    elif op in (0xb6, 0xb7, 0xb8, 0xbb, 0xbd, 0xc0): pc += 3
                    elif op == 0xbc: pc += 2   # newarray
                    elif op == 0xb9: pc += 5   # invokeinterface
                    elif op >= 0x1a and op <= 0x1d: pc += 1  # iload_n
                    elif op >= 0x2a and op <= 0x2d: pc += 1  # aload_n
                    elif op >= 0x3b and op <= 0x3e: pc += 1  # istore_n
                    elif op >= 0x4b and op <= 0x4e: pc += 1  # astore_n
                    else: pc += 1  # single-byte opcodes

                # Verify pc matches code_end
                if pc != ce:
                    errors.append(
                        f'{mn_str}: disassembly mismatch: pc={pc-cs}, code_end={cl}'
                    )

                pos = ce

                # Exception table
                etl = struct.unpack('>H', data[pos:pos+2])[0]; pos += 2
                pos += etl * 8

                # Sub-attributes
                sac = struct.unpack('>H', data[pos:pos+2])[0]; pos += 2
                for _ in range(sac):
                    sal = struct.unpack('>I', data[pos+2:pos+6])[0]; pos += 6 + sal
            else:
                pos += al

    # Class attributes
    cac = struct.unpack('>H', data[pos:pos+2])[0]; pos += 2
    for _ in range(cac):
        cal = struct.unpack('>I', data[pos+2:pos+6])[0]; pos += 6 + cal

    if pos != len(data):
        errors.append(f'File size mismatch: parsed {pos}, actual {len(data)}')

    if errors:
        return False, '; '.join(errors)
    return True, f'OK v{major}.{minor}'

def main():
    if not os.path.isdir(TMP):
        print(f"Directory {TMP} not found. Run dart test first.")
        sys.exit(1)

    files = sorted([f for f in os.listdir(TMP) if f.endswith('.class')])
    if not files:
        print("No .class files found.")
        sys.exit(1)

    all_ok = True
    for f in files:
        path = os.path.join(TMP, f)
        ok, msg = validate_class(path)
        status = 'OK' if ok else 'FAIL'
        print(f'{status:5} {f:25s} {msg}')
        if not ok:
            all_ok = False

    print(f'\n{"ALL CLASSES VALID" if all_ok else "SOME CLASSES HAVE ERRORS"}')
    sys.exit(0 if all_ok else 1)

if __name__ == '__main__':
    main()
