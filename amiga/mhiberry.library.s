; mhiberry.library 1.16 - MHI04 RELEASE, persistent silent engine
; MHI queue ABI is hardware-proven by MHI02b. The actual MP3/CPU1/MMAL engine
; runs in C:mhiberry_engine as a normal AmigaDOS Process. MHI04 starts that
; process automatically from MHIAllocDecoder when no engine is READY.

RTC_MATCHWORD   equ $4afc
RTF_AUTOINIT    equ $80
NT_LIBRARY      equ 9
LIBF_CHANGED    equ 2
LIBF_SUMUSED    equ 4
LIBF_DELEXP     equ 8

MHIF_PLAYING     equ 0
MHIF_STOPPED     equ 1
MHIF_OUT_OF_DATA equ 2
MHIF_PAUSED      equ 3

MHIQ_CAPABILITIES       equ 0
MHIQ_MPEG1              equ 1
MHIQ_MPEG2              equ 2
MHIQ_MPEG25             equ 3
MHIQ_LAYER3             equ 12
MHIQ_VARIABLE_BITRATE   equ 20
MHIQ_JOINT_STEREO       equ 21
MHIQ_VOLUME_CONTROL      equ 40
MHIQ_DECODER_NAME       equ 1000
MHIQ_DECODER_VERSION    equ 1001
MHIQ_AUTHOR             equ 1002
MHIQ_IS_HARDWARE        equ 1010
MHIQ_IS_68K             equ 1011
MHIQ_IS_PPC             equ 1012
MHIP_VOLUME             equ 0
MHIP_PANNING            equ 1

_LVOForbid       equ -132
_LVOPermit       equ -138
_LVOSignal       equ -324
_LVOFindTask     equ -294
_LVOWait         equ -318
_LVORemove       equ -252
_LVOFreeMem      equ -210
_LVOOpenLibrary  equ -552
_LVOCloseLibrary equ -414

_DOSOpen          equ -30
_DOSClose         equ -36
_DOSSystemTagList equ -606
_DOSDelay         equ -198
_DOSWrite         equ -48
_DOSSeek          equ -66
TAG_DONE          equ 0
TAG_USER          equ $80000000
SYS_Dummy         equ (TAG_USER+32)
SYS_Input         equ (SYS_Dummy+1)
SYS_Output        equ (SYS_Dummy+2)
SYS_Asynch        equ (SYS_Dummy+3)

MODE_READWRITE    equ 1004
MODE_OLDFILE      equ 1005
MODE_NEWFILE      equ 1006
OFFSET_END         equ 1

LN_TYPE         equ 8
LN_NAME         equ 10
LIB_FLAGS       equ 14
LIB_NEGSIZE     equ 16
LIB_POSSIZE     equ 18
LIB_VERSION     equ 20
LIB_REVISION    equ 22
LIB_IDSTRING    equ 24
LIB_OPENCNT     equ 32

B_SEGLIST       equ 36
B_SYSBASE       equ 40
B_HANDLE        equ 64

H_MAGIC         equ 0
H_TASK          equ 4
H_SIGMASK       equ 8
H_STATUS        equ 12
H_PLAYFLAG      equ 13
H_STOPREQ       equ 14
H_QUIT          equ 15
H_QHEAD         equ 16
H_QTAIL         equ 18
H_QCOUNT        equ 20
H_EHEAD         equ 22
H_ETAIL         equ 24
H_ECOUNT        equ 26
H_ENQUEUED      equ 28
H_CONSUMED      equ 32
H_SIGNALED      equ 36
H_VOLUME        equ 44
H_PANNING       equ 45
H_QBUFS         equ 64
H_QSIZES        equ 128
H_EBUFS         equ 192
HANDLE_SIZE     equ 256
QUEUE_SLOTS     equ 16
QUEUE_MASK      equ 15
HANDLE_MAGIC    equ $424d4833       ; 'BMH3'

; Engine registration lives outside the decoder handle, so the Process may
; start before MHIAllocDecoder and wait for a client session.
B_ENGINE_TASK    equ (B_HANDLE+HANDLE_SIZE) ; 320
B_ENGINE_SIGMASK equ 324
B_ENGINE_READY   equ 328
B_ENGINE_BUSY    equ 329
B_ENGINE_ERROR   equ 330
BASE_SIZE        equ 336
ENGINE_READY_FROM_HANDLE equ (B_ENGINE_READY-B_HANDLE)
ENGINE_BUSY_FROM_HANDLE  equ (B_ENGINE_BUSY-B_HANDLE)

        section code,code
lib_start:
        moveq   #-1,d0
        rts
        even
romtag:
        dc.w    RTC_MATCHWORD
        dc.l    romtag
        dc.l    endresident
        dc.b    RTF_AUTOINIT
        dc.b    1
        dc.b    NT_LIBRARY
        dc.b    0
        dc.l    lib_name
        dc.l    id_string
        dc.l    init_table
endresident:
        even
init_table:
        dc.l    BASE_SIZE
        dc.l    func_table
        dc.l    0
        dc.l    lib_init
