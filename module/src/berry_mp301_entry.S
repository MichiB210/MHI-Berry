.section .text.berry_entry,"ax",%progbits
.align 4
.global berry_mp301_image
berry_mp301_image:
    .byte 0x42,0x4d,0x4d,0x42      /* BMMB */
    .byte 0x59,0x4d,0x4d,0x59      /* YMMY */
    .byte 1                         /* ABI */
    .byte 2                         /* CODEC */
    .byte 0,0
    .ascii "MP31"
    .space 48,0
.global berry_mp301_module_entry
berry_mp301_module_entry:
    /* Preserve BerryCore service context on its original CPU1 stack. */
    stp x27,x28,[sp,#-16]!
    stp x29,x30,[sp,#-16]!
    mov x27,sp

    /* Use the top of the shared 256-KiB work area as the decoder stack.
       The bridge allocator owns the low part of work; the stack grows down. */
    ldr w8,[x0,#48]                 /* work_phys */
    ldr w9,[x0,#52]                 /* work_len  */
    movz w10,#0x8040
    movk w10,#0x0002,lsl #16       /* require >= 0x28040 */
    cmp w9,w10
    b.lo 1f
    uxtw x8,w8
    add x8,x8,x1
    uxtw x9,w9
    add x9,x8,x9
    and x9,x9,#-16
    mov sp,x9
1:
    bl berry_mp301_c_entry

    /* AAPCS64 big-endian struct {u32 a,b,c,d} return -> BerryCore w0..w3. */
    mov x4,x0
    mov x5,x1
    lsr x6,x4,#32
    mov w0,w6
    mov w1,w4
    lsr x6,x5,#32
    mov w2,w6
    mov w3,w5

    mov sp,x27
    ldp x29,x30,[sp],#16
    ldp x27,x28,[sp],#16
    ret
