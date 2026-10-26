#include <stdint.h>
#include <stddef.h>
#include "mp3dec.h"                 /* Helix fixed-point public API */
#include "berry_mp301_runtime.h"
void *memset(void *, int, size_t);
void *memcpy(void *, const void *, size_t);

typedef struct BerryMailbox {
    uint32_t _pad00[6];
    uint32_t in_phys;       /* +24 */
    uint32_t in_len;        /* +28 */
    uint32_t out_phys;      /* +32 */
    uint32_t out_len;       /* +36 */
    uint32_t param0;        /* +40 */
    uint32_t param1;        /* +44 */
    uint32_t work_phys;     /* +48 */
    uint32_t work_len;      /* +52 */
} BerryMailbox;

typedef struct BerryMp3Work {
    uint32_t magic;         /* BMP3 */
    uint32_t version;
    uint32_t stream_off;
    uint32_t frame_index;
    uint64_t decoder;
    uint32_t initialized;
    uint32_t heap_used;
    uint32_t init_rate;
    uint32_t init_channels;
    uint32_t last_bitrate;
    uint32_t reserved[5];   /* 64-byte control area */
} BerryMp3Work;

typedef struct BerryMp3Out {
    uint32_t marker;        /* MP31 */
    uint32_t status;
    uint32_t samplerate;
    uint32_t channels;
    uint32_t bytesconsumed;
    uint32_t samples;       /* interleaved sample values */
    uint32_t error;
    uint32_t frame_index;
    uint32_t input_offset;
    uint32_t next_offset;
    uint32_t pcm_fnv1a;
    int32_t first_l, first_r, last_l, last_r;
    uint32_t heap_used;
    uint32_t capabilities;
    uint32_t reserved[47];
    int16_t pcm[32768];     /* 64 KiB, native AArch64-BE PCM16 */
} BerryMp3Out;

typedef struct { uint32_t a,b,c,d; } BerryRet;

#define BMP3_MAGIC 0x424d5033u
#define MP31_MARK  0x4d503331u
#define BMP3_VERSION 1u
#define WORK_CTRL 64u
#define WORK_HEAP_BYTES 0x00018000u   /* 96 KiB; Helix documented data need is far below this */
#define WORK_STACK_BYTES 0x00010000u  /* 64 KiB private CPU1 stack at top of work area */
#define WORK_MIN (WORK_CTRL + WORK_HEAP_BYTES + WORK_STACK_BYTES)
#define OUT_MIN (256u + 65536u)
#define PCM_CAP 65536u
#define MP3_CAP_LAYER3 1u

static inline void *alias_ptr(uint32_t phys, uint64_t alias_add)
{
    return (void *)(uintptr_t)((uint64_t)phys + alias_add);
}
static uint32_t fnv1a_update(uint32_t h,const uint8_t *p,uint32_t n)
{
    while(n--) { h^=*p++; h*=0x01000193u; } return h;
}

_Static_assert(offsetof(BerryMailbox,in_phys)==24,"mailbox in_phys ABI");
_Static_assert(offsetof(BerryMailbox,work_len)==52,"mailbox work_len ABI");
_Static_assert(sizeof(BerryMp3Work)==64,"work control must stay 64 bytes");
_Static_assert(offsetof(BerryMp3Out,pcm)==256,"PCM payload ABI");
_Static_assert(sizeof(BerryMp3Out)==65792,"output ABI size");

/* Validate a normal Layer-III frame and return its complete byte length.
   Free-format is deliberately excluded from BerryMP301's first hardware test. */
