/*
 * BerryCore patch for Emu68 1.1.0-beta.1 (PiStorm classic build, git 0ba3a89)
 * ---------------------------------------------------------------------------
 * Port of the BerryCore 1.0.7 patch (Emu68-pistorm-BerryCore, 13.09.2026).
 * "BerryCore2": the CPU1 service is the 1.0.7 code with one change - the
 * mailbox scan uses address mode 1 only (see scan_start for the reason).
 * The mailbox and module ABI are unchanged (see berrycore_patch.S of 1.0.7):
 *   mailbox magic "B99B"/"Y99Y", service version 20,
 *   commands 0 PING, 1 ADD, 2 CHECKSUM, 3 LOAD_MODULE, 4 CALL_MODULE,
 *            5 UNLOAD_MODULE,
 *   module header "BMMB"/"YMMY", ABI 1, entry at module base + 0x40.
 *
 * Only the patch locations changed. Compared with 1.0.7:
 *
 *   what                                  1.0.7      1.1.0-beta.1
 *   CPU1 bootargs check (start of)        0x654      0x69C
 *   CPU1: release boot_lock, call         0x688      0x6D0
 *   bl serial_writer()                    0x694      0x6DC
 *   serial_writer()                       0x8A00     0xF740  (unchanged here)
 *   BerryCore service                     0x20F500   0x134C00
 *
 * Differences in method:
 *   - 1.0.7 replaced the first instruction of serial_writer() with a branch.
 *     Here the single "bl serial_writer" in secondary_boot() is redirected to
 *     the service instead; serial_writer() itself stays untouched.
 *   - The service is placed in the zero padding at the end of .text, after
 *     the exception vectors (last instruction "eret" at 0x134814) and before
 *     .rodata (0x135000). 0x134818..0x134FFF is free (2024 bytes); the
 *     service needs 932 bytes. This is code memory, mapped like all of .text.
 *
 * secondary_boot() in 1.1.0-beta.1 (src/aarch64/start.c), CPU1 path:
 *   0x644  cmp x19,#1 / b.eq 0x69c
 *   0x69C  dt_find_node("/chosen") ... strstr(bootargs,"async_log")
 *   0x6D0  adrp x0, boot_lock / stlrb wzr,[x0]    (release boot lock)
 *   0x6DC  bl serial_writer                         (only caller)
 *   0x6E0  wfe loop
 *
 * Emu68 (c) Michal Schulz, MPL-2.0. This patch is MPL-2.0 as well.
 * build_berrycore_110b1.py assembles this file and writes each .p_<hex>
 * section to that file offset of the uncompressed Emu68.img.
 */

/* Version strings at 0x50 / 0x3CDC48: "$VER: Emu68" stays, the rest     */
/* (from 0x5B / 0x3CDC53, 38 bytes) is replaced.                          */
/* Original: " 1.1.0-beta.1 (01.09.2026) git:0ba3a89"                    */
        .section .p_0005b,"a"
        .ascii  "-BerryCore2 1.1.0-beta.1 (26.10.2026)"
        .byte   0

        .section .p_3cdc53,"a"
        .ascii  "-BerryCore2 1.1.0-beta.1 (26.10.2026)"
        .byte   0

/* CPU1: skip the bootargs check, continue at boot-lock release (0x6D0). */
        .section .p_0069c,"ax"
        b       . + (0x6d0 - 0x69c)

/* CPU1: call the BerryCore service instead of serial_writer(). */
        .section .p_006dc,"ax"
        bl      . + (0x134c00 - 0x6dc)

/* ------------------------------------------------------------------ */
/* BerryCore service (file offset 0x134C00). Same as 1.0.7 except the  */
/* mailbox scan, which uses address mode 1 only (see scan_start).      */
/* ------------------------------------------------------------------ */
        .section .p_134c00,"ax"
berrycore_service:
        mov     x22, xzr                // no module loaded
        mov     w23, wzr
        mov     w24, wzr

/* Search the mailbox: 0x8000 pages of 4 KiB (128 MiB) at 0x0800_0000,
   address mode 1 only. If nothing is found, start again.

   CHANGE FOR 1.1 (BerryCore2): the 1.0.7 service first scanned the alias
   0x10_0800_0000 (mode 2). That area is not mapped. In 1.0.7 every read
   there faulted and SYSReadValFromAddr() answered it with a 0xBAD00BAD
   pattern, so the scan went on and always found the mailbox in mode 1.
   Emu68 1.1 rejects faults with (far >> 32) != 0 ("Read from high
   memory"), the fault is unhandled and CPU1 stops in a wfe loop at boot.
   So mode 2 is skipped: "movk x0,#0x10,lsl #32" -> nop, w7 = 1.
   The mode-1 code path is exactly the one that ran on 1.0.7 hardware. */