func_table:
        dc.l    lib_open,lib_close,lib_expunge,lib_extfunc
        dc.l    mhi_alloc_decoder,mhi_free_decoder,mhi_queue_buffer,mhi_get_empty
        dc.l    mhi_get_status,mhi_play,mhi_stop,mhi_pause,mhi_query,mhi_set_param
        dc.l    -1
        even

lib_init:
        move.l  d0,a1
        move.b  #NT_LIBRARY,LN_TYPE(a1)
        lea     lib_name(pc),a2
        move.l  a2,LN_NAME(a1)
        move.b  #(LIBF_CHANGED+LIBF_SUMUSED),LIB_FLAGS(a1)
        move.w  #1,LIB_VERSION(a1)
        move.w  #7,LIB_REVISION(a1)
        lea     id_string(pc),a2
        move.l  a2,LIB_IDSTRING(a1)
        move.l  a0,B_SEGLIST(a1)
        move.l  a6,B_SYSBASE(a1)
        lea     B_HANDLE(a1),a2
        clr.l   H_MAGIC(a2)
        clr.l   B_ENGINE_TASK(a1)
        clr.l   B_ENGINE_SIGMASK(a1)
        clr.b   B_ENGINE_READY(a1)
        clr.b   B_ENGINE_BUSY(a1)
        clr.b   B_ENGINE_ERROR(a1)
        move.l  a1,d0
        rts

lib_open:
        addq.w  #1,LIB_OPENCNT(a6)
        andi.b  #$f7,LIB_FLAGS(a6)
        move.l  a6,d0
        rts
lib_close:
        tst.w   LIB_OPENCNT(a6)
        beq.s   .done
        subq.w  #1,LIB_OPENCNT(a6)
        bne.s   .done
        tst.l   B_HANDLE+H_MAGIC(a6)
        bne.s   .delay
        tst.b   B_ENGINE_READY(a6)
        bne.s   .delay
        btst    #3,LIB_FLAGS(a6)
        bne.w   lib_expunge
.done:  moveq   #0,d0
        rts
.delay: ori.b   #LIBF_DELEXP,LIB_FLAGS(a6)
        moveq   #0,d0
        rts
lib_expunge:
        tst.w   LIB_OPENCNT(a6)
        bne.s   .later
        tst.l   B_HANDLE+H_MAGIC(a6)
        bne.s   .later
        tst.b   B_ENGINE_READY(a6)
        bne.s   .later
        movem.l d2-d4/a1-a2/a6,-(sp)
        move.l  B_SEGLIST(a6),d4
        move.l  a6,a2
        move.l  a2,a1
        move.l  B_SYSBASE(a2),a6
        jsr     _LVORemove(a6)
        moveq   #0,d2
        move.w  LIB_NEGSIZE(a2),d2
        moveq   #0,d3
        move.w  LIB_POSSIZE(a2),d3
        move.l  d2,d0
        add.l   d3,d0
        move.l  a2,a1
        suba.l  d2,a1
        jsr     _LVOFreeMem(a6)
        move.l  d4,d0
        movem.l (sp)+,d2-d4/a1-a2/a6
        rts
.later: ori.b   #LIBF_DELEXP,LIB_FLAGS(a6)
        moveq   #0,d0
        rts
lib_extfunc:
        moveq   #0,d0
        rts

; a0=client task, d0=signal mask
; MHI04: if the external engine is not already registered, start
; C:mhiberry_engine asynchronously through dos.library/SystemTagList and wait
; for its READY registration before handing the decoder to AmiAMP.
mhi_alloc_decoder:
        movem.l d2-d5/a2,-(sp)
        move.l  a0,d4                  ; preserve client task before diagnostics/autostart
        move.l  d0,d5                  ; preserve client signal mask
        lea     diag_alloc_entry(pc),a0
        bsr     diag_log
        lea     B_HANDLE(a6),a2
        ; MHI04R REOPEN RECOVERY:
        ; AmiAMP may close without reaching MHIFreeDecoder().  Because the
        ; external engine deliberately keeps this library resident, the old
        ; handle can otherwise survive and make the next MHIAllocDecoder fail.
        ; Reclaim such a stale single-client session by shutting the old engine
        ; down without signalling its former (possibly dead) owner task.
        tst.l   H_MAGIC(a2)
        beq.s   .handle_free
        ; MHI04F: H_QUIT=1 means MHIFreeDecoder() is actively tearing the
        ; previous session down.  This is NOT a stale/orphan handle.  Never
        ; detach H_TASK/H_SIGMASK here: the old FreeDecoder still needs them
        ; for the engine's final wakeup.  Serialize the session boundary and
        ; wait until that FreeDecoder has committed H_MAGIC=0.
        tst.b   H_QUIT(a2)
        beq.s   .really_stale
        lea     diag_shutdown_wait(pc),a0
        bsr     diag_log
        bsr     wait_active_free
        tst.l   d0
        beq.w   .fail
        lea     diag_shutdown_done(pc),a0
        bsr     diag_log
        bra.s   .handle_free