static int mp3_frame_bytes(const uint8_t *h, uint32_t n)
{
    static const uint16_t br_m1_l3[16]={0,32,40,48,56,64,80,96,112,128,160,192,224,256,320,0};
    static const uint16_t br_m2_l3[16]={0,8,16,24,32,40,48,56,64,80,96,112,128,144,160,0};
    static const uint32_t sr_base[3]={44100,48000,32000};
    if(n<4 || h[0]!=0xff || (h[1]&0xe0)!=0xe0) return -1;
    unsigned ver=(h[1]>>3)&3u, layer=(h[1]>>1)&3u;
    unsigned bi=(h[2]>>4)&15u, si=(h[2]>>2)&3u, pad=(h[2]>>1)&1u;
    if(ver==1u || layer!=1u || bi==0u || bi==15u || si==3u) return -1;
    uint32_t sr=sr_base[si];
    if(ver==2u) sr>>=1; else if(ver==0u) sr>>=2;
    uint32_t br=(ver==3u ? br_m1_l3[bi] : br_m2_l3[bi])*1000u;
    uint32_t z=((ver==3u ? 144u : 72u)*br)/sr + pad;
    return (z>=24u && z<=2048u) ? (int)z : -1;
}

BerryRet berry_mp301_c_entry(BerryMailbox *mb, uint64_t alias_add, void *module_base)
{
    (void)module_base;
    BerryRet ret={0,0,0,0};
    if(!mb) { ret.c=90; return ret; }

    BerryMp3Work *w=(BerryMp3Work*)alias_ptr(mb->work_phys,alias_add);
    BerryMp3Out *o=(BerryMp3Out*)alias_ptr(mb->out_phys,alias_add);
    if(!w || mb->work_len<WORK_MIN) { ret.c=91; return ret; }
    if(!o || mb->out_len<OUT_MIN) { ret.c=92; return ret; }

    if(mb->param0==0 || mb->param0==2) {
        memset(w,0,WORK_CTRL);
        memset(o,0,256);
        berry_heap_bind((uint8_t*)w+WORK_CTRL,WORK_HEAP_BYTES);
        HMP3Decoder h=MP3InitDecoder();
        if(!h || berry_heap_failed()) { ret.c=93; return ret; }
        w->magic=BMP3_MAGIC; w->version=BMP3_VERSION;
        w->decoder=(uint64_t)(uintptr_t)h;
        w->heap_used=(uint32_t)berry_heap_used();
        o->marker=MP31_MARK; o->status=1; o->heap_used=w->heap_used;
        o->capabilities=MP3_CAP_LAYER3;
        ret.a=1; return ret;
    }

    if(mb->param0!=3 || w->magic!=BMP3_MAGIC || !w->decoder) { ret.c=96; return ret; }
    uint8_t *input=(uint8_t*)alias_ptr(mb->in_phys,alias_add);
    if(!input || !mb->in_len) { ret.c=97; return ret; }

    memset(o,0,256);
    o->marker=MP31_MARK; o->status=4; o->input_offset=w->stream_off;
    o->capabilities=MP3_CAP_LAYER3;

    HMP3Decoder h=(HMP3Decoder)(uintptr_t)w->decoder;
    uint32_t local_off=0, frames=0, blocks=0, pcm_bytes=0, total_samples=0;
    uint32_t hash=0x811c9dc5u;
    int have_first=0;

    while(local_off<mb->in_len) {
        uint32_t left=mb->in_len-local_off;
        if(left<4u) break;

        /* Skip a complete ID3v2 tag before looking for MPEG sync. */
        if(left>=10u && input[local_off]=='I' && input[local_off+1]=='D' && input[local_off+2]=='3') {
            uint32_t tag=((uint32_t)(input[local_off+6]&0x7f)<<21) |
                         ((uint32_t)(input[local_off+7]&0x7f)<<14) |
                         ((uint32_t)(input[local_off+8]&0x7f)<<7)  |
                         ((uint32_t)(input[local_off+9]&0x7f));
            tag+=10u;
            if(input[local_off+5]&0x10) tag+=10u;
            if(tag<=left) { local_off+=tag; continue; }
            break; /* retain an incomplete ID3v2 tag for the next refill */
        }

        int sync=MP3FindSyncWord(input+local_off,(int)left);
        if(sync<0) {
            /* Keep up to the last 3 bytes: an MPEG sync/header may straddle
               the next 68k rolling-window refill boundary. */
            uint32_t keep = left < 3u ? left : 3u;
            local_off += left - keep;
            break;
        }
        local_off+=(uint32_t)sync;
        left=mb->in_len-local_off;
        if(left<4u) break;

        int frame_bytes=mp3_frame_bytes(input+local_off,left);
        if(frame_bytes<0) { local_off+=1u; continue; }
        if((uint32_t)frame_bytes>left) {
            /* Terminal partial frame: consume nothing from the frame itself.
               The 68k rolling reader retains this tail and appends more bytes. */
            break;
        }
        if(PCM_CAP-pcm_bytes<4608u && frames) break;

        const unsigned char *p=input+local_off;
        size_t bytes_left=(size_t)frame_bytes;
        short *dst=(short*)(void*)((uint8_t*)o+256u+pcm_bytes);
        int err=MP3Decode(h,&p,&bytes_left,dst,0);
        uint32_t consumed=(uint32_t)frame_bytes-(uint32_t)bytes_left;
        if(err==ERR_MP3_MAINDATA_UNDERFLOW) {
            /* Normal when starting before the Layer-III bit reservoir is primed.
               Helix has already copied this frame's main data into its reservoir. */
            if(!consumed || consumed>(uint32_t)frame_bytes) { ret.c=101; return ret; }
            local_off+=consumed; w->stream_off+=consumed; w->frame_index++; frames++;
            continue;
        }
        if(err) {
            o->error=(uint32_t)(-err); ret.c=100u+(uint32_t)(-err); return ret;
        }
        if(!consumed || consumed>(uint32_t)frame_bytes) { ret.c=101; return ret; }

        MP3FrameInfo fi; memset(&fi,0,sizeof(fi));
        MP3GetLastFrameInfo(h,&fi);
        if(fi.layer!=3 || fi.samprate<=0 || fi.samprate>192000 || fi.nChans!=2 || fi.bitsPerSample!=16) {
            ret.c=102; return ret;
        }
        uint32_t ns=(uint32_t)fi.outputSamps;
        uint32_t nb=ns*2u;
        if(nb>PCM_CAP-pcm_bytes) { ret.c=103; return ret; }

        if(!w->initialized) {
            w->initialized=1; w->init_rate=(uint32_t)fi.samprate; w->init_channels=(uint32_t)fi.nChans;
        } else if(w->init_rate!=(uint32_t)fi.samprate || w->init_channels!=(uint32_t)fi.nChans) {
            ret.c=104; return ret;
        }
        w->last_bitrate=(uint32_t)fi.bitrate;
        local_off+=consumed; w->stream_off+=consumed; w->frame_index++; frames++;

        if(ns) {
            int16_t *q=(int16_t*)(void*)((uint8_t*)o+256u+pcm_bytes);
            if(!have_first) { o->first_l=q[0]; o->first_r=q[1]; have_first=1; }
            o->last_l=q[ns-2]; o->last_r=q[ns-1];
            hash=fnv1a_update(hash,(const uint8_t*)q,nb);
            pcm_bytes+=nb; total_samples+=ns; blocks++;
        }
    }

    /* Junk skipped before the first sync is part of this staged chunk too. */
    w->stream_off=o->input_offset+local_off;
    o->samplerate=w->init_rate; o->channels=w->init_channels;
    o->bytesconsumed=local_off; o->samples=total_samples;
    o->frame_index=w->frame_index; o->next_offset=w->stream_off;
    o->pcm_fnv1a=blocks ? hash : 0u;
    w->heap_used=(uint32_t)berry_heap_used(); o->heap_used=w->heap_used;
    o->reserved[0]=frames; o->reserved[1]=blocks; o->reserved[2]=pcm_bytes;
    o->reserved[3]=total_samples; o->reserved[4]=local_off; o->reserved[5]=w->last_bitrate;
    ret.a=o->pcm_fnv1a; ret.b=local_off; ret.c=0; ret.d=w->frame_index;
    return ret;
}