scan_start:
        mov     x0, #0x8000000
        nop                             // 1.0.7: movk x0, #0x10, lsl #32
        mov     w1, #0x8000
        mov     w7, #1                  // 1.0.7: mov w7, #2
scan_page:
        mov     w2, #0x3942             // "B99B"
        movk    w2, #0x4239, lsl #16
        mov     w3, #0x3959             // "Y99Y"
        movk    w3, #0x5939, lsl #16
        ldr     w4, [x0]
        cmp     w4, w2
        b.ne    scan_next
        ldr     w4, [x0, #4]
        cmp     w4, w3
        b.eq    mailbox_found
scan_next:
        add     x0, x0, #1, lsl #12
        subs    w1, w1, #1
        b.ne    scan_page
        cmp     w7, #2
        b.ne    berrycore_service       // w7 is always 1 now: start over
        mov     x0, #0x8000000          // (unreachable since BerryCore2)
        mov     w1, #0x8000
        mov     w7, #1
        b       scan_page

mailbox_found:
        mov     x20, x0
        mov     w21, w7

/* Main loop: wait for a request ($A5 at +8). */
wait_request:
        dc      ivac, x20               // read fresh mailbox from RAM
        dsb     sy
        mov     w2, #0x3942             // "B99B"
        movk    w2, #0x4239, lsl #16
        mov     w3, #0x3959             // "Y99Y"
        movk    w3, #0x5939, lsl #16
        ldr     w4, [x20]
        cmp     w4, w2
        b.ne    berrycore_service       // mailbox gone: search again
        ldr     w4, [x20, #4]
        cmp     w4, w3
        b.ne    berrycore_service
        ldrb    w4, [x20, #8]
        cmp     w4, #0xa5
        b.ne    wait_request

        add     x17, x20, #0x40         // second cache line of the mailbox
        dc      ivac, x17
        dsb     sy
        ldr     w27, [x20, #0xc]        // sequence number
        ldr     w4, [x20, #0x10]        // command
        mov     w12, wzr
        mov     w13, wzr
        mov     w14, wzr
        mov     w15, wzr
        cmp     w4, #0
        b.eq    cmd_ping
        cmp     w4, #1
        b.eq    cmd_add
        cmp     w4, #2
        b.eq    cmd_checksum
        cmp     w4, #3
        b.eq    cmd_load_module
        cmp     w4, #4
        b.eq    cmd_call_module
        cmp     w4, #5
        b.eq    cmd_unload_module
        mov     w15, #1                 // error 1: unknown command
        b       finish_request

/* 0: PING - only answer. */
cmd_ping:
        b       finish_request

/* 1: ADD test - result 0 = operand1 + operand2. */
cmd_add:
        ldr     w5, [x20, #0x28]
        ldr     w6, [x20, #0x2c]
        add     w12, w5, w6
        b       finish_request

/* 2: CHECKSUM - result 0 = sum of all 32-bit words in buffer A. */
cmd_checksum:
        ldr     w5, [x20, #0x18]
        ldr     w6, [x20, #0x1c]
        ubfx    x8, x5, #0, #32         // zero-extend Amiga address
        cmp     w21, #2
        b.ne    1f
        mov     x9, #0x1000000000
        add     x8, x8, x9
1:      mov     w12, wzr
        cbz     w6, finish_request
2:      ldr     w13, [x8], #4
        add     w12, w12, w13
        subs    w6, w6, #4
        b.ne    2b
        mov     w13, wzr
        b       finish_request

/* 3: LOAD_MODULE - buffer A holds the module image (in place).
   Size must be 0x44 .. 1 MiB. Result 0 = module type, result 1 = size. */
cmd_load_module:
        mov     x22, xzr                // old module is forgotten
        mov     w23, wzr
        mov     w24, wzr
        ldr     w5, [x20, #0x18]
        ldr     w6, [x20, #0x1c]
        cmp     w6, #0x44
        b.lo    load_bad_size
        mov     w8, #0x100000
        cmp     w6, w8
        b.hi    load_bad_size
        ubfx    x8, x5, #0, #32         // zero-extend Amiga address
        cmp     w21, #2
        b.ne    1f
        mov     x9, #0x1000000000
        add     x8, x8, x9
1:      mov     x10, x8                 // invalidate data cache of the image
        add     w11, w6, #0x3f
        lsr     w11, w11, #6
2:      dc      ivac, x10
        add     x10, x10, #0x40
        subs    w11, w11, #1
        b.ne    2b
        dsb     sy
        mov     w9, #0x4d42             // "BMMB"
        movk    w9, #0x424d, lsl #16
        ldr     w10, [x8]
        cmp     w10, w9
        b.ne    load_bad_magic
        mov     w9, #0x4d59             // "YMMY"
        movk    w9, #0x594d, lsl #16
        ldr     w10, [x8, #4]
        cmp     w10, w9
        b.ne    load_bad_magic
        ldrb    w10, [x8, #8]           // ABI version must be 1
        cmp     w10, #1
        b.ne    load_bad_version
        ldrb    w24, [x8, #9]           // module type, must not be 0
        cbz     w24, load_bad_version
        mov     x10, x8                 // make the code visible to the
        add     w11, w6, #0x3f          // instruction fetch
        lsr     w11, w11, #6
3:      ic      ivau, x10
        add     x10, x10, #0x40
        subs    w11, w11, #1
        b.ne    3b
        dsb     sy
        isb
        mov     x22, x8                 // module is loaded
        mov     w23, w6
        mov     w12, w24
        mov     w13, w23
        b       finish_request
load_bad_size:
        mov     w15, #4
        b       finish_request
load_bad_magic:
        mov     w15, #3
        b       finish_request
load_bad_version:
        mov     w15, #5
        b       finish_request

/* 4: CALL_MODULE - calls module base + 0x40.
   Before: invalidate buffers A, B, C (read what the 68k side wrote).
   After:  clean buffers B and C (write results back to RAM). */
cmd_call_module:
        cbz     x22, call_no_module
        ldr     w5, [x20, #0x18]
        ldr     w6, [x20, #0x1c]
        bl      cache_invalidate_range
        ldr     w5, [x20, #0x20]
        ldr     w6, [x20, #0x24]
        bl      cache_invalidate_range
        ldr     w5, [x20, #0x30]
        ldr     w6, [x20, #0x34]
        bl      cache_invalidate_range
        mov     x0, x20                 // x0 = mailbox
        mov     x2, x22                 // x2 = module base
        mov     x1, xzr                 // x1 = address addend
        cmp     w21, #2
        b.ne    1f
        mov     x1, #0x1000000000
1:      add     x9, x22, #0x40
        blr     x9
        mov     w12, w0                 // result 0
        mov     w13, w1                 // result 1
        mov     w15, w2                 // error code
        mov     w14, w3                 // result 3
        ldr     w5, [x20, #0x20]
        ldr     w6, [x20, #0x24]
        bl      cache_clean_range
        ldr     w5, [x20, #0x30]
        ldr     w6, [x20, #0x34]
        bl      cache_clean_range
        b       finish_request
call_no_module:
        mov     w15, #2
        b       finish_request

/* Invalidate the data cache for w5 = Amiga address, w6 = length. */
cache_invalidate_range:
        cbz     w6, 3f
        ubfx    x8, x5, #0, #32         // zero-extend Amiga address
        cmp     w21, #2
        b.ne    1f
        mov     x9, #0x1000000000
        add     x8, x8, x9
1:      add     x11, x8, x6
        lsr     x10, x8, #6             // round start down to 64 bytes
        lsl     x10, x10, #6
        add     x11, x11, #0x3f         // round end up to 64 bytes
        lsr     x11, x11, #6
        lsl     x11, x11, #6
2:      dc      ivac, x10
        add     x10, x10, #0x40
        cmp     x10, x11
        b.lo    2b
        dsb     sy
3:      ret

/* Clean (write back) the data cache for w5 = address, w6 = length. */
cache_clean_range:
        cbz     w6, 3f
        ubfx    x8, x5, #0, #32         // zero-extend Amiga address
        cmp     w21, #2
        b.ne    1f
        mov     x9, #0x1000000000
        add     x8, x8, x9
1:      add     x11, x8, x6
        lsr     x10, x8, #6
        lsl     x10, x10, #6
        add     x11, x11, #0x3f
        lsr     x11, x11, #6
        lsl     x11, x11, #6
2:      dc      cvac, x10
        add     x10, x10, #0x40
        cmp     x10, x11
        b.lo    2b
        dsb     sy
3:      ret

/* 5: UNLOAD_MODULE */
cmd_unload_module:
        mov     x22, xzr
        mov     w23, wzr
        mov     w24, wzr
        b       finish_request

/* Write the results, set "done" and wait for the next request. */
finish_request:
        str     w12, [x20, #0x38]
        str     w13, [x20, #0x3c]
        str     w14, [x20, #0x40]
        str     w15, [x20, #0x44]
        str     w21, [x20, #0x48]
        str     w27, [x20, #0x4c]
        mov     w4, #1
        strb    w4, [x20, #0xa]         // service present
        mov     w4, #20
        strb    w4, [x20, #0xb]         // service version 20
        strb    wzr, [x20, #8]          // clear request flag
        mov     w4, #0x5a
        strb    w4, [x20, #9]           // done
        dc      cvac, x20               // write both cache lines back
        add     x17, x20, #0x40
        dc      cvac, x17
        dsb     sy
        b       wait_request
