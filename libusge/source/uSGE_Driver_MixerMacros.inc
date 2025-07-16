/************************************************/
#include "uSGE_Config.h"
/************************************************/
/*!

Register allocations for mixer:
 r0..r7: Wet (only r0..r3 used in mono mode, with r4 being &DstBuffer[])
 r8:  00FF00FFh | -nLoopsRem<<25
 r9: [Temp]
 sl: &SrcData
 fp: [Temp]
 ip:  VolL (or Volume in mono mode)
 lr:  VolR (unused in mono mode)
 sp+00h: &DstBufferL[] (in stereo mode)
 sp+04h: &DstBufferR[] (in stereo mode)

!*/

/************************************************/

/*!

Voice mixing table structure:

struct MonoMixerEntry_t {
  [00h] uint16_t Rate;
  [02h] uint16_t Pos;
  [04h] const int8_t *DataPtr;
  [08h] uint32_t Volume;
  [0Ch] uint32_t SampRem;
  [10h] uint32_t LoopSize;
  [14h] enable_if(USGE_VOLSUBDIV) uint32_t VolCur;
  [18h] enable_if(USGE_VOLSUBDIV) uint32_t VolStep;
}

struct StereoMixerEntry_t {
  [00h] uint16_t Rate;
  [02h] uint16_t Pos;
  [04h] const int8_t *DataPtr;
  [08h] uint32_t VolL;
  [0Ch] uint32_t VolR;
  [10h] uint32_t SampRem;
  [14h] uint32_t LoopSize;
  [18h] enable_if(USGE_VOLSUBDIV) uint32_t VolCur;
  [1Ch] enable_if(USGE_VOLSUBDIV) uint32_t VolStep;
}

!*/

/************************************************/

#define OFFSET_OF_ADC_FROM_START     (0x04 * 3) //! ADR,LDMIA,ADDS
#define OFFSET_OF_LDRSB_FROM_START   (0x04 * 5) //! ADR,LDMIA,ADDS,ADC,STMIA
#define OFFSET_OF_MLANE_FROM_LDRSB   (0x04 * 3) //! LDRSB,LDRSB,ADDS

#if USGE_STEREOMIX
# define STRIDE_BETWEEN_SAMPLE_PAIRS (0x04 * 5) //! LDRSB,LDRSB,ADDS,MLANE,MLANE
# define STRIDE_BETWEEN_VOICES       (0x04 * 25)
#else
# define STRIDE_BETWEEN_SAMPLE_PAIRS (0x04 * 4) //! LDRSB,LDRSB,ADDS,MLANE
# define STRIDE_BETWEEN_VOICES       (0x04 * 21)
#endif

#if (USGE_MAX_VOICES <= 8)
# define SMALL_VOXTABLE
#endif

/************************************************/

@ Create table of jump instructions and jump targets
.macro CREATE_VOXLOOPTABLE_ENTRY Target
	BCC	\Target + (. - .LMixLoop_LoopOpcode)
	.word	\Target
.endm
.macro CREATE_VOXLOOPTABLE VoiceIdx=(USGE_MAX_VOICES-1)
	CREATE_VOXLOOPTABLE_ENTRY (.LMixLoop_BlockLoop + (\VoiceIdx)*STRIDE_BETWEEN_VOICES)
	.if (\VoiceIdx > 0)
		CREATE_VOXLOOPTABLE (\VoiceIdx - 1)
	.endif
.endm

@ Create table of pointers to voice table entries
.macro CREATE_VOXTABLEPTRS VoiceIdx=0
	.word uSGE_Driver_VoxTable + USGE_VOXTABLE_ENTRY_SIZE*(\VoiceIdx)
	.if (\VoiceIdx < USGE_MAX_VOICES-1)
		CREATE_VOXTABLEPTRS (\VoiceIdx + 1)
	.endif
.endm

/************************************************/