.really_stale:
        lea     diag_stale(pc),a0
        bsr     diag_log
        bsr     recover_stale_decoder
        tst.l   d0
        beq.w   .fail
        lea     diag_recover_ok(pc),a0
        bsr     diag_log
.handle_free:
        tst.l   d4
        beq.w   .fail
        tst.l   d5
        beq.w   .fail
        tst.b   B_ENGINE_READY(a6)
        bne.s   .engine_ok
        lea     diag_need_start(pc),a0
        bsr     diag_log
        bsr     auto_start_engine
        tst.l   d0
        beq.w   .fail
        tst.b   B_ENGINE_READY(a6)
        beq.w   .fail
.engine_ok:
        lea     diag_engine_ok(pc),a0
        bsr     diag_log
        move.l  #HANDLE_MAGIC,H_MAGIC(a2)
        move.l  d4,H_TASK(a2)
        move.l  d5,H_SIGMASK(a2)
        move.b  #MHIF_STOPPED,H_STATUS(a2)
        clr.b   H_PLAYFLAG(a2)
        clr.b   H_STOPREQ(a2)
        clr.b   H_QUIT(a2)
        clr.w   H_QHEAD(a2)
        clr.w   H_QTAIL(a2)
        clr.w   H_QCOUNT(a2)
        clr.w   H_EHEAD(a2)
        clr.w   H_ETAIL(a2)
        clr.w   H_ECOUNT(a2)
        clr.l   H_ENQUEUED(a2)
        clr.l   H_CONSUMED(a2)
        clr.l   H_SIGNALED(a2)
        move.b  #100,H_VOLUME(a2)
        move.b  #50,H_PANNING(a2)
        lea     diag_alloc_ok(pc),a0
        bsr     diag_log
        move.l  a2,d0
        movem.l (sp)+,d2-d5/a2
        rts
.fail:  lea     diag_alloc_fail(pc),a0
        bsr     diag_log
        moveq   #0,d0
        movem.l (sp)+,d2-d5/a2
        rts

; MHI04F active FreeDecoder serialization.
; Entry: a6=library base, a2=embedded handle with H_QUIT already asserted.
; Result: d0!=0 once the OLD MHIFreeDecoder has completed H_MAGIC=0.
; Important: this helper never touches H_TASK/H_SIGMASK and never signals the
; engine/client.  It only yields to AmigaDOS while the old owner finishes.
wait_active_free:
        movem.l d1-d7/a0-a6,-(sp)
        move.l  a6,a5
        move.l  a2,a3
        tst.l   H_MAGIC(a3)
        beq.s   .already_free
        lea     dos_name(pc),a1
        moveq   #36,d0
        move.l  B_SYSBASE(a5),a6
        jsr     _LVOOpenLibrary(a6)
        tst.l   d0
        beq.s   .wait_fail
        move.l  d0,a4
        move.w  #249,d7              ; bounded ~5 s at 50 Hz
.wait_loop:
        tst.l   H_MAGIC(a3)
        beq.s   .free_with_dos
        moveq   #1,d1
        move.l  a4,a6
        jsr     _DOSDelay(a6)
        dbra    d7,.wait_loop
        moveq   #0,d6
        bra.s   .close_dos
.free_with_dos:
        moveq   #1,d6
.close_dos:
        move.l  a4,a1
        move.l  B_SYSBASE(a5),a6
        jsr     _LVOCloseLibrary(a6)
        move.l  d6,d0
        bra.s   .wait_out
.already_free:
        moveq   #1,d0
        bra.s   .wait_out
.wait_fail:
        moveq   #0,d0
.wait_out:
        movem.l (sp)+,d1-d7/a0-a6
        rts

; MHI04R stale-session recovery for AmiAMP close/reopen.
; Entry: a6 = library base, a2 = embedded old handle.
; Result: d0 != 0 when the stale session is fully gone and may be reused.
; The old owner task/signal is detached before the engine is told to quit,
; because the previous AmiAMP process may already have disappeared.
recover_stale_decoder:
        movem.l d1-d7/a0-a6,-(sp)
        move.l  a6,a5                  ; stable library base
        move.l  a2,a3                  ; signal_engine expects handle in a3

        ; Never Signal() the former client while reclaiming an orphan.
        clr.l   H_TASK(a3)
        clr.l   H_SIGMASK(a3)
        move.b  #1,H_QUIT(a3)
        move.b  #1,H_STOPREQ(a3)
        clr.b   H_PLAYFLAG(a3)
        move.b  #MHIF_STOPPED,H_STATUS(a3)

        tst.b   B_ENGINE_READY(a5)
        bne.s   .recover_engine_live
        lea     diag_recover_ready0(pc),a0
        bsr     diag_log
        bra.s   .clear_handle
