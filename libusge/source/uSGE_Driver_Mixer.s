/************************************************/
#include "uSGE_ASM.h"
#include "uSGE_Config.h"
#include "uSGE_Driver_MixerMacros.inc"
/************************************************/

//! Generate warning for large voice tables
#ifdef USGE_LARGE_VOXTABLE
# warning "USGE_MAX_VOICES exceeds fast mixer limits; performance will be degraded."
#endif

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

ASM_FUNC_GLOBAL(uSGE_Driver_Mixer)
ASM_FUNC_BEG   (uSGE_Driver_Mixer, ASM_FUNCSECT_IWRAM;ASM_MODE_ARM)

uSGE_Driver_Mixer:
	ADR	ip, .LMixer_VoxLoopTable - 0x08*1
	ADD	ip, ip, r7, lsl #0x03
	LDMIA	ip, {sl,fp}                            @ `B .LMixLoop_BlockMixVoiceX` -> sl, &BlockLoopPtr -> fp
#if ((USGE_STEREOMIX && USGE_MAX_VOICES > 25) || (!USGE_STEREOMIX && USGE_MAX_VOICES > 30))
	LDR	r3, =.LMixLoop_LoopOpcode
	STR	sl, [r3]
#else
	STR	sl, .LMixLoop_LoopOpcode
#endif
	MOV	sl, r8
0:	SUB	r7, r7, r6, lsl #0x18-3                @ nActiveVox | -nTotalLoopsRem<<24 (=N/M)
#if USGE_VOLSUBDIV
# if USGE_VOLSUBDIV_RATIO
	SUB	r3, r6, #0x01                          @ [nLoops = nLoopsPerSubdiv(=Ceiling[N/M/SUBDIV]) -> r3]
	MOV	r3, r3, lsr r9
	MOV	r3, r3, lsr #0x03
	ADD	r3, r3, #0x01
	LDR	ip, .LMixer_SubdivShiftPatchOpcode     @ Patch the instruction that updates the volume
	LDR	lr, =.LMixer_SubdivShiftPatch
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

.LMixer_PatchFirstVoiceMUL:
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

.LMixer_PatchOtherVoiceMLA:
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
	MOV	r1, r1, lsl #(32-USGE_FRACBITS)        @ Shift Phase to uppermost bits -> r1
	MOV	r2, #0xD0                              @ Low byte of `LDRSB Rd, [Rm, #IMM]!` opcode, at offset 0
1:	ADDS	ip, r1, r0, lsl #(32-USGE_FRACBITS)    @ Phase += Rate?
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
	ADDS	ip, r1, r0, lsl #(32-USGE_FRACBITS)
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
	BCC	.LMixer_PatchOtherVoiceMLA

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
	BX	fp

.LMixer_PatchOpcodes:
#if USGE_STEREOMIX
	MUL	r0, r9, ip                             @ Mix first voice (left)
	MUL	r4, r9, lr                             @ Mix first voice (right)
	MLANE	r0, r9, ip, r0                         @ Mix other voice (left)
	MLANE	r4, r9, lr, r4                         @ Mix other voice (right)
#else
	MUL	r0, ip, r9                             @ Mix first voice
	MLANE	r0, ip, r9, r0                         @ Mix other voice
#endif

.LMixer_VoxLoopTable:
	CREATE_VOXLOOPTABLE

.LMixer_SubdivShiftPatchOpcode:
#if (USGE_VOLSUBDIV && USGE_VOLSUBDIV_RATIO)
	ADD	r2, r2, lr, lsl #0x08                  @ VolCur += VolStep/SUBDIV
#endif

ASM_LITPOOL

/************************************************/

#ifdef SMALL_VOXTABLE
ASM_DATA_GLOBAL(uSGE_Driver_VoxTable)
uSGE_Driver_VoxTable:
	.space USGE_MAX_VOICES * USGE_VOXTABLE_ENTRY_SIZE
