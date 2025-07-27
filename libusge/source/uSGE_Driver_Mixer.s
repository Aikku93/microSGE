/************************************************/
#include "uSGE_ASM.h"
#include "uSGE_Config.h"
#include "uSGE_Driver_MixerMacros.inc"
/************************************************/

//! Once a one-shot sample has ended, we loop into silence.
//! This defines the size of this silence (excluding padding!).
#define SILENT_LOOP_SIZE 64

/************************************************/

@ r0 must be reserved!
@ This function is called from uSGE_Driver_Open(),
@ which has the driver pointer in r0.

ASM_FUNC_GLOBAL(uSGE_Driver_LoadMixer)
ASM_FUNC_BEG   (uSGE_Driver_LoadMixer, ASM_FUNCSECT_TEXT;ASM_MODE_THUMB)

uSGE_Driver_LoadMixer:
	PUSH	{r4-r7}
	MOV	r1, #MAX_VOICES_PER_CHUNK
	LDR	r2, =.LMixerArea_VoxArea + OFFSET_OF_ADR_FROM_START
	LDR	r3, =.LLoadMixerOpcodes_MixVoice
	MOV	r6, #.LMixerArea_VoxArea + OFFSET_OF_ADR_FROM_START - (uSGE_Driver_VoxTable + (MAX_VOICES_PER_CHUNK-1)*USGE_VOXTABLE_ENTRY_SIZE) + 0x08
	LDR	r7, .LLoadMixer_ADR_Opcode

.LLoadMixer_LoadVoiceMixers:
1:	MOV	r4, r6                                 @ Rotate offset as needed
	MOV	r5, #0x10
	CMP	r4, #0xFF
	BLS	11f
10:	LSR	r4, #0x02
	SUB	r5, #0x01
	CMP	r4, #0xFF
	BHI	10b
11:	LSL	r5, #0x1C                              @ Mask and shift rotate amount
	LSR	r5, #0x1C - 8
	ADD	r4, r5                                 @ Store ADR instruction
	ADD	r4, r7
	STMIA	r2!, {r4}
	MOV	r4, #STRIDE_BETWEEN_VOICES - 0x04      @ Copy remaining instructions
12:	SUB	r4, #0x04
	LDR	r5, [r3, r4]
	STR	r5, [r2, r4]
	BHI	12b
2:	ADD	r6, #STRIDE_BETWEEN_VOICES + USGE_VOXTABLE_ENTRY_SIZE
	ADD	r2, #STRIDE_BETWEEN_VOICES - 0x04
	SUB	r1, #0x01                              @ More voices?
	BNE	1b

.LLoadMixer_LoadMergeStore:
	ADD	r3, #STRIDE_BETWEEN_VOICES - 0x04      @ Load block merge/store sequence
	MOV	r4, #.LLoadMixerOpcodes_MergeStoreLoop_End - .LLoadMixerOpcodes_MergeStoreLoop
0:	SUB	r4, #0x04
	LDR	r5, [r3, r4]
	STR	r5, [r2, r4]
	BHI	0b
#if USGE_CLIPMIXDOWN
1:	MOV	r3, r2                                 @ Patch the 'jump to clipper' opcodes
	ADD	r3, #0x04 + OFFSET_OF_BNE_FROM_BLOCK_MERGE
# if USGE_STEREOMIX
	MOV	r1, #0x04
# else
	MOV	r1, #0x02
# endif
10:	LDR	r4, [r3]
	SUB	r4, r3
	ASR	r4, #0x02
	MOV	r5, #0x1A+1
	LSL	r5, #0x18
	ADD	r4, r5
	STR	r4, [r3]
	ADD	r3, #STRIDE_BETWEEN_BLOCK_MERGE
	SUB	r1, #0x01
	BNE	10b
#endif
2:	ADD	r2, #.LLoadMixerOpcodes_MergeStoreLoop_RetryPatch - .LLoadMixerOpcodes_MergeStoreLoop
#if USE_BUFFERED_MIXER
# if USGE_STEREOMIX
	MOV	r1, #0x0C
# else
	MOV	r1, #0x04
# endif
#endif
20:
#if USE_BUFFERED_MIXER
	LDR	r4, [r2, r1]                           @ Patch the 'jump to retry' opcodes
#else
	LDR	r4, [r2]
#endif
	SUB	r4, r2
#if USE_BUFFERED_MIXER
	SUB	r4, r1
#endif
	ASR	r4, #0x02
	MOV	r5, #0xEA+1
	LSL	r5, #0x18
	ADD	r4, r5
#if USE_BUFFERED_MIXER
	STR	r4, [r2, r1]