.recover_engine_live:
        lea     diag_recover_ready1(pc),a0
        bsr     diag_log

        ; Ask the old persistent engine to terminate completely.
        move.l  B_SYSBASE(a5),a6
        bsr     signal_engine
        tst.b   B_ENGINE_READY(a5)
        beq.s   .clear_handle

        ; Poll boundedly; do not inherit/wait on the old client's signal bit.
        lea     dos_name(pc),a1
        moveq   #36,d0
        jsr     _LVOOpenLibrary(a6)
        tst.l   d0
        beq.s   .failed
        move.l  d0,a4
        move.w  #249,d7
.wait_gone:
        tst.b   B_ENGINE_READY(a5)
        beq.s   .gone_with_dos
        moveq   #1,d1
        move.l  a4,a6
        jsr     _DOSDelay(a6)
        dbra    d7,.wait_gone
        moveq   #0,d6
        bra.s   .close_dos
.gone_with_dos:
        moveq   #1,d6
.close_dos:
        move.l  a4,a1
        move.l  B_SYSBASE(a5),a6
        jsr     _LVOCloseLibrary(a6)
        tst.l   d6
        beq.s   .failed

.clear_handle:
        ; Engine no longer owns any old compressed/MMAL data.  Do not return
        ; stale pointers to a dead client; simply discard the orphaned queue.
        clr.l   H_MAGIC(a3)
        clr.l   H_TASK(a3)
        clr.l   H_SIGMASK(a3)
        move.b  #MHIF_STOPPED,H_STATUS(a3)
        clr.b   H_PLAYFLAG(a3)
        clr.b   H_STOPREQ(a3)
        clr.b   H_QUIT(a3)
        clr.w   H_QHEAD(a3)
        clr.w   H_QTAIL(a3)
        clr.w   H_QCOUNT(a3)
        clr.w   H_EHEAD(a3)
        clr.w   H_ETAIL(a3)
        clr.w   H_ECOUNT(a3)
        clr.l   H_ENQUEUED(a3)
        clr.l   H_CONSUMED(a3)
        clr.l   H_SIGNALED(a3)
        lea     diag_recover_cleared(pc),a0
        bsr     diag_log
        moveq   #1,d0
        bra.s   .out
.failed:
        lea     diag_recover_fail(pc),a0
        bsr     diag_log
        moveq   #0,d0
.out:
        movem.l (sp)+,d1-d7/a0-a6
        rts

; MHI04 automatic engine bootstrap.
; Entry: a6 = mhiberry.library base.
; Result: d0 = nonzero when B_ENGINE_READY became set, zero on launch/timeout.
; SystemTagList is asynchronous, so AmigaDOS owns command/process cleanup.
; We retain the external Process architecture: no VCHIQ/MMAL/DOS player body
; ever runs in the library caller itself.
auto_start_engine:
        movem.l d1-d7/a0-a6,-(sp)
        lea     diag_auto_entry(pc),a0
        bsr     diag_log
        move.l  a6,a5                  ; keep mhiberry.library base
        tst.b   B_ENGINE_READY(a5)
        bne.w   .ready

        ; Open dos.library V36+, required for SystemTagList.
        move.l  B_SYSBASE(a5),a6
        lea     dos_name(pc),a1
        moveq   #36,d0
        jsr     _LVOOpenLibrary(a6)
        tst.l   d0
        beq.w   .failed_no_dos
        move.l  d0,a4                  ; DOSBase

        ; MHI04T: SystemTagList()+SYS_Asynch owns and closes the child's
        ; input/output streams when the command exits.  Never let it inherit
        ; AmiAMP/Workbench streams: that corrupts the caller environment and
        ; can make the next auto-start fail after the first engine terminates.
        ; Give the child two private NIL: handles instead.  On successful
        ; asynchronous launch DOS owns them; on launch failure we close them.
        lea     nil_name(pc),a0
        move.l  a0,d1
        move.l  #MODE_OLDFILE,d2
        move.l  a4,a6
        jsr     _DOSOpen(a6)
        move.l  d0,d4
        beq.w   .failed_with_dos

        lea     nil_name(pc),a0
        move.l  a0,d1
        move.l  #MODE_NEWFILE,d2
        move.l  a4,a6
        jsr     _DOSOpen(a6)
        move.l  d0,d5
        beq.w   .failed_with_input

        ; Build the tag list on our stack because the NIL: BPTRs are runtime
        ; values.  The list is consumed synchronously by SystemTagList itself;
        ; the launched command then owns d4/d5 until it exits.
        suba.l  #32,sp
        move.l  #SYS_Input,(sp)
        move.l  d4,4(sp)
        move.l  #SYS_Output,8(sp)
        move.l  d5,12(sp)
        move.l  #SYS_Asynch,16(sp)
        move.l  #1,20(sp)
        move.l  #TAG_DONE,24(sp)
        clr.l   28(sp)
        lea     engine_command(pc),a0
        move.l  a0,d1
        move.l  sp,d2
        move.l  a4,a6
        jsr     _DOSSystemTagList(a6)
        adda.l  #32,sp
        cmpi.l  #-1,d0
        beq.s   .failed_with_streams
        lea     diag_system_ok(pc),a0
        bsr     diag_log

        ; Ownership transferred to the asynchronous command.  Do not Close().
        clr.l   d4
        clr.l   d5

        ; The child registers B_ENGINE_TASK/SIGMASK/READY immediately at start.
        ; Poll for at most 250 ticks (~5 s PAL) so a missing C:mhiberry_engine
        ; can never hang AmiAMP forever.
        move.w  #249,d7