#else
.LMixLoop_VoiceTablePtrs:
	CREATE_VOXTABLEPTRS
#endif

.LMixLoop_BlockLoop:
	MixLoop_BlockMixVoices
#if USGE_CLIPMIXDOWN
	LDR	r9, =0x01010101
#endif
	MixLoop_BlockMerge r0, r0, r1                  @ Merge all samples -> r0,r1,r2,r3
.LMixLoop_BlockLoop_ClipReturn_r0:
	MixLoop_BlockMerge r1, r2, r3
.LMixLoop_BlockLoop_ClipReturn_r1:
#if USGE_STEREOMIX
	MixLoop_BlockMerge r2, r4, r5
.LMixLoop_BlockLoop_ClipReturn_r2:
	MixLoop_BlockMerge r3, r6, r7
.LMixLoop_BlockLoop_ClipReturn_r3:
#endif
#if USGE_STEREOMIX
	LDMFD	sp!, {sl,fp}                           @ BufL -> sl, BufR -> fp
	STMIA	sl!, {r0,r1}                           @ Store Sample0..7 (left)
	STMIA	fp!, {r2,r3}                           @ Store Sample0..7 (right)
	STMFD	sp!, {sl,fp}                           @ Store updated {BufL,BufR}
#else
	STMIA	r4!, {r0-r1}                           @ Store Sample0..7
#endif
	ADDS	r8, r8, #0x01<<25                      @ --nLoopsRem?
.LMixLoop_LoopOpcode:
	BCC	.LMixLoop_BlockLoop                    @ <- Self modifying

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
#if USGE_VOLSUBDIV
	TST	r7, #0xFF<<16                          @ Next subdivision?
	ANDEQ	lr, r7, #0xFF<<8                       @  Y: nSubdivLoopsRem = nLoopsPerSubdiv
	ORREQ	r7, r7, lr, lsl #(16-8)
#endif

.LMixer_Restart:
	B	.LMixer_AdvanceSampsRemAndMix

ASM_LITPOOL

.LExit:
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
0:	SUB	ip, ip, lr                             @ DataPtr -= LoopSize
	ADDS	r2, r2, lr                             @ SampRem += LoopSize?
	BLE	0b
1:	STR	ip, [r8, #0x04]
#if USGE_STEREOMIX
	STR	r2, [r8, #0x10]
#else
	STR	r2, [r8, #0x0C]
#endif
	B	.LMixer_LoopSample_Return

/************************************************/
#if USGE_CLIPMIXDOWN
/************************************************/

@ Clip samples in registers r0..r3

.LMixLoop_BlockLoop_Clip_r0:
	MixLoop_BlockClip r0
	B	.LMixLoop_BlockLoop_ClipReturn_r0

.LMixLoop_BlockLoop_Clip_r1:
	MixLoop_BlockClip r1
	B	.LMixLoop_BlockLoop_ClipReturn_r1

#if USGE_STEREOMIX

.LMixLoop_BlockLoop_Clip_r2:
	MixLoop_BlockClip r2
	B	.LMixLoop_BlockLoop_ClipReturn_r2

.LMixLoop_BlockLoop_Clip_r3:
	MixLoop_BlockClip r3
	B	.LMixLoop_BlockLoop_ClipReturn_r3

#endif

/************************************************/
#endif
/************************************************/

ASM_FUNC_END(uSGE_Driver_Mixer)

/************************************************/
#ifndef SMALL_VOXTABLE
/************************************************/

ASM_DATA_GLOBAL(uSGE_Driver_VoxTable)
ASM_DATA_BEG   (uSGE_Driver_VoxTable, ASM_DATASECT_BSS;ASM_ALIGN(4))

uSGE_Driver_VoxTable:
	.space USGE_MAX_VOICES * USGE_VOXTABLE_ENTRY_SIZE

ASM_DATA_END(uSGE_Driver_VoxTable)

/************************************************/
#endif
/************************************************/
//! EOF
/************************************************/