# if USGE_STEREOMIX
	SUB	r1, #0x0C
# else
	SUB	r1, #0x04
# endif
	BCS	20b
#else
	STR	r4, [r2]
#endif

.LLoadMixer_Exit:
	POP	{r4-r7}
	BX	lr

ASM_MODE_ARM
.LLoadMixer_ADR_Opcode:
	SUB	fp, pc, #0x00

/************************************************/
ASM_MODE_ARM
/************************************************/

.LLoadMixerOpcodes_MixVoice:
	MixLoop_BlockMixVoice

.LLoadMixerOpcodes_MergeStoreLoop:
#if USGE_CLIPMIXDOWN
	LDR	r9, .LLoadMixerOpcodes_ClipConstant
#endif
	MixLoop_BlockMerge r0, r0, r1                  @ Merge all samples -> r0,r1,r2,r3
.LLoadMixerOpcodes_ClipReturn_r0:
	MixLoop_BlockMerge r1, r2, r3
.LLoadMixerOpcodes_ClipReturn_r1:
#if USGE_STEREOMIX
	MixLoop_BlockMerge r2, r4, r5
.LLoadMixerOpcodes_ClipReturn_r2:
	MixLoop_BlockMerge r3, r6, r7
.LLoadMixerOpcodes_ClipReturn_r3:
#endif
.LLoadMixerOpcodes_MergeSamples:
#if USGE_STEREOMIX
	LDMFD	sp!, {sl,fp}                           @ BufL -> sl, BufR -> fp
	STMIA	sl!, {r0,r1}                           @ Store Sample0..7 (left)
	STMIA	fp!, {r2,r3}                           @ Store Sample0..7 (right)
	STMFD	sp!, {sl,fp}                           @ Store updated {BufL,BufR}
#else
	STMIA	r4!, {r0-r1}                           @ Store Sample0..7
#endif
	ADDS	r8, r8, #0x01<<25                      @ --nLoopsRem?
.LLoadMixerOpcodes_MergeStoreLoop_JumpPatch:           @ <- Self modifying jump to first voice to mix
	BCC	.
.LLoadMixerOpcodes_MergeStoreLoop_RetryPatch:          @ <- Needs to be patched relative to the mixer area
	.word	.LMixer_Retry - 0x08
#if USE_BUFFERED_MIXER
# if USGE_STEREOMIX
	NOP	                                       @ <- These 2/3 instructions are here for when we need to
	NOP	                                       @    LDR/LDMIA/STR from the mixing buffer on the last batch
# endif
	.word	.LMixer_Retry - 0x08
#endif
.LLoadMixerOpcodes_ClipConstant:
#if USGE_CLIPMIXDOWN
	.word	0x01010101
#endif
.LLoadMixerOpcodes_MergeStoreLoop_End:

.LLoadMixerOpcodes_StoreBufferedSamples:
#if USE_BUFFERED_MIXER
	ADDS	r8, r8, #0x01<<25                      @ --nLoopsRem?