.wait_ready:
        tst.b   B_ENGINE_READY(a5)
        bne.s   .ready_with_dos
        moveq   #1,d1
        move.l  a4,a6
        jsr     _DOSDelay(a6)
        dbra    d7,.wait_ready
        bra.s   .failed_with_dos

.ready_with_dos:
        lea     diag_ready(pc),a0
        bsr     diag_log
        moveq   #1,d6
        bra.s   .close_dos
.failed_with_streams:
        lea     diag_system_fail(pc),a0
        bsr     diag_log
        ; SystemTagList failed before ownership transfer: close both private
        ; handles ourselves.
        move.l  d5,d1
        move.l  a4,a6
        jsr     _DOSClose(a6)
.failed_with_input:
        tst.l   d4
        beq.s   .failed_with_dos
        move.l  d4,d1
        move.l  a4,a6
        jsr     _DOSClose(a6)
.failed_with_dos:
        lea     diag_auto_fail(pc),a0
        bsr     diag_log
        moveq   #0,d6
.close_dos:
        move.l  a4,a1
        move.l  B_SYSBASE(a5),a6
        jsr     _LVOCloseLibrary(a6)
        move.l  d6,d0
        bra.s   .out
.ready:
        moveq   #1,d0
        bra.s   .out
.failed_no_dos:
        moveq   #0,d0
.out:
        movem.l (sp)+,d1-d7/a0-a6
        rts

mhi_free_decoder:
        ; MHI04H: keep the external engine process resident between MHI handles.
        ; FreeDecoder must release the current decoder/session, not terminate the
        ; helper process.  Reuse the hardware-proven synchronous MHIStop fence:
        ; it waits until B_ENGINE_BUSY=0, so MP314/MMAL no longer owns any client
        ; buffer.  Then discard all queue bookkeeping and release the handle.
        movem.l d0-d7/a0-a6,-(sp)
        lea     diag_free_entry(pc),a0
        bsr     diag_log
        cmpi.l  #HANDLE_MAGIC,H_MAGIC(a3)
        bne.s   .done

        ; This exact stop fence is the same path used by the working MHIStop.
        bsr     mhi_stop

        ; MHIStop has made ENGINE_BUSY=0 and returned/flushed all buffers.
        ; FreeDecoder owns no requirement to hand those addresses back through
        ; GetEmpty, so discard all old session bookkeeping before reuse.
        move.l  4.w,a6
        jsr     _LVOForbid(a6)
        clr.l   H_MAGIC(a3)
        clr.l   H_TASK(a3)
        clr.l   H_SIGMASK(a3)
        move.b  #MHIF_STOPPED,H_STATUS(a3)
        clr.b   H_PLAYFLAG(a3)
        clr.b   H_STOPREQ(a3)
        clr.b   H_QUIT(a3)
        clr.w   H_QHEAD(a3)
        clr.w   H_QTAIL(a3)
        clr.w   H_QCOUNT(a3)
        clr.w   H_EHEAD(a3)
        clr.w   H_ETAIL(a3)
        clr.w   H_ECOUNT(a3)
        clr.l   H_ENQUEUED(a3)
        clr.l   H_CONSUMED(a3)
        clr.l   H_SIGNALED(a3)
        jsr     _LVOPermit(a6)

        ; Deliberately leave B_ENGINE_READY/B_ENGINE_TASK/B_ENGINE_SIGMASK alone.
        ; The silent engine is now idle in mhi3_engine_wait and can service the
        ; next MHIAllocDecoder without process shutdown/restart.
        lea     diag_free_engine_kept(pc),a0
        bsr     diag_log
.done:
        lea     diag_free_done(pc),a0
        bsr     diag_log
        movem.l (sp)+,d0-d7/a0-a6
        rts

mhi_queue_buffer:
        movem.l d2-d4/a2/a6,-(sp)
        cmpi.l  #HANDLE_MAGIC,H_MAGIC(a3)
        bne.w   .fail
        tst.l   a0
        beq.w   .fail
        tst.l   d0
        beq.w   .fail
        move.l  a0,a2
        move.l  d0,d2
        move.l  4.w,a6
        jsr     _LVOForbid(a6)
        moveq   #0,d3
        move.w  H_QCOUNT(a3),d3
        moveq   #0,d4
        move.w  H_ECOUNT(a3),d4
        add.w   d4,d3
        cmpi.w  #QUEUE_SLOTS,d3
        bhs.s   .full
        moveq   #0,d3
        move.w  H_QTAIL(a3),d3
        lsl.l   #2,d3
        lea     H_QBUFS(a3),a0
        move.l  a2,0(a0,d3.l)
        lea     H_QSIZES(a3),a0
        move.l  d2,0(a0,d3.l)
        addq.w  #1,H_QTAIL(a3)
        andi.w  #QUEUE_MASK,H_QTAIL(a3)
        addq.w  #1,H_QCOUNT(a3)
        addq.l  #1,H_ENQUEUED(a3)
        jsr     _LVOPermit(a6)
        cmpi.b  #MHIF_OUT_OF_DATA,H_STATUS(a3)
        bne.s   .maybe_wake
        tst.b   H_PLAYFLAG(a3)
        beq.s   .maybe_wake
        move.b  #MHIF_PLAYING,H_STATUS(a3)
