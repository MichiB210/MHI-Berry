# Emu68 1.1.0-beta.1 BerryCore kernel (PiStorm classic)

Port of the Emu68 1.0.7 BerryCore patch to **Emu68 1.1.0-beta.1 (01.09.2026, git 0ba3a89)**,
PiStorm classic build. Needed for HDMI sound with mhiberry.library / MintVID on 1.1.

    Emu68-pistorm-classic-BerryCore2.gz  patched kernel (gzip, like the original release)
    berrycore_patch_110b1.S              complete, commented source of the change
    build_berrycore_110b1.py             rebuilds the kernel from the original .gz
    upstream/Emu68-pistorm-classic.gz    unmodified original (sha256 3b87c6cf...)

Build:  `python3 build_berrycore_110b1.py Emu68-pistorm-classic-BerryCore2.gz`

| Area | 1.0.7 | 1.1.0-beta.1 | What it does |
|---|---|---|---|
| version string (2x) | $5B / $1540C3 | $5B / $3CDC53 | "Emu68-BerryCore2 1.1.0-beta.1 (26.10.2026)" |
| CPU1 bootargs check | $654 | $69C | jump straight to boot-lock release |
| call on CPU1 | $8A00 (serial_writer entry) | $6DC (bl serial_writer) | now calls the BerryCore service |
| BerryCore service | $20F500 | $134C00 | 932 bytes, 1.0.7 code, mailbox scan mode 1 only |

The service sits in the free zero padding between the end of .text (exception vectors)
and .rodata. Only these bytes differ from the original; serial_writer() is unchanged.
Mailbox and module ABI are exactly those of BerryCore 1.0.7 (service version 20).

**Why "BerryCore2":** the 1.0.7 service first scanned the unmapped alias 0x10_0800_0000.
Emu68 1.0.7 answered those faults with a 0xBAD00BAD pattern, so the scan continued and
found the mailbox at 0x0800_0000 (mode 1). Emu68 1.1 treats reads with an address above
4 GB as unhandled ("Read from high memory") and CPU1 stops at boot - the 68k side then
times out (BerryMP314 stage 0x21, status 0xFFFFFFFF). BerryCore2 scans mode 1 only.

Emu68 (c) Michal Schulz, MPL-2.0. This patch is MPL-2.0 as well.