# if USGE_STEREOMIX
	LDR	ip, [sp, #0x18]                        @ Store updated samples back to buffer
	STMIA	ip!, {r0-r7}
	STR	ip, [sp, #0x18]
# else
	STMIA	r5!, {r0-r3}
# endif
.LLoadMixerOpcodes_StoreBufferedSamples_JumpPatch:     @ <- Self modifying jump to first voice to mix
# if USGE_STEREOMIX
	LDMCCIA	ip, {r0-r7}                            @    * We might need a LDMIA before the jump, though!
# else
	LDMCCIA	r5, {r0-r3}
# endif
	BCC	.
.LLoadMixerOpcodes_StoreBufferedSamples_RetryPatch:    @ <- Needs to be patched relative to the mixer area
	.word	.LMixer_Retry - 0x08
#endif
.LLoadMixerOpcodes_StoreBufferedSamples_End:

.LLoadMixerOpcodes_MergeStoreWithBuffer:
#if USE_BUFFERED_MIXER
# if USGE_STEREOMIX
	LDRCC	ip, [sp, #0x18]
	LDMCCIA	ip!, {r0-r7}
	STRCC	ip, [sp, #0x18]
# else
	LDMCCIA	r5!, {r0-r3}
# endif
#endif

ASM_FUNC_END(uSGE_Driver_LoadMixer)

/************************************************/

@ r4: &DstBufferL[]
@ r5: &DstBufferR[] (with USGE_STEREOMIX)
@ r6:  N
@ r7:  nActiveVox
@ r8: &VoxTable[] (points past the last entry)
@ r9:  SubdivLevel (with USGE_VOLSUBDIV_RATIO)
@ sl:
@ fp:
@ ip:
@ lr:
@ With USE_BUFFERED_MIXER:
@  r5:     &MixBuffer[] (without USGE_STEREOMIX)
@  sp+00h:  HaveBufferedChunk | VoxOffs<<1 | -nTotalVoxRem<<16
@  sp+04h: &MixBuffer[] (with USGE_STEREOMIX)

ASM_FUNC_GLOBAL(uSGE_Driver_Mixer)
ASM_FUNC_BEG   (uSGE_Driver_Mixer, ASM_FUNCSECT_IWRAM;ASM_MODE_ARM)

uSGE_Driver_Mixer:
	ADR	ip, .LMixer_VoxLoopTable - 0x08*1
	ADD	ip, ip, r7, lsl #0x03
	LDMIA	ip, {sl,fp}                            @ `B .LMixLoop_BlockMixVoiceX` -> sl, &BlockLoopPtr -> fp
0:	SUB	r7, r7, r6, lsl #0x18-3                @ nActiveVox | -nTotalLoopsRem<<24 (=N/M)
#if USGE_VOLSUBDIV
# if USGE_VOLSUBDIV_RATIO
	SUB	r3, r6, #0x01                          @ [nLoops = nLoopsPerSubdiv(=Ceiling[N/M/SUBDIV]) -> r3]
	MOV	r3, r3, lsr r9
	MOV	r3, r3, lsr #0x03
	ADD	r3, r3, #0x01
	LDR	ip, .LMixer_SubdivShiftPatchOpcode     @ Patch the instruction that updates the volume
	ADR	lr, .LMixer_SubdivShiftPatch
	SUB	ip, ip, r9, lsl #0x07
	STR	ip, [lr]
# else
	ADD	r3, r6, #(1 << (3+USGE_VOLSUBDIV))-1
	MOV	r3, r3, lsr #(3+USGE_VOLSUBDIV)
# endif
	ORR	r7, r7, r3, lsl #0x08                  @            | nLoopsPerSubdiv<<8
	ORR	r7, r7, r3, lsl #0x10                  @            | nSubdivLoopsRem<<16
	MOV	r6, r3, lsl #0x03                      @ N = nLoopsPerSubdiv*M
#else
	MOV	r3, r6, lsr #0x03                      @ nLoops = N/M
#endif
	SUB	r3, r3, r7, lsl #0x18                  @ nLoops | -nVoxRem<<24 -> r3
	ADD	r9, fp, #OFFSET_OF_LDRSB_FROM_START

.LMixer_PatchTargetBuffer:
#if USE_BUFFERED_MIXER
	LDR	ip, [sp, #0x00]                        @ Mixing the first batch?
	CMN	ip, #MAX_VOICES_PER_CHUNK<<16
	TST	ip, #0x01
# if USGE_STEREOMIX
	LDREQ	r0, .LMixer_InvocationPatchOpcode      @  Y: Skip loading from buffer
	STREQ	r0, .LMixer_InvocationPatch
	ADRNE	r0, .LMixer_InvocationPatchLoadOpcodes @  N: Load from buffer before invoking mixer
	ADRNE	r1, .LMixer_InvocationPatch
	LDMNEIA	r0, {r0,r2,lr}
	BICCC	r2, r2, #0x01<<21                      @     Skip writeback when we will store back to the buffer
	STMNEIA	r1, {r0,r2,lr}
# else
	LDREQ	r0, .LMixer_InvocationPatchOpcode      @  Y: Skip loading from buffer
	LDRNE	r1, .LMixer_InvocationPatchLoadOpcodes @  N: Load from buffer before invoking mixer
	BICCC	r1, r1, #0x01<<21
	STREQ	r0, .LMixer_InvocationPatch
	STRNE	r1, .LMixer_InvocationPatch
# endif
	LDRCS	r0, =.LLoadMixerOpcodes_MergeStoreLoop @ Select overlay
	LDRCC	r0, =.LLoadMixerOpcodes_StoreBufferedSamples
#endif

.LMixer_LoadOverlay:
	LDR	r2, =.LMixerArea_StoreArea
#if USE_BUFFERED_MIXER
1:	LDR	r1, =.LLoadMixerOpcodes_StoreBufferedSamples_End - .LLoadMixerOpcodes_StoreBufferedSamples
10:	SUBS	r1, r1, #0x04
	LDR	lr, [r0, r1]                           @ * Note that we only copy the smaller of the two overlay
	STR	lr, [r2, r1]                           @   sizes, since we only ever switch between the two of them.
	BHI	10b
2:	CMN	ip, #MAX_VOICES_PER_CHUNK<<16          @ C = LastChunk, Z = HaveBufferedChunk?
	TST	ip, #0x01
	BCS	21f
20:	LDR	lr, [r2, #.LLoadMixerOpcodes_StoreBufferedSamples_RetryPatch - .LLoadMixerOpcodes_StoreBufferedSamples]!
	SUB	lr, lr, r2                             @ Patch the 'jump to retry' opcode, and the 'loop over blocks' opcode
	MOV	lr, lr, asr #0x02
	ADD	lr, lr, #(0xEA+1)<<24
	STR	lr, [r2]
	SUB	sl, sl, #((.LLoadMixerOpcodes_StoreBufferedSamples_JumpPatch - .LLoadMixerOpcodes_StoreBufferedSamples) - \
		          (.LLoadMixerOpcodes_MergeStoreLoop_JumpPatch       - .LLoadMixerOpcodes_MergeStoreLoop)) / 0x04
	STREQ	sl, [r2, #.LLoadMixerOpcodes_StoreBufferedSamples_JumpPatch  - .LLoadMixerOpcodes_StoreBufferedSamples_RetryPatch]
	SUBNE	sl, sl, #0x04/0x04                     @ * When we have a prior buffer, insert a LDMIA before the jump!
	LDRNE	lr, [r0, #.LLoadMixerOpcodes_StoreBufferedSamples_JumpPatch  - .LLoadMixerOpcodes_StoreBufferedSamples]
	STRNE	lr, [r2, #.LLoadMixerOpcodes_StoreBufferedSamples_JumpPatch  - .LLoadMixerOpcodes_StoreBufferedSamples_RetryPatch]!
	STRNE	sl, [r2, #0x04]
	B	3f
21:
# if USGE_STEREOMIX
	@ When mixing the last chunk, and we had a prior chunk
	@ in the mix buffer, insert a [LDR/]LDMIA[/STR] sequence
	@ to load the samples for the next iteration
	ADDNE	r0, r0, #.LLoadMixerOpcodes_MergeStoreWithBuffer     - .LLoadMixerOpcodes_MergeStoreLoop
	LDMNEIA	r0, {r0-r1,lr}
	ADDNE	r2, r2, #.LLoadMixerOpcodes_MergeStoreLoop_JumpPatch - .LLoadMixerOpcodes_MergeStoreLoop
	STMNEIA	r2!, {r0-r1,lr}
	SUBNE	sl, sl, #0x0C/0x04
	ADDEQ	r2, r2, #.LLoadMixerOpcodes_MergeStoreLoop_JumpPatch - .LLoadMixerOpcodes_MergeStoreLoop
	STR	sl, [r2]
# else
	LDRNE	r0, [r0, #.LLoadMixerOpcodes_MergeStoreWithBuffer     - .LLoadMixerOpcodes_MergeStoreLoop]
	STRNE	r0, [r2, #.LLoadMixerOpcodes_MergeStoreLoop_JumpPatch - .LLoadMixerOpcodes_MergeStoreLoop]
	SUBNE	sl, sl, #0x04/0x04
	ADDNE	r2, r2, #0x04
	STR	sl, [r2, #.LLoadMixerOpcodes_MergeStoreLoop_JumpPatch - .LLoadMixerOpcodes_MergeStoreLoop]
# endif
3:
#else
	STR	sl, [r2, #.LLoadMixerOpcodes_MergeStoreLoop_JumpPatch - .LLoadMixerOpcodes_MergeStoreLoop]
#endif

.LMixer_PatchFirstVoiceWithMUL:
	MOV	sl, r8                                 @ Save &VoxTable[] -> sl
#if USE_BUFFERED_MIXER
	TST	ip, #0x01                              @ If we are not mixing the first batch, patch first voice with MLA
	BNE	.LMixer_PatchVoicesWithMLA
#endif
	ADD	ip, r9, #OFFSET_OF_MLANE_FROM_LDRSB
#if USGE_STEREOMIX
	ADR	lr, .LMixer_PatchOpcodes + 0x08*0
	LDMIA	lr!, {r0,r1}                           @ `MUL r0, ip, r9` -> r0, `MUL r4, lr, r9` -> r1
0:	STMIA	ip, {r0,r1}
	ADD	ip, ip, #STRIDE_BETWEEN_SAMPLE_PAIRS
	ADD	r0, r0, #0x01<<16                      @ Step to next sample registers
	ADD	r1, r1, #0x01<<16
	ADDS	r6, r6, #0x01<<(32-2)                  @ Count up four register pairs (=8 samples)
	BCC	0b
#else
	LDR	r0, .LMixer_PatchOpcodes + 0x04*0
0:	STR	r0, [ip], #STRIDE_BETWEEN_SAMPLE_PAIRS
	ADD	r0, r0, #0x01<<16                      @ Step to next sample register
	ADDS	r6, r6, #0x01<<(32-2)                  @ Count up four registers (=8 samples)
	BCC	0b
#endif
1:	B	.LMixer_PatchVoiceOffsets

.LMixer_PatchVoicesWithMLA:
	ADD	ip, r9, #OFFSET_OF_MLANE_FROM_LDRSB
#if USGE_STEREOMIX
	ADR	lr, .LMixer_PatchOpcodes + 0x08*1
	LDMIA	lr!, {r0,r1}                           @ `MLANE r0, ip, r9, r0` -> r0, `MLANE r4, lr, r9, r4` -> r1
0:	STMIA	ip, {r0,r1}
	ADD	ip, ip, #STRIDE_BETWEEN_SAMPLE_PAIRS
	ADD	r0, r0, #(1<<12) | (1<<16)             @ Step to next sample registers
	ADD	r1, r1, #(1<<12) | (1<<16)
	ADDS	r6, r6, #0x01<<(32-2)                  @ Count up four register pairs (=8 samples)
	BCC	0b
#else
	LDR	r0, .LMixer_PatchOpcodes + 0x04*1
0:	STR	r0, [ip], #STRIDE_BETWEEN_SAMPLE_PAIRS
	ADD	r0, r0, #(1<<12) | (1<<16)             @ Step to next sample registers
	ADDS	r6, r6, #0x01<<(32-2)                  @ Count up four registers (=8 samples)
	BCC	0b
#endif

@ Instruction order:
@ LDRSB Samp0, [sl, #0]
@ LDRSB Samp2, [sl, #Delta*2]
@ LDRSB Samp1, [sl, #Delta]
@ LDRSB Samp3, [sl, #Delta*3]!
@ LDRSB Samp4, [sl, #Delta]!
@ LDRSB Samp6, [sl, #Delta*2]
@ LDRSB Samp5, [sl, #Delta]
@ LDRSB Samp7, [sl, #Delta*3]
.LMixer_PatchVoiceOffsets:
	LDR	r0, [r8, #-USGE_VOXTABLE_ENTRY_SIZE]!  @ Rate | Phase<<16 -> r0
	MOV	r1, r0, lsr #(32-USGE_FRACBITS)        @ Phase -> r1
	BIC	r0, r0, r1, lsl #(32-USGE_FRACBITS)    @ Rate -> r0
#if USGE_STEREOMIX
	LDR	r2, [r8, #0x10]                        @ SampRem -> r2
#else
	LDR	r2, [r8, #0x0C]
#endif
	MLA	lr, r0, r6, r1                         @ nSampToRead = Rate*N + Phase -> lr
	CMP	r2, lr, lsr #USGE_FRACBITS             @ SampRem < nSampToRead?
	BLLT	.LMixer_ClipLoopCount
	MOV	r2, r0, lsr #(USGE_FRACBITS-3)         @ Update ADC immediate for Rate step
	STRB	r2, [r9, #OFFSET_OF_ADC_FROM_START-OFFSET_OF_LDRSB_FROM_START]
	MOV	r1, #0x00                              @ Start with initial Phase=0 to ensure we never over-step, as this sounds awful
	MOV	r2, #0xD0                              @ Low byte of `LDRSB Rd, [Rm, #IMM]!` opcode, at offset 0
1:	ADDS	r1, r1, r0, lsl #(32-USGE_FRACBITS)    @ Phase += Rate?
	ADC	ip, r2, r0, lsr #USGE_FRACBITS         @ CurOffs += (int)Rate + C
	STRB	ip, [r9, #1*STRIDE_BETWEEN_SAMPLE_PAIRS + 0x00]
	ADDS	r1, r1, r0, lsl #(32-USGE_FRACBITS)
	ADC	ip, ip, r0, lsr #USGE_FRACBITS
	STRB	ip, [r9, #0*STRIDE_BETWEEN_SAMPLE_PAIRS + 0x04]
	ADDS	r1, r1, r0, lsl #(32-USGE_FRACBITS)
	ADC	ip, ip, r0, lsr #USGE_FRACBITS
	STRB	ip, [r9, #1*STRIDE_BETWEEN_SAMPLE_PAIRS + 0x04]
	ADDS	r1, r1, r0, lsl #(32-USGE_FRACBITS)
	ADC	ip, r2, r0, lsr #USGE_FRACBITS
	STRB	ip, [r9, #2*STRIDE_BETWEEN_SAMPLE_PAIRS + 0x00]
	ADDS	r1, r1, r0, lsl #(32-USGE_FRACBITS)
	ADC	ip, r2, r0, lsr #USGE_FRACBITS
	STRB	ip, [r9, #3*STRIDE_BETWEEN_SAMPLE_PAIRS + 0x00]
	ADDS	r1, r1, r0, lsl #(32-USGE_FRACBITS)
	ADC	ip, ip, r0, lsr #USGE_FRACBITS
	STRB	ip, [r9, #2*STRIDE_BETWEEN_SAMPLE_PAIRS + 0x04]
	ADDS	r1, r1, r0, lsl #(32-USGE_FRACBITS)
	ADC	ip, ip, r0, lsr #USGE_FRACBITS
	STRB	ip, [r9, #3*STRIDE_BETWEEN_SAMPLE_PAIRS + 0x04]
2:	ADD	r9, r9, #STRIDE_BETWEEN_VOICES         @ Move to next voice
	ADDS	r3, r3, #0x01<<24                      @ --nVoxRem?
	BCC	.LMixer_PatchVoicesWithMLA

.LMixer_AdvanceSampsRemAndMix:
	ADD	r7, r7, r3, lsl #0x18                  @ nTotalLoopsRem -= nLoops
#if USGE_VOLSUBDIV
	SUB	r7, r7, r3, lsl #0x10                  @ nSubdivLoopsRem -= nLoops
#endif
	AND	ip, r7, #0xFF                          @ nVoxRem = nActiveVox -> ip
	MOV	r8, sl
0:	LDR	r0, [r8, #-USGE_VOXTABLE_ENTRY_SIZE]!  @ Rate | Phase<<16 -> r0
	MOV	r1, r0, lsr #(32-USGE_FRACBITS)        @ Phase -> r1
	BIC	r0, r0, r1, lsl #(32-USGE_FRACBITS)    @ Rate -> r0
#if USGE_STEREOMIX
	LDR	r2, [r8, #0x10]                        @ SampRem -> r2
#else
	LDR	r2, [r8, #0x0C]
#endif
	MLA	lr, r0, r6, r1                         @ nSampToRead = Rate*N + Phase -> lr
	SUB	r2, r2, lr, lsr #USGE_FRACBITS         @ SampRem -= nSampToRead?
#if USGE_STEREOMIX
	STR	r2, [r8, #0x10]
#else
	STR	r2, [r8, #0x0C]
#endif
	SUBS	ip, ip, #0x01                          @ --nVoxRem?
	BNE	0b
0:	MOV	r8, #0xFF                              @ 00FF00FFh | -nLoops<<25 -> r8
	ORR	r8, r8, r8, lsl #0x10
	SUB	r8, r8, r3, lsl #0x19
#if USGE_STEREOMIX
	STMFD	sp!, {r4,r5,r7,sl,fp}                  @ Push registers and invoke mixer
#else
	STMFD	sp!, {sl,fp}
#endif

.LMixer_InvocationPatch:
#if USE_BUFFERED_MIXER
	BX	fp                                     @ <- Replaced by LDMIA (or LDR/LDMIA/STR) as needed
# if USGE_STEREOMIX
	NOP
	NOP
# endif
#endif
.LMixer_InvocationPatchOpcode:
	BX	fp                                     @ <- Used when mixing chunk 2 and onward (never modified)

.LMixer_PatchOpcodes:
	MUL	r0, r9, ip                             @ Mix first voice (left)
#if USGE_STEREOMIX
	MUL	r4, r9, lr                             @ Mix first voice (right)
#endif
	MLANE	r0, r9, ip, r0                         @ Mix other voice (left)
#if USGE_STEREOMIX
	MLANE	r4, r9, lr, r4                         @ Mix other voice (right)
#endif

.LMixer_VoxLoopTable:
	CREATE_VOXLOOPTABLE

.LMixer_SubdivShiftPatchOpcode:
#if (USGE_VOLSUBDIV && USGE_VOLSUBDIV_RATIO)
	ADD	r2, r2, lr, lsl #0x08                  @ VolCur += VolStep/SUBDIV
#endif

.LMixer_InvocationPatchLoadOpcodes:
#if USE_BUFFERED_MIXER
# if USGE_STEREOMIX
	LDR	ip, [sp, #0x18]                        @ Load buffered samples
	LDMIA	ip!, {r0-r7}
	STR	ip, [sp, #0x18]
# else
	LDMIA	r5!, {r0-r3}
# endif
#endif

ASM_LITPOOL

/************************************************/

.LMixer_Retry:
#if USGE_STEREOMIX
	LDMFD	sp!, {r4,r5,r7,r8,fp}
#else
	LDMFD	sp!, {r8,fp}
#endif
	TST	r7, #0xFF<<24                          @ Have any loops remaining?
	BEQ	.LExit

.LMixer_SetNextN:
#if USGE_VOLSUBDIV
	MOV	ip, #0xFF
	ANDS	r3, ip, r7, lsr #0x10                  @ nLoops = nSubdivLoopsRem?
	ANDEQ	r3, ip, r7, lsr #0x08                  @  nSubdivLoopsRem == 0: nLoops = nLoopsPerSubdiv
	ADDS	ip, r7, r3, lsl #0x18                  @ nLoops = MIN(nLoops, nTotalLoopsRem)
	SUBCS	r3, r3, ip, lsr #0x18
#else
	MOV	r3, r7, lsr #0x18                      @ nLoops = nTotalLoopsRem
	RSB	r3, r3, #0x0100
#endif
	MOV	r6, r3, lsl #0x03                      @ N = nLoops*M -> r6

.LMixer_RescanVoices:
	AND	ip, r7, #0xFF
	SUB	r3, r3, ip, lsl #0x08                  @ nVoxRem = nActiveVox
	MOV	sl, r8
1:	LDR	r0, [r8, #-USGE_VOXTABLE_ENTRY_SIZE]!  @ Rate | Phase<<16 -> r0
	MOV	r1, r0, lsr #(32-USGE_FRACBITS)        @ Phase -> r1
	BIC	r0, r0, r1, lsl #(32-USGE_FRACBITS)    @ Rate -> r0
#if USGE_STEREOMIX
	LDR	r2, [r8, #0x10]                        @ SampRem -> r2
#else
	LDR	r2, [r8, #0x0C]
#endif
	CMP	r2, #0x00                              @ SampRem <= 0? Need to loop
	BLE	.LMixer_LoopSample
.LMixer_LoopSample_Return:
	MLA	lr, r0, r6, r1                         @ nSampToRead = Rate*N + Phase -> lr
	CMP	r2, lr, lsr #USGE_FRACBITS             @ SampRem < nSampToRead?
	BLLT	.LMixer_ClipLoopCount
#if USGE_VOLSUBDIV
	TST	r7, #0xFF<<16                          @ Next subdivision?
	BNE	2f
# if USGE_STEREOMIX
	ADD	r0, r8, #0x18
# else
	ADD	r0, r8, #0x14
# endif
	LDMIA	r0, {r2,lr}                            @ VolCur -> r2, VolStep -> lr
.LMixer_SubdivShiftPatch:
	ADD	r2, r2, lr, lsl #0x08-USGE_VOLSUBDIV   @ VolCur += VolStep/SUBDIV
# if USGE_STEREOMIX
	STR	r2, [r0], #0x08 - 0x18
	MOV	lr, r2, lsr #0x18                      @ VolR -> lr
	MOV	r2, r2, lsr #0x08                      @ VolL -> r2
	AND	r2, r2, #0xFF
	STMIA	r0, {r2,lr}
# else
	STR	r2, [r0], #0x08 - 0x14
	MOV	r2, r2, lsr #0x08                      @ Volume -> r2
	STR	r2, [r0]
# endif
#endif
2:	ADDS	r3, r3, #0x01<<8                       @ --nVoxRem?
	BCC	1b

.LMixer_Restart:
#if USGE_VOLSUBDIV
	TST	r7, #0xFF<<16                          @ Next subdivision?
	ANDEQ	lr, r7, #0xFF<<8                       @  Y: nSubdivLoopsRem = nLoopsPerSubdiv
	ORREQ	r7, r7, lr, lsl #(16-8)
#endif
	B	.LMixer_AdvanceSampsRemAndMix

ASM_LITPOOL

.LExit:
#if USE_BUFFERED_MIXER
# if USGE_STEREOMIX
	LDR	r0, [sp], #0x08
# else
	LDR	r0, [sp], #0x04
# endif
	ORR	r0, r0, #0x01                          @ HaveBufferedChunk = 1
	ADDS	r0, r0, #MAX_VOICES_PER_CHUNK<<16      @ nTotalVoxRem -= VOICES_PER_CHUNK?
	LDRCC	r1, =uSGE_Driver_Update_NextChunk+1    @  Do another chunk as needed
	BXCC	r1
#endif
	LDMFD	sp!, {r4-fp,lr}
	BX	lr

/************************************************/
//! Mixer Edge Cases
/************************************************/

@ Clip number of loops to run
@ r0: Rate
@ r1: Phase
@ r2: SampRem
@ r3: nLoops | xx<<24 (nLoops will be overwritten)
@ r4:
@ r5:
@ r6: N               (will be stored to)

.LMixer_ClipLoopCount:
	MOV	r6, #0x01<<3                           @ nLoopsThisRun = Ceiling[((SampRem << BITS) - Phase) / (Rate*M)]
	ADD	ip, r1, #0x01
	RSB	ip, ip, r2, lsl #USGE_FRACBITS
.irp x, 7,6,5,4,3,2,1,0
	SUBS	ip, ip, r0, lsl #0x03 + \x
	ADDCC	ip, ip, r0, lsl #0x03 + \x
	ADDCS	r6, r6, #(1<<3) << \x
.endr
0:	BIC	r3, r3, #0xFF
	ORR	r3, r3, r6, lsr #0x03
	BX	lr

.LMixer_LoopSample:
	LDR	ip, [r8, #0x04]                        @ DataPtr -> ip
#if USGE_STEREOMIX
	LDR	lr, [r8, #0x14]                        @ LoopSize -> lr
#else
	LDR	lr, [r8, #0x10]
#endif
	CMP	lr, #0x00                              @ Have a loop?
	BEQ	2f
0:	SUB	ip, ip, lr                             @  Y: DataPtr -= LoopSize
	ADDS	r2, r2, lr                             @     SampRem += LoopSize?
	BLE	0b
1:	STR	ip, [r8, #0x04]
#if USGE_STEREOMIX
	STR	r2, [r8, #0x10]
#else
	STR	r2, [r8, #0x0C]
#endif
	B	.LMixer_LoopSample_Return
2:	LDR	ip, =uSGE_Driver_SilentLoop            @  N: Loop silence
	MOV	r2, #SILENT_LOOP_SIZE
	B	1b

ASM_LITPOOL

/************************************************/
#if USGE_CLIPMIXDOWN
/************************************************/

@ Clip samples in registers r0..r3

.LMixLoop_BlockLoop_Clip_r0:
	MixLoop_BlockClip r0
	B	.LMixerArea_StoreArea + (.LLoadMixerOpcodes_ClipReturn_r0 - .LLoadMixerOpcodes_MergeStoreLoop)

.LMixLoop_BlockLoop_Clip_r1:
	MixLoop_BlockClip r1
	B	.LMixerArea_StoreArea + (.LLoadMixerOpcodes_ClipReturn_r1 - .LLoadMixerOpcodes_MergeStoreLoop)

#if USGE_STEREOMIX

.LMixLoop_BlockLoop_Clip_r2:
	MixLoop_BlockClip r2
	B	.LMixerArea_StoreArea + (.LLoadMixerOpcodes_ClipReturn_r2 - .LLoadMixerOpcodes_MergeStoreLoop)

.LMixLoop_BlockLoop_Clip_r3:
	MixLoop_BlockClip r3
	B	.LMixerArea_StoreArea + (.LLoadMixerOpcodes_ClipReturn_r3 - .LLoadMixerOpcodes_MergeStoreLoop)

#endif

/************************************************/
#endif
/************************************************/

ASM_FUNC_END(uSGE_Driver_Mixer)

/************************************************/

ASM_DATA_GLOBAL(uSGE_Driver_VoxTable)
ASM_DATA_BEG   (uSGE_Driver_VoxTable, ASM_DATASECT_BSS;ASM_ALIGN(4))

uSGE_Driver_VoxTable:
	.space MAX_VOICES_PER_CHUNK * USGE_VOXTABLE_ENTRY_SIZE

ASM_DATA_END(uSGE_Driver_VoxTable)

/************************************************/

ASM_DATA_BEG(uSGE_Driver_MixerArea, ASM_DATASECT_BSS;ASM_ALIGN(4))

uSGE_Driver_MixerArea:
.LMixerArea_VoxArea:
	.space (MAX_VOICES_PER_CHUNK * STRIDE_BETWEEN_VOICES)
.LMixerArea_StoreArea:
	.space (.LLoadMixerOpcodes_MergeStoreLoop_End - .LLoadMixerOpcodes_MergeStoreLoop)

ASM_DATA_END(uSGE_Driver_MixerArea)

/************************************************/

ASM_DATA_BEG(uSGE_Driver_SilentLoop, ASM_DATASECT_RODATA;ASM_ALIGN(1))

uSGE_Driver_SilentLoop:
	.fill (SILENT_LOOP_SIZE + 32) @ Need 8*MAX_RATE samples of padding

ASM_DATA_END(uSGE_Driver_SilentLoop)

/************************************************/
//! EOF
/************************************************/