.maybe_wake:
        tst.b   H_PLAYFLAG(a3)
        beq.s   .ok
        bsr     signal_engine
.ok:    moveq   #-1,d0
        movem.l (sp)+,d2-d4/a2/a6
        rts
.full:  jsr     _LVOPermit(a6)
.fail:  moveq   #0,d0
        movem.l (sp)+,d2-d4/a2/a6
        rts

mhi_get_empty:
        movem.l d2/a1/a6,-(sp)
        cmpi.l  #HANDLE_MAGIC,H_MAGIC(a3)
        bne.s   .none
        move.l  4.w,a6
        jsr     _LVOForbid(a6)
        tst.w   H_ECOUNT(a3)
        beq.s   .empty
        moveq   #0,d2
        move.w  H_EHEAD(a3),d2
        lsl.l   #2,d2
        lea     H_EBUFS(a3),a1
        move.l  0(a1,d2.l),d2
        addq.w  #1,H_EHEAD(a3)
        andi.w  #QUEUE_MASK,H_EHEAD(a3)
        subq.w  #1,H_ECOUNT(a3)
        jsr     _LVOPermit(a6)
        move.l  d2,d0
        movem.l (sp)+,d2/a1/a6
        rts
.empty: jsr     _LVOPermit(a6)
.none:  moveq   #0,d0
        movem.l (sp)+,d2/a1/a6
        rts

mhi_get_status:
        cmpi.l  #HANDLE_MAGIC,H_MAGIC(a3)
        bne.s   .bad
        moveq   #0,d0
        move.b  H_STATUS(a3),d0
        rts
.bad:   moveq   #MHIF_STOPPED,d0
        rts

mhi_play:
        movem.l d0/a1/a6,-(sp)
        cmpi.l  #HANDLE_MAGIC,H_MAGIC(a3)
        bne.s   .done
        ; MHI03h STOP->PLAY race fix:
        ; AmiAMP may issue MHIStop() and immediately queue/start the next title.
        ; MHIStop is intentionally non-blocking, so while the old MP314 session
        ; is still BUSY its STOPREQ must remain set until the engine observes it.
        ; Clearing STOPREQ here used to let the old session survive and consume
        ; new-title buffers at the previous title's position.
        moveq   #0,d0
        move.b  H_STATUS(a3),d0
        move.b  #1,H_PLAYFLAG(a3)
        tst.b   H_STOPREQ(a3)
        beq.s   .clear_stop
        tst.b   B_ENGINE_BUSY(a6)
        bne.s   .pending_restart
.clear_stop:
        clr.b   H_STOPREQ(a3)
        cmpi.b  #MHIF_PAUSED,d0
        beq.s   .resume
        tst.w   H_QCOUNT(a3)
        beq.s   .nodata
.resume:
        move.b  #MHIF_PLAYING,H_STATUS(a3)
        move.l  4.w,a6
        bsr     signal_engine
        bra.s   .done
.pending_restart:
        ; Keep STOPREQ asserted.  PLAYFLAG marks a restart pending; the engine
        ; completes/cleans the old MP314 session first and starts the queued new
        ; stream only afterwards.
        tst.w   H_QCOUNT(a3)
        beq.s   .pending_nodata
        move.b  #MHIF_PLAYING,H_STATUS(a3)
        bra.s   .pending_signal
.pending_nodata:
        move.b  #MHIF_OUT_OF_DATA,H_STATUS(a3)
.pending_signal:
        move.l  4.w,a6
        bsr     signal_engine
        bra.s   .done
.nodata:move.b  #MHIF_OUT_OF_DATA,H_STATUS(a3)
.done:  movem.l (sp)+,d0/a1/a6
        rts

mhi_stop:
        movem.l d0-d3/a0-a2/a6,-(sp)
        cmpi.l  #HANDLE_MAGIC,H_MAGIC(a3)
        bne.s   .done

        ; MHI03i SYNCHRONOUS STOP FENCE:
        ; MHIStop must not return buffers to the client while the external
        ; MP314/MMAL session can still be reading/using them.  Request stop,
        ; wake the engine and wait until its complete session cleanup has
        ; finished (B_ENGINE_BUSY=0).  Only then flush queued buffers.
        ; This makes a direct AmiAMP title change equivalent to an explicit
        ; completed Stop -> refill new title -> Play sequence.
        move.b  #1,H_STOPREQ(a3)
        clr.b   H_PLAYFLAG(a3)
        move.b  #MHIF_STOPPED,H_STATUS(a3)
        move.l  4.w,a6
        bsr     signal_engine
