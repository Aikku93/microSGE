/************************************************/
#include "uSGE_ASM.h"
#include "uSGE_Config.h"
#include "uSGE.h"
/************************************************/

@ r0: &Driver

ASM_FUNC_GLOBAL(uSGE_Driver_Update)
ASM_FUNC_BEG   (uSGE_Driver_Update, ASM_FUNCSECT_IWRAM;ASM_MODE_ARM)

uSGE_Driver_Update:
	STMFD	sp!, {r4-fp,lr}
	ADR	ip, 1f+1
	BX	ip

ASM_MODE_THUMB
1:	MOV	r4, r0                    @ Driver -> r4
	LDR	r0, [r4, #0x00]           @ State -> r0
	LDR	r1, =USGE_DRIVER_STATE_READY
	SUB	r1, r0                    @ Invalid state?
	BNE	.LExit
0:	LDRH	r5, [r4, #0x0A]           @ N = BufLen -> r5
	PUSH	{r4-r5}                   @ Push {Driver,N}

/************************************************/

.LVoxUpdateLoop_Enter:
	LDR	r0, =uSGE_Driver_VoxTable
#if (USGE_VOLSUBDIV && USGE_VOLSUBDIV_RATIO)
	MOV	r9, r1                    @ SubdivLevel = 0
#endif
	MOV	r8, r0                    @ &VoxTable[] -> r8
	LDRB	r7, [r4, #0x06]           @ &Vox[] -> r4, nActiveVox=0|-nVoxRem<<7 -> r7
	NEG	r7, r7
	LSL	r7, #0x07
	ADD	r4, #USGE_DRIVER_HEADER_SIZE

.LVoxUpdateLoop:
	LDRB	r6, [r4, #0x00]           @ Stat -> r6
	LSL	r0, r6, #(32-7)           @ C=ACTIVE, N=KEYON?
	BCS	uSGE_Driver_VoiceUpdate
	SUB	r7, #0x01                 @  Voice is inactive: --nActiveVox, be cause we do ++nActiveVox next

.LVoxUpdateLoop_Tail:
	ADD	r4, #USGE_VOX_SIZE        @ Move to next voice
	ADD	r7, #0x01 + 0x01<<7       @ ++nActiveVox, --nVoxRem?
	BCC	.LVoxUpdateLoop

/************************************************/

.LMixer_Enter:
	POP	{r5,r6}                   @ Pop {Driver -> r5, N -> r6}
	LDRB	r0, [r5, #0x07]           @ BfIdxW -> r0
	LDRB	r1, [r5, #0x05]           @ BfCnt -> r1
	ADD	r2, r0, #0x01             @ BfIdxW = WRAP(BfIdxW+1) -> r2
0:	SUB	r2, r1
	BCS	0b
0:	ADD	r2, r1
	STRB	r2, [r5, #0x07]
	MUL	r0, r6                    @ BufferOffs = BfIdxW*BufLen -> r0
	ADD	r4, r0                    @ DstBufferL = BufferStart + BufferOffs -> r4
#if USGE_STEREOMIX
	MUL	r1, r6                    @ DstBufferR = DstBufferL + BfCnt*BufLen -> r5
	ADD	r5, r4, r1
#endif
1:	MOV	r1, r7                    @ Did we have any voices?
	BEQ	.LMixer_NoVoices          @  N: Clear buffers
10:	LDR	r0, =uSGE_Driver_Mixer    @  Y: Invoke mixer
	BX	r0

.LMixer_NoVoices:
	MOV	r0, r4                    @ Clear DstBufferL
	@MOV	r1, #0x00
	MOV	r2, r6
	BL	memset
#if USGE_STEREOMIX
	MOV	r0, r5                    @ Clear DstBufferR
	MOV	r1, #0x00
	MOV	r2, r6
	BL	memset
#endif

ASM_ALIGN(4)
.LExit:
	BX	pc
	NOP
ASM_MODE_ARM
	LDMFD	sp!, {r4-fp,lr}
	BX	lr

ASM_FUNC_END(uSGE_Driver_Update)

/************************************************/
//! Voice Update
/************************************************/

@ r4: &Vox
@ r5:
@ r6:  Vox.Stat
@ r7:  nActiveVox | -nVoxRem<<7 (nActiveVox does NOT account for this voice yet)
@ r8: &VoxTable[]
@ r9:  SubdivLevel (with USGE_VOLSUBDIV_RATIO)
@ sp+00h: &Driver
@ sp+04h:  nVoxRem

ASM_FUNC_BEG(uSGE_Driver_VoiceUpdate, ASM_FUNCSECT_IWRAM;ASM_MODE_THUMB)

uSGE_Driver_VoiceUpdate:
	PUSH	{r4,r7}
	BMI	.LVoxUpdate_KeyOn         @ Handle KEYON as needed
	LSL	r0, r6, #(32-5)           @ C=KEYOFF, N=MANUAL_EG?
#if USGE_GENERATE_ENVELOPE
	BMI	.LVoxUpdate_EG_Manual
	BCS	.LVoxUpdate_KeyOff
#endif

.LVoxUpdate_KeyOn_Done:
.LVoxUpdate_KeyOff_Done:

#if USGE_GENERATE_ENVELOPE

.LVoxUpdate_EGUpdate:
	LDR	r1, =uSGE_RecpLUT         @ &RecpLUT[] -> r1
	LSL	r0, r6, #(32-5)           @ C=KEYOFF?
	BCS	.LVoxUpdate_EG_Release    @  * In KEYOFF, we are always in Release phase
	LSL	r2, r6, #0x20-2           @ Invoke correct handler
	LSR	r2, #0x20-2 - 1
	ADR	r3, .LVoxUpdate_EG_JumpTable
	LDRH	r3, [r3, r2]
.LVoxUpdate_EG_JumpOffset:
	ADD	pc, r3

ASM_ALIGN(4)
.LVoxUpdate_EG_JumpTable:
	.hword	.LVoxUpdate_EG_Attack  - .LVoxUpdate_EG_JumpOffset - 0x04 @ -2 instructions for pipelining
	.hword	.LVoxUpdate_EG_Hold    - .LVoxUpdate_EG_JumpOffset - 0x04
	.hword	.LVoxUpdate_EG_Decay   - .LVoxUpdate_EG_JumpOffset - 0x04
	.hword	.LVoxUpdate_EG_Sustain - .LVoxUpdate_EG_JumpOffset - 0x04

.LVoxUpdate_EG_Release:
	LDRB	r0, [r4, #0x07]           @ EGc -> r0
	BL	uSGE_Driver_GetExpDecStep
	LDRH	r1, [r4, #0x0C]           @ EG *= EGc -> r0
	MUL	r0, r1
	LSR	r0, #0x10
	B	.LVoxUpdate_EG_Ready

#endif

.LVoxUpdate_KeyOn:
	SUB	r6, #USGE_VOX_STAT_KEYON  @ Clear KEYON
	STRH	r0, [r4, #0x0A]           @ Vox.Offs = 0
	LDR	r0, [r4, #0x14]           @ Vox.Data = Wav.Data
	ADD	r0, #0x08
	STR	r0, [r4, #0x10]
#if USGE_VOLSUBDIV
	LDRB	r0, [r4, #0x01]           @ Set OldVol = NewVol (ie. as though EG = 1.0)
	STRB	r0, [r4, #0x0E]           @ If we have Attack, we will clear this to 0 later
# if USGE_STEREOMIX
	LDRB	r0, [r4, #0x02]
	STRB	r0, [r4, #0x0F]
# endif
#endif
#if USGE_GENERATE_ENVELOPE
	LSL	r0, r6, #(32-4)           @ Test for MANUAL mode EG
	BCS	.LVoxUpdate_KeyOn_Done
0:	LDRB	r0, [r4, #0x03]           @ Vox.Attack?
	LSL	r1, r0, #0x18
	BNE	.LVoxUpdate_KeyOnWithAttack
0:	ADD	r6, #0x01                 @ Move to Hold phase
	LDRB	r0, [r4, #0x04]           @ Vox.Hold?
	SUB	r1, r0, #0x01             @  Y: EG = 0 | N: EG = 1.0 for Decay
	LSR	r1, #0x10
	BEQ	1f
0:	ADD	r6, #0x01                 @ Move to Decay phase
	LDRB	r0, [r4, #0x05]           @ Vox.Decay?
	CMP	r0, #0x00                 @  Y: EG is ready
	BNE	1f
0:	ADD	r6, #0x01                 @ Move to Sustain phase
	LDRB	r0, [r4, #0x06]           @ EG = Vox.Sustain * FFFFhh/FFh
	LSL	r1, r0, #0x08
	ADD	r1, r0
1:	STRH	r1, [r4, #0x0C]           @ Store EG
#endif
	B	.LVoxUpdate_KeyOn_Done

#if USGE_GENERATE_ENVELOPE

.LVoxUpdate_KeyOnWithAttack:
#if USGE_VOLSUBDIV
	STRH	r1, [r4, #0x0C]           @ EG = 0
	STRH	r1, [r4, #0x0E]           @ VolL = VolR = 0, to ramp from silence
#else
	@MOV	r0, r0                    @ EG = AttackStep/2 (trade-off between silence and next level)
	LDR	r1, =uSGE_RecpLUT         @ This is because otherwise, the first mix chunk is
	BL	uSGE_Driver_GetLinearStep @ for silence, which is practically useless
	LSR	r0, #0x01
	STRH	r0, [r4, #0x0C]
#endif
	B	.LVoxUpdate_KeyOn_Done

.LVoxUpdate_KeyOff:
	MOV	r0, #USGE_VOX_STAT_EG_MSK @ EGPhase -> r0
	AND	r0, r6
	SUB	r0, #USGE_VOX_STAT_EG_HLD @ EGPhase == Hold?
	BNE	.LVoxUpdate_KeyOn_Done
0:	MVN	r0, r0                    @  Y: Reset EG = 1.0, EGPhase = Sustain
	ADD	r6, #USGE_VOX_STAT_EG_SUS-USGE_VOX_STAT_EG_HLD
	STRH	r0, [r4, #0x0C]
1:	B	.LVoxUpdate_KeyOff_Done

.LVoxUpdate_EG_Sustain:
	LDRB	r0, [r4, #0x06]           @ EG = Sustain * FFFFh/FFh
	LSL	r1, r0, #0x08
	ORR	r0, r1
	B	.LVoxUpdate_EG_Ready

.LVoxUpdate_EG_Decay:
	LDRB	r0, [r4, #0x05]           @ EGc -> r0
	BL	uSGE_Driver_GetExpDecStep
	LDRH	r1, [r4, #0x0C]           @ EG *= EGc -> r0
	MUL	r0, r1
	LSR	r0, #0x10
	LDRB	r2, [r4, #0x06]           @ SustainLevel = Sustain * FFFF/FFh -> r2
	LSL	r3, r2, #0x08
	ORR	r2, r3
	CMP	r0, r2                    @ EG <= SustainLevel?
	BHI	.LVoxUpdate_EG_Ready
0:	MOV	r0, r2                    @  Y: EG = SustainLevel, EGPhase = Sustain
	ADD	r6, #0x01
	B	.LVoxUpdate_EG_Ready

.LVoxUpdate_EG_Hold:
	LDRB	r0, [r4, #0x04]           @ EGc -> r0
	BL	uSGE_Driver_GetLinearStep
	LDRH	r1, [r4, #0x0C]           @ EG += EGc -> r0
	ADD	r0, r1
	LSR	r1, r0, #0x10             @ EG >= 1.0?
	BEQ	.LVoxUpdate_EG_Ready
0:	MVN	r0, r1                    @  Y: EG = 1.0, EGPhase = Decay
	LSR	r0, #0x10
	ADD	r6, #0x01
	B	.LVoxUpdate_EG_Ready

.LVoxUpdate_EG_Attack:
	LDRB	r0, [r4, #0x03]           @ EGc -> r0
	BL	uSGE_Driver_GetLinearStep
	LDRH	r1, [r4, #0x0C]           @ EG += EGc -> r0
	ADD	r0, r1
	LSR	r1, r0, #0x10             @ EG >= 1.0?
	BEQ	.LVoxUpdate_EG_Ready
0:	LDRB	r0, [r4, #0x04]           @  Y: HoldTime -> r0
	MOV	r1, #0x01
	SUB	r0, #0x01                 @     EG      = (HoldTime == 0) ? FFFFh : 0
	LSR	r0, #0x10
	ADC	r6, r1                    @     EGPhase = (HoldTime == 0) ? Decay : Hold
	B	.LVoxUpdate_EG_Ready

.LVoxUpdate_EG_Manual:
	LDRH	r0, [r4, #0x0C]           @ EG = Vox.EG
#endif

.LVoxUpdate_EG_Ready:
	STRB	r6, [r4, #0x00]           @ Store updated Vox.Stat
#if !USGE_VOLSUBDIV
	LDRH	r1, [r4, #0x0C]           @ Load current EG -> r1
#endif
#if USGE_GENERATE_ENVELOPE
	STRH	r0, [r4, #0x0C]           @ Store next EG
#endif
#if USGE_GENERATE_ENVELOPE
	LSL	r2, r6, #(32-4)           @ Manual envelope?
	BCS	1f
0:	MOV	r2, #USGE_VOX_STAT_EG_MSK @  N: EGPhase == Hold?
	AND	r2, r6
	SUB	r2, #USGE_VOX_STAT_EG_HLD
	BNE	1f
	MVN	r2, r2                    @   Y: Override to EG = 1.0
# if USGE_VOLSUBDIV
	LSR	r0, r2, #0x10
# else
	LSR	r1, r2, #0x10
# endif
1:
#endif

.LVoxUpdate_StoreToVoxTable:
	LDRB	r2, [r4, #0x01]           @ VolL * EG -> r2
#if USGE_STEREOMIX
	LDRB	r3, [r4, #0x02]           @ VolR * EG -> r3
#endif
#if USGE_VOLSUBDIV
	MUL	r2, r0
# if USGE_STEREOMIX
	MUL	r3, r0
# endif
	LSR	r6, r2, #0x10             @ NewVolL -> r6
	LDRB	r2, [r4, #0x0E]           @ OldVolL -> r2
	STRB	r6, [r4, #0x0E]           @ Store VolL
# if USGE_VOLSUBDIV_RATIO
	MOV	r0, r6                    @ LoVol = NewVolL -> r0
	MOV	r1, r2                    @ HiVol = OldVolL -> r1
# endif
# if USGE_STEREOMIX
	LSR	r7, r3, #0x10             @ NewVolR -> r7
	LDRB	r3, [r4, #0x0F]           @ OldVolR -> r3
	STRB	r7, [r4, #0x0F]           @ Store VolR
	LSL	r7, #0x10
	ORR	r7, r6                    @ Pack NewVolL|NewVolR -> r7
	LSL	r6, r3, #0x10
	ORR	r6, r2                    @ Pack OldVolL|OldVolR -> r6
	SUB	r7, r6                    @ VolStep = NewVol - OldVol -> r7
	LSL	r6, #0x08                 @ VolCur = OldVol -> r6
	MOV	r5, #0x18
# else
	SUB	r7, r6, r2                @ VolStep = NewVol - OldVol -> r7
	LSL	r6, r2, #0x08             @ VolCur = OldVol -> r6
	MOV	r5, #0x14
# endif
	ADD	r5, r8
	STMIA	r5!, {r6,r7}              @ Store {VolCur,VolStep}
# if USGE_VOLSUBDIV_RATIO
#  if USGE_STEREOMIX
	ASR	r5, r7, #0x10             @ ABS(VolStepR) -> r5
	BPL	0f                        @ * This will be off by 1 if VolStepL < 0
	NEG	r5, r5
0:	SUB	r7, r1, r0                @ ABS(VolStepL) -> r7, and ensure LoVol is in r0, HiVol in r1
	BHI	0f
	ADD	r0, r7
	SUB	r1, r7
	NEG	r7, r7
0:	CMP	r5, r7                    @ ABS(VolStepR) > ABS(VolStepL)?
	BLS	1f
	LSR	r0, r6, #0x18             @  Y: LoVol = NewVolR
	LDRB	r1, [r4, #0x0F]           @     HiVol = OldVolR
#  endif
	SUB	r7, r0, r1                @ Ensure LoVol is in r0, HiVol in r1
	BCC	1f                        @ * This check is also needed when selecting the R volume
	SUB	r0, r7
	ADD	r1, r7
1:	MOV	r6, #0x00                 @ ThisSubdivLevel = 0 -> r6
	ADD	r0, #0x03                 @ <- Adding a bias here helps avoid excessive subdivision for
	ADD	r1, #0x03                 @    very low volumes, where the stepping is inaudible anyway
10:	ADD	r7, r1, #(1<<USGE_VOLSUBDIV_RATIO)-1
	LSR	r7, r1, #USGE_VOLSUBDIV_RATIO
	SUB	r1, r7                    @ HiVol *= 1-2^-RATIO
	CMP	r1, r0                    @ HiVol > LoVol?
	BLS	2f
	ADD	r6, #0x01                 @  Y: ThisSubdivLevel++
#  if (USGE_VOLSUBDIV > 1)
	CMP	r6, #USGE_VOLSUBDIV       @     Can subdivide further?
	BCC	10b
#  endif
2:	CMP	r6, r9                    @ SubdivLevel = MAX(SubdivLevel, ThisSubdivLevel)
	BCC	0f
	MOV	r9, r6
0:
# endif
#else
	MUL	r2, r1
	LSR	r2, #0x10                 @ Shift out EG bits
	STRB	r2, [r4, #0x0E]           @ Store VolL
# if USGE_STEREOMIX
	MUL	r3, r1
	LSR	r3, #0x10
	STRB	r3, [r4, #0x0F]           @ Store VolR
# endif
#endif
1:	LDR	r0, [r4, #0x08]           @ Rate | Offs<<16 -> r0
	LSL	r1, r0, #0x10
	LSR	r1, #0x10+USGE_FRACBITS+2
	BNE	.LVoxUpdate_ClipRate
.LVoxUpdate_ClipRate_Return:
	LDR	r1, [r4, #0x10]           @ DataPtr -> r1
	LDR	r7, [r4, #0x14]           @ Vox.Wav -> r7
	LDMIA	r7!, {r5,r6}              @ Wav.{Size,Loop,Data} -> r5,r6,r7
	ADD	r5, r7                    @ End = Wav.Data + Wav.Size -> r5
	SUB	r5, r1                    @ SampRem = End - DataPtr -> r5
	MOV	ip, r6                    @ Save Wav.Loop -> ip (we need it later)
	CMP	r6, #0x00                 @ One-shot samples are looped while mixing
	BNE	0f
	MOV	r6, #USGE_WAV_MIN_LOOP
0:	MOV	lr, r1                    @ Save original DataPtr -> lr
	LSL	r7, r0, #0x10             @ Rewind DataPtr by (int)(Rate*8) (mixer pre-increments)
	LSR	r7, #(16+USGE_FRACBITS)
	SUB	r1, r7
	LSL	r7, r0, #(32-USGE_FRACBITS+3)
	SUB	r0, r7                    @ Phase -= Rate*8? (again, mixer pre-increments)
	SBC	r7, r7                    @  Needed borrow bit: Rewind another sample
	ADD	r1, r7
	MOV	r7, r8                    @ Store to voice table
#if USGE_STEREOMIX
	STMIA	r7!, {r0-r3,r5-r6}
#else
	STMIA	r7!, {r0-r2,r5-r6}
#endif
#if USGE_VOLSUBDIV
	ADD	r7, #0x08
#endif
	MOV	r8, r7
	MOV	r1, lr                    @ Restore original DataPtr

.LVoxUpdate_CheckEGDecay:
#if USGE_GENERATE_ENVELOPE
	LDRB	r7, [r4, #0x00]           @ Vox.Stat -> r7
	MOV	r2, #USGE_VOX_STAT_EG_MSK @ Vox.EnvPhase -> r2
	AND	r2, r7
	LDRH	r3, [r4, #0x0C]           @ Vox.EG -> r3
	SUB	r2, #USGE_VOX_STAT_EG_HLD @ If we are in Attack or Hold (or MANUAL mode), do NOT end when below threshold
	BLE	0f
# if (USGE_EG_LOG2THRES > 8)
	MOV	r2, #(1 << (16-USGE_EG_LOG2THRES))
# else
	MOV	r2, #0x01
	LSL	r2, #(16-USGE_EG_LOG2THRES)
# endif
0:	CMP	r3, r2                    @ EG below threshold?
	BLT	.LVoxUpdate_DecaysToSilence
#endif

.LVoxUpdate_StoreToVoxStruct:
	LSR	r3, r0, #(32-USGE_FRACBITS)
	LSL	r2, r0, #0x10             @ Rate -> r2, Offs -> r3
	LSR	r2, #0x10
	LDR	r7, [sp, #0x0C]           @ N -> r7
	MUL	r7, r2                    @ SampsThisUpdate = Floor[N * Rate + Offs] -> r7
	ADD	r7, r3
	LSL	r6, r7, #(32-USGE_FRACBITS)
	LSR	r6, #0x10                 @ Store next phase offset
	STRH	r6, [r4, #0x0A]
	LSR	r7, #USGE_FRACBITS
	ADD	r1, r7                    @ DataPtr += SampsThisUpdate
	SUB	r5, r7                    @ SampRem -= SampsThisUpdate?
	BGT	11f                       @  Do not need to loop or terminate
1:	MOV	r7, ip                    @ Wav.Loop -> r7
	CMP	r7, #0x00                 @ Do we have a loop?
	BEQ	.LVoxUpdate_SampleEnds
10:	SUB	r1, r7                    @ DataPtr -= LoopSize
	ADD	r5, r7                    @ Continue looping until fully wrapped
	BLE	10b
11:	STR	r1, [r4, #0x10]           @ Store DataPtr for next update

.LVoxUpdate_Finish:
	POP	{r4,r7}
	B	.LVoxUpdateLoop_Tail

.LVoxUpdate_ClipRate:
	LSR	r0, #0x10                 @ Rate = MAX_RATE
#if (USGE_FRACBITS == 14)
	ADD	r0, #0x01
	LSL	r0, #0x10
	SUB	r0, #0x01
#else
	LSL	r0, #0x10
	MOV	r1, #0x04
	LSL	r1, #USGE_FRACBITS
	ORR	r0, r1
#endif
	B	.LVoxUpdate_ClipRate_Return

.LVoxUpdate_SampleEnds:
	LDRB	r7, [r4, #0x00]           @ Vox.Stat -> r7

.LVoxUpdate_DecaysToSilence:
	SUB	r7, #USGE_VOX_STAT_ACTIVE @ Vox.Stat &= ~ACTIVE (finishes or decays to silence after this update)
	STRB	r7, [r4, #0x00]
	POP	{r4,r7}
	B	.LVoxUpdateLoop_Tail

ASM_FUNC_END(uSGE_Driver_VoiceUpdate)

/************************************************/
//! Envelope Calculations
/************************************************/
#if USGE_GENERATE_ENVELOPE
/************************************************/

@ r0:  DecayTime (in companded form)
@ r1: &RecpLUT

ASM_FUNC_BEG(uSGE_Driver_GetLinearStep, ASM_FUNCSECT_IWRAM;ASM_MODE_THUMB;ASM_ALIGN(4))

uSGE_Driver_GetLinearStep:
#if !USGE_FIXED_RATE
	LDR	r2, [sp, #0x08]      @ Driver.EnvMul -> r2
	LDR	r2, [r2, #0x0C]
#endif

.LGetLinearStep_Core:
	LSL	r0, #0x01
	LDRH	r0, [r1, r0]         @ dt = 1/CompandedEnvTime -> r0 [.16fxp]
#if USGE_FIXED_RATE
	LDR	r2, =USGE_FIXED_RATE * 1626
	MUL	r0, r0               @ dt^2 -> r0 [.32fxp] (generates a warning, but is fine)
#else
	MOV	r1, r0               @ dt^2 -> r1
	MUL	r1, r0
#endif
	BX	pc
	NOP
ASM_MODE_ARM
#if USGE_FIXED_RATE
	UMULL	r2, r3, r0, r2       @ dv = dt^2 * (MsecPerUpdate*1626/1000) -> r2,r3 [.32 + .24 = .56fxp]
	MOV	r0, r3, lsr #(56 - 32 - 16)
#else
	UMULL	r2, r0, r1, r2
#endif
	CMP	r0, #0x01<<16        @ Clip to 0..FFFFh range
	BXCC	lr
0:	MOV	r0, #0x01<<16
	SUB	r0, r0, #0x01
	BX	lr

ASM_FUNC_END(uSGE_Driver_GetLinearStep)

/************************************************/

@ r0:  DecayTime (in companded form)
@ r1: &RecpLUT

ASM_FUNC_BEG(uSGE_Driver_GetExpDecStep, ASM_FUNCSECT_IWRAM;ASM_MODE_THUMB)

uSGE_Driver_GetExpDecStep:
#if !USGE_FIXED_RATE
	LDR	r2, [sp, #0x08]      @ Driver.EnvMul -> r2
	LDR	r2, [r2, #0x0C]
#endif
	PUSH	{lr}
	BL	.LGetLinearStep_Core
	LDR	r2, =32656 @ Scale = -Log2[10^(-96/20)]*2^(27 - 16)
	MOV	r3, #0x10  @ Return 2^(16 - Scale/DeltaPerUpdate)
	MUL	r2, r0
	LSL	r3, #0x1B
	SUB	r0, r3, r2
	BLS	1f
	BL	uSGE_Exp2fxp
	POP	{pc}
1:	MOV	r0, #0x00
	POP	{pc}

ASM_FUNC_END(uSGE_Driver_GetExpDecStep)

/************************************************/
#endif
/************************************************/
//! EOF
/************************************************/