@ Mix two samples to output registers
@ Instruction order:
@ LDRSB Samp0, [sl, #0]
@ LDRSB Samp2, [sl, #Delta*2]
@ LDRSB Samp1, [sl, #Delta]
@ LDRSB Samp3, [sl, #Delta*3]!
@ LDRSB Samp4, [sl, #Delta]!
@ LDRSB Samp6, [sl, #Delta*2]
@ LDRSB Samp5, [sl, #Delta]
@ LDRSB Samp7, [sl, #Delta*3]
.macro MixLoop_BlockMix RdL,RvL, WrBack1, WrBack2, VoiceIdx, RdR=,RvR=
	LDRSB	r9, [sl, #0x00]\WrBack1               @ Load sample 0     (offset is self-modifying)
	LDRSB	fp, [sl, #0x00]\WrBack2               @ Load sample 2 (!) (offset is self-modifying)
	ADDS	r9, r9, fp, lsl #0x10                 @ Combine Smp0|Smp2
#if USGE_STEREOMIX
	MLANE	\RdL, r9, \RvL, \RdL                  @ Mix Smp0|Smp2     (instruction becomes MULNE on first voice)
	MLANE	\RdR, r9, \RvR, \RdR
#else
	MLANE	\RdL, \RvL, r9, \RdL
#endif
.endm

@ Mix voices to output registers
.macro MixLoop_BlockMixVoices VoiceIdx=(USGE_MAX_VOICES-1)
#ifdef SMALL_VOXTABLE
	ADR	fp, uSGE_Driver_VoxTable + USGE_VOXTABLE_ENTRY_SIZE*(\VoiceIdx)
#else
	LDR	fp, .LMixLoop_VoiceTablePtrs + 0x04*(\VoiceIdx)
#endif
#if USGE_STEREOMIX
	LDMIA	fp, {r9,sl,ip,lr}                     @ Rate | Pos<<16 -> r9, DataPtr -> sl, VolL -> ip, VolR -> lr
#else
	LDMIA	fp, {r9,sl,ip}                        @ Rate | Pos<<16 -> r9, DataPtr -> sl, Volume -> ip
#endif
	ADDS	r9, r9, r9, lsl #(32-USGE_FRACBITS+3) @ Pos += Rate*8?
	ADC	sl, sl, #0x00                         @ SrcData = (DataPtr += (int)(Rate*8) + Carry) (#IMM is self-modifying)
	STMIA	fp, {r9,sl}                           @ Store updated {DataPtr,Rate|Pos}
1:	MixLoop_BlockMix r0, ip,  ,  , \VoiceIdx, r4, lr    @ Mix samples to output
	MixLoop_BlockMix r1, ip,  , !, \VoiceIdx, r5, lr
	MixLoop_BlockMix r2, ip, !,  , \VoiceIdx, r6, lr
	MixLoop_BlockMix r3, ip,  ,  , \VoiceIdx, r7, lr
.if (\VoiceIdx > 0)
	MixLoop_BlockMixVoices (\VoiceIdx - 1)
.endif
.endm

@ Combine four samples from two registers into one register
@ Destroys Ra,Rb
.macro MixLoop_BlockMerge Rd, Ra, Rb
#if USGE_CLIPMIXDOWN
	AND	sl, r8, \Ra, lsr #0x07+1              @ Extract true-sign samples -> sl
	AND	fp, r8, \Rb, lsr #0x07+1
	ORR	sl, sl, fp, lsl #0x08
#endif
	AND	\Ra, r8, \Ra, lsr #0x07               @ 00cc00aa
	AND	\Rb, r8, \Rb, lsr #0x07               @ 00dd00bb
	ORR	\Rd, \Ra, \Rb, lsl #0x08              @ ddccbbaa
#if USGE_CLIPMIXDOWN
	EOR	ip, sl, \Rd                           @ Extract wrong signs -> ip? (in LSB of each sample)
	ANDS	ip, r9, ip, lsr #0x07
	BNE	.LMixLoop_BlockLoop_Clip_\Rd
#endif
.endm

@ Clip samples in Rd
@ ip contains incoming mask of wrong signs (in LSB of each byte)
@ sl contains incoming true-sign samples (only the MSB of each byte matters)
@ Destroys sl,ip
.macro MixLoop_BlockClip Rd
	RSB	ip, ip, ip, lsl #0x08                 @ Create mask of clipped samples
	BIC	sl, r9, sl, lsr #0x07                 @ Get complement of true sign bits
	RSB	sl, sl, r9, lsl #0x07                 @ Create sign-corrected clipped samples
	AND	sl, sl, ip                            @ Mask clipped samples
	BIC	\Rd, \Rd, ip                          @ Clear wrong samples
	ORR	\Rd, \Rd, sl                          @ Combine clipped samples
.endm

/************************************************/
//! EOF
/************************************************/
