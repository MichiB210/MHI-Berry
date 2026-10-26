#!/bin/sh
# mhiberry - kompletter Build aus den Quellen
#
#   sh build_all.sh
#
# Benoetigt:
#   vasmm68k_mot  (vasm, Motorola-Syntax; Pfad per VASM=... ueberschreibbar)
#   clang, ld.lld, llvm-objcopy, llvm-objdump  (LLVM 14 oder neuer)
#   python3, unzip, gzip
#
# Ergebnis in build/ und Vergleich mit den Release-Dateien in release/.

set -e
HERE=$(cd "$(dirname "$0")" && pwd)
cd "$HERE"
VASM=${VASM:-vasmm68k_mot}
CLANG=${CLANG:-clang}
OUT=$HERE/build
rm -rf "$OUT"
mkdir -p "$OUT/LIBS/MHI" "$OUT/C" "$OUT/kernel" "$OUT/tmp/obj"

check() {   # check NAME DATEI REFERENZ
    if cmp -s "$2" "$3"; then
        echo "  $1: BYTE-IDENTISCH mit release/"
    else
        echo "  $1: weicht von release/ ab"
    fi
}

echo "== 1. Amiga-Seite (vasm)"
( cd amiga
  "$VASM" -quiet -m68020 -Fhunkexe -nosym -o "$OUT/LIBS/MHI/mhiberry.library" mhiberry.library.s
  "$VASM" -quiet -m68020 -Fhunkexe -nosym -o "$OUT/C/mhiberry_engine"        mhiberry_engine.s )
check mhiberry.library "$OUT/LIBS/MHI/mhiberry.library" release/LIBS/MHI/mhiberry.library
check mhiberry_engine  "$OUT/C/mhiberry_engine"         release/C/mhiberry_engine

echo "== 2. CPU1-Decodermodul (clang, AArch64 big-endian)"
unzip -q -o module/third_party/libhelix-mp3-master.zip -d "$OUT/tmp"
H=$OUT/tmp/libhelix-mp3-master/src
CF="--target=aarch64_be-none-elf -mcpu=cortex-a53 -O2 -ffreestanding -fno-builtin -fno-pic -fno-stack-protector -I$H/pub -I$H/real -Imodule/src -Imodule/inc"
for f in $H/mp3dec.c $H/mp3tabs.c $H/real/*.c module/src/berry_mp301_bridge.c module/src/berry_mp301_runtime.c; do
    "$CLANG" $CF -w -c "$f" -o "$OUT/tmp/obj/$(basename "$f" .c).o"
done
"$CLANG" --target=aarch64_be-none-elf -c module/src/berry_mp301_entry.S -o "$OUT/tmp/obj/entry.o"
ld.lld -EB -nostdlib -static -T module/src/berry_mp301.ld -o "$OUT/tmp/berry_mp301.elf" "$OUT"/tmp/obj/*.o
llvm-objcopy -O binary "$OUT/tmp/berry_mp301.elf" "$OUT/tmp/berry_mp301.module"
# berry_mp3.module = Rohmodul + API-1.0/$VER-Metadaten in Header-Bytes 0x10..0x3F
python3 - "$OUT/tmp/berry_mp301.module" "$OUT/LIBS/MHI/berry_mp3.module" <<'PY'
import sys
b = bytearray(open(sys.argv[1], 'rb').read())
meta = bytes.fromhex('00010000') + b'MP3V' + b'$VER: berry_mp3.module 1.0 (24.09.2026)\0'
b[0x10:0x10 + len(meta)] = meta
open(sys.argv[2], 'wb').write(b)
PY
check berry_mp3.module "$OUT/LIBS/MHI/berry_mp3.module" release/LIBS/MHI/berry_mp3.module
echo "    (Original mit clang 17/Swift gebaut; andere clang-Versionen ergeben"
echo "     gleichwertigen, aber nicht byte-gleichen Code.)"

echo "== 3. Kernel Emu68 1.0.7 BerryCore"
python3 kernel/emu68_1.0.7/build_berrycore.py kernel/emu68_1.0.7/upstream/Emu68-pistorm "$OUT/kernel/Emu68-pistorm-BerryCore" | tail -1
check Emu68-pistorm-BerryCore "$OUT/kernel/Emu68-pistorm-BerryCore" release/kernel/Emu68-pistorm-BerryCore

echo "== 4. Kernel Emu68 1.1.0-beta.1 BerryCore2"
python3 kernel/emu68_1.1.0-beta.1/build_berrycore_110b1.py kernel/emu68_1.1.0-beta.1/upstream/Emu68-pistorm-classic.gz "$OUT/kernel/Emu68-pistorm-classic-BerryCore2.gz" | grep SHA
check Emu68-pistorm-classic-BerryCore2.gz "$OUT/kernel/Emu68-pistorm-classic-BerryCore2.gz" release/kernel/Emu68-pistorm-classic-BerryCore2.gz

rm -rf "$OUT/tmp"
echo "Fertig. Dateien in build/"
