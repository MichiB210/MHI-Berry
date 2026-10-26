#!/usr/bin/env python3
"""build_berrycore_110b1.py [ORIGINAL_GZ] OUTPUT_GZ

Builds Emu68 1.1.0-beta.1 BerryCore (PiStorm classic) from readable source:
  1. unpacks the original Emu68-pistorm-classic.gz (Emu68.img),
  2. assembles berrycore_patch_110b1.S (clang, aarch64),
  3. writes every section .p_<hexoffset> to that offset of Emu68.img,
  4. checks that only zero bytes are overwritten in the service area,
  5. writes the result gzip-compressed (like the original release).
Needs: python3, clang, llvm-objdump, llvm-objcopy.
"""
import gzip, hashlib, os, re, subprocess, sys, tempfile

ORIGINAL_GZ_SHA256  = '3b87c6cf3f4e54a3c412688babb9f05854f895097466c9f4672fb954afc27030'
ORIGINAL_IMG_SHA256 = '9d3fe5bf7f2aad217b34ebb352a97d1541c8e2564bb49ccc171bf2ddf373fa29'
SERVICE_OFF, SERVICE_END = 0x134C00, 0x135000
HERE = os.path.dirname(os.path.abspath(__file__))

def run(*cmd, **kw):
    return subprocess.run(cmd, check=True, **kw)

def main(src, dst):
    raw = open(src, 'rb').read()
    if hashlib.sha256(raw).hexdigest() != ORIGINAL_GZ_SHA256:
        sys.exit('ERROR: input is not the original Emu68 1.1.0-beta.1 PiStorm classic .gz')
    data = bytearray(gzip.decompress(raw))
    assert hashlib.sha256(data).hexdigest() == ORIGINAL_IMG_SHA256
    with tempfile.TemporaryDirectory() as tmp:
        obj = os.path.join(tmp, 'patch.o')
        run('clang', '--target=aarch64-none-elf', '-c',
            os.path.join(HERE, 'berrycore_patch_110b1.S'), '-o', obj)
        heads = run('llvm-objdump', '-h', obj, capture_output=True, text=True).stdout
        for name, off in re.findall(r'^\s*\d+\s+(\.p_([0-9a-f]+))\s', heads, re.M):
            out = os.path.join(tmp, name + '.bin')
            run('llvm-objcopy', '-O', 'binary', '--only-section=' + name, obj, out)
            blob = open(out, 'rb').read()
            o = int(off, 16)
            if o == SERVICE_OFF:
                if o + len(blob) > SERVICE_END or any(data[o:o + len(blob)]):
                    sys.exit('ERROR: service does not fit into the free padding')
            print('  %-10s -> offset 0x%06X, %4d bytes' % (name, o, len(blob)))
            data[o:o + len(blob)] = blob
    print('Emu68.img SHA-256:', hashlib.sha256(data).hexdigest())
    with open(dst, 'wb') as f:
        with gzip.GzipFile(filename='Emu68.img', mode='wb', fileobj=f, mtime=0) as g:
            g.write(data)
    print('written:', dst)

if __name__ == '__main__':
    if len(sys.argv) == 2:
        main(os.path.join(HERE, 'upstream', 'Emu68-pistorm-classic.gz'), sys.argv[1])
    elif len(sys.argv) == 3:
        main(sys.argv[1], sys.argv[2])
    else:
        sys.exit(__doc__)