.wait_engine:
        tst.b   ENGINE_BUSY_FROM_HANDLE(a3)
        beq.s   .engine_stopped
        move.l  H_SIGMASK(a3),d0
        tst.l   d0
        beq.s   .wait_engine
        jsr     _LVOWait(a6)
        bra.s   .wait_engine

.engine_stopped:
        ; Engine has disabled audio_render/MMAL and returned its current MHI
        ; buffer.  It is now safe to release all still-queued buffers too.
        jsr     _LVOForbid(a6)
.flush: tst.w   H_QCOUNT(a3)
        beq.s   .flushed
        cmpi.w  #QUEUE_SLOTS,H_ECOUNT(a3)
        bhs.s   .flushed
        bsr     pop_q_to_empty_locked
        bra.s   .flush
.flushed:
        move.w  H_ECOUNT(a3),d3
        jsr     _LVOPermit(a6)
        tst.w   d3
        beq.s   .done
        bsr     signal_owner
.done:  movem.l (sp)+,d0-d3/a0-a2/a6
        rts

mhi_pause:
        cmpi.l  #HANDLE_MAGIC,H_MAGIC(a3)
        bne.s   .done
        cmpi.b  #MHIF_PLAYING,H_STATUS(a3)
        bne.s   .done
        move.b  #MHIF_PAUSED,H_STATUS(a3)
        clr.b   H_PLAYFLAG(a3)
.done:  rts

mhi_query:
        cmpi.l  #MHIQ_CAPABILITIES,d1
        beq.w   .cap
        cmpi.l  #MHIQ_DECODER_NAME,d1
        beq.w   .name
        cmpi.l  #MHIQ_DECODER_VERSION,d1
        beq.w   .ver
        cmpi.l  #MHIQ_AUTHOR,d1
        beq.w   .author
        cmpi.l  #MHIQ_MPEG1,d1
        beq.s   .yes
        cmpi.l  #MHIQ_MPEG2,d1
        beq.s   .yes
        cmpi.l  #MHIQ_MPEG25,d1
        beq.s   .yes
        cmpi.l  #MHIQ_LAYER3,d1
        beq.s   .yes
        cmpi.l  #MHIQ_VARIABLE_BITRATE,d1
        beq.s   .yes
        cmpi.l  #MHIQ_JOINT_STEREO,d1
        beq.s   .yes
        cmpi.l  #MHIQ_VOLUME_CONTROL,d1
        beq.s   .yes
        cmpi.l  #MHIQ_IS_HARDWARE,d1
        beq.s   .yes
        moveq   #0,d0
        rts
.yes:   moveq   #1,d0
        rts
.cap:   lea capability_string(pc),a0
        move.l a0,d0
        rts
.name:  lea decoder_name(pc),a0
        move.l a0,d0
        rts
.ver:   lea decoder_version(pc),a0
        move.l a0,d0
        rts
.author:lea author_string(pc),a0
        move.l a0,d0
        rts

mhi_set_param:
        cmpi.l  #HANDLE_MAGIC,H_MAGIC(a3)
        bne.s   .done
        cmpi.w  #MHIP_VOLUME,d0
        bne.s   .pan
        cmpi.l  #100,d1
        bls.s   .vok
        moveq   #100,d1
.vok:   move.b  d1,H_VOLUME(a3)
        rts
.pan:   cmpi.w  #MHIP_PANNING,d0
        bne.s   .done
        cmpi.l  #100,d1
        bls.s   .pok
        moveq   #100,d1
.pok:   move.b  d1,H_PANNING(a3)
.done:  rts

; Called with SysBase in a6, a3=handle. Engine fields are base-relative,
; and handle begins at B_HANDLE, therefore engine offsets are adjusted here.
signal_engine:
        movem.l d0/a1,-(sp)
        move.l  B_ENGINE_TASK-B_HANDLE(a3),a1
        move.l  B_ENGINE_SIGMASK-B_HANDLE(a3),d0
        tst.l   a1
        beq.s   .done
        tst.l   d0
        beq.s   .done
        jsr     _LVOSignal(a6)
.done:  movem.l (sp)+,d0/a1
        rts

signal_owner:
        movem.l d0/a1,-(sp)
        move.l  H_TASK(a3),a1
        move.l  H_SIGMASK(a3),d0
        tst.l   a1
        beq.s   .done
        tst.l   d0
        beq.s   .done
        jsr     _LVOSignal(a6)
        addq.l  #1,H_SIGNALED(a3)
.done:  movem.l (sp)+,d0/a1
        rts

; Forbid active, a3=handle.
pop_q_to_empty_locked:
        movem.l d0-d2/a0-a1,-(sp)
        moveq   #0,d0
        move.w  H_QHEAD(a3),d0
        lsl.l   #2,d0
        lea     H_QBUFS(a3),a0
        move.l  0(a0,d0.l),d1
        addq.w  #1,H_QHEAD(a3)
        andi.w  #QUEUE_MASK,H_QHEAD(a3)
        subq.w  #1,H_QCOUNT(a3)
        moveq   #0,d2
        move.w  H_ETAIL(a3),d2
        lsl.l   #2,d2
        lea     H_EBUFS(a3),a1
        move.l  d1,0(a1,d2.l)
        addq.w  #1,H_ETAIL(a3)
        andi.w  #QUEUE_MASK,H_ETAIL(a3)
        addq.w  #1,H_ECOUNT(a3)
        addq.l  #1,H_CONSUMED(a3)
        movem.l (sp)+,d0-d2/a0-a1
        rts


; MHI04 RELEASE: lifecycle logging disabled.
; rts+nop replaces the original 4-byte MOVEM so following code/data keep layout.
diag_log:
        rts
        nop
        ; Unreachable diagnostic implementation retained for source comparison.
        move.l  a0,a3
        move.l  4.w,a6
        lea     dos_name(pc),a1
        moveq   #36,d0
        jsr     _LVOOpenLibrary(a6)
        tst.l   d0
        beq.s   .out
        move.l  d0,a4

        lea     diag_path(pc),a0
        move.l  a0,d1
        move.l  #MODE_READWRITE,d2
        move.l  a4,a6
        jsr     _DOSOpen(a6)
        move.l  d0,d4
        bne.s   .opened
        lea     diag_path(pc),a0
        move.l  a0,d1
        move.l  #MODE_NEWFILE,d2
        jsr     _DOSOpen(a6)
        move.l  d0,d4
        beq.s   .close_dos
.opened:
        move.l  d4,d1
        moveq   #0,d2
        moveq   #OFFSET_END,d3
        jsr     _DOSSeek(a6)

        move.l  a3,a0
        moveq   #0,d3
.len:
        tst.b   0(a0,d3.l)
        beq.s   .write
        addq.l  #1,d3
        bra.s   .len
.write:
        move.l  d4,d1
        move.l  a3,d2
        jsr     _DOSWrite(a6)
        move.l  d4,d1
        jsr     _DOSClose(a6)
.close_dos:
        move.l  a4,a1
        move.l  4.w,a6
        jsr     _LVOCloseLibrary(a6)
.out:
        movem.l (sp)+,d0-d7/a0-a6
        rts

        even
lib_name:          dc.b "mhiberry.library",0
id_string:         dc.b "mhiberry.library 1.16 (25.09.2026)",0
ver_string:        dc.b 0,"$VER: mhiberry.library 1.16 (25.09.2026)",0

decoder_name:      dc.b "BerryMP3 PiStorm CPU1 HDMI",0
decoder_version:   dc.b "1.0 MHI->CPU1->HDMI + MHI04 release           ",0
author_string:     dc.b "MichiB210",0
capability_string: dc.b "audio/mpeg{audio/mp3},audio/mp3",0
dos_name:          dc.b "dos.library",0
engine_command:    dc.b "C:mhiberry_engine",0
nil_name:          dc.b "NIL:",0
diag_path:         dc.b "RAM:mhiberry_diag.txt",0
diag_alloc_entry:  dc.b "ALLOC entry",10,0
diag_shutdown_wait: dc.b "ALLOC shutdown-in-progress -> wait old FREE",10,0
diag_shutdown_done: dc.b "ALLOC old FREE completed -> handle free",10,0
diag_stale:        dc.b "ALLOC stale-handle",10,0
diag_recover_ok:   dc.b "ALLOC stale recovered",10,0
diag_recover_ready0: dc.b "RECOVER engine READY=0",10,0
diag_recover_ready1: dc.b "RECOVER engine READY=1",10,0
diag_recover_cleared: dc.b "RECOVER handle MAGIC=0",10,0
diag_recover_fail: dc.b "RECOVER FAIL",10,0
diag_need_start:   dc.b "ALLOC engine not ready -> autostart",10,0
diag_engine_ok:    dc.b "ALLOC engine ready",10,0
diag_alloc_ok:     dc.b "ALLOC success",10,0
diag_alloc_fail:   dc.b "ALLOC FAIL",10,0
diag_auto_entry:   dc.b "AUTO entry",10,0
diag_system_ok:    dc.b "AUTO SystemTagList accepted",10,0
diag_system_fail:  dc.b "AUTO SystemTagList FAIL",10,0
diag_ready:        dc.b "AUTO engine READY",10,0
diag_auto_fail:    dc.b "AUTO timeout/fail",10,0
diag_free_entry:   dc.b "FREE entry",10,0
diag_free_same_task: dc.b "FREE caller == MHI signal owner",10,0
diag_free_other_task: dc.b "FREE caller != MHI signal owner",10,0
diag_free_signal:  dc.b "FREE engine quit signalled",10,0
diag_free_engine_gone: dc.b "FREE engine READY=0",10,0
diag_free_done:    dc.b "FREE done",10,0
diag_free_engine_kept: dc.b "FREE handle released; engine kept READY",10,0
diag_free_timeout: dc.b "FREE TIMEOUT waiting ENGINE_READY=0",10,0
        even
        end
