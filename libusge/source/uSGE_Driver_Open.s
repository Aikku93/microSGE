/************************************************/
#include "uSGE_ASM.h"
#include "uSGE_Config.h"
#include "uSGE.h"
/************************************************/

@ r0: &Driver
@ r1:  VoxCnt
@ r2:  RateHz
@ r3:  BufCnt
@ sp+00h: BufLen

ASM_FUNC_GLOBAL(uSGE_Driver_Open)
ASM_FUNC_BEG   (uSGE_Driver_Open, ASM_FUNCSECT_TEXT;ASM_MODE_THUMB)

uSGE_Driver_Open:
	PUSH	{r4-r5,lr}
	LDR	r4, [sp, #0x0C]                @ BufLen -> r4
1:	CMP	r1, #0x00                      @ Invalid VoxCnt?
	BEQ	.LExit_Error
	CMP	r1, #USGE_MAX_VOICES
	BHI	.LExit_Error
	LSR	r5, r2, #0x06                  @ RateHz too low (<8000Hz) or too high?
	CMP	r5, #(8000 >> 6)
	BCC	.LExit_Error
	LSR	r5, r2, #0x10
	BNE	.LExit_Error
	CMP	r3, #0x02                      @ Invalid BufCnt?
	BCC	.LExit_Error
	CMP	r3, #0xFF
	BHI	.LExit_Error
	CMP	r4, #0x00                      @ Invalid BufLen?
	BEQ	.LExit_Error
	LSL	r5, r4, #0x20-3                @ BufLen not multiple of M?
	BNE	.LExit_Error
	LSR	r5, r4, #0x03                  @ BufLen > 7Fh*M?
	CMP	r5, #0x7F
	BHI	.LExit_Error

.LPrepareWorkArea:
	STRB	r3, [r0, #0x05]                @ Store BufCnt
	STRB	r1, [r0, #0x06]                @ Store VoxCnt
	STRH	r2, [r0, #0x08]                @ Store RateHz
	STRH	r4, [r0, #0x0A]                @ Store BufLen
	MUL	r3, r4                         @ BufSize = BufLen*BufCnt -> r3
	LSL	r3, #(32-4)                    @ BufSize must be a multiple of 16 samples
	BNE	.LExit_Error
0:	MOV	r2, #USGE_VOX_SIZE             @ Clear voices
	MUL	r2, r1
	MOV	r1, #0x00
	ADD	r0, #0x10
	BL	memset
	SUB	r0, #0x10
#if !USGE_FIXED_RATE
	MOV	r5, r0
	LDR	r0, =1626                      @ Store EnvMul = BufLen * 1626 * 2^16 / RateHz
	MUL	r0, r4
	LSR	r1, r0, #0x10
	LSL	r0, #0x10
	LDRH	r2, [r5, #0x08]
	MOV	r3, #0x00
	SUB	r0, #0x01
	SBC	r1, r3
	BL	__aeabi_uldivmod               @ <- Yes, this is a 64-bit division...
	ADD	r0, #0x01
	STR	r0, [r5, #0x0C]
	MOV	r0, r5
#endif
0:	LDR	r1, =USGE_DRIVER_STATE_PAUSED
	STR	r1, [r0, #0x00]                @ Store State = Paused (we will call Resume() to start playback)
	BL	uSGE_Driver_Resume

.LExit:
	POP	{r4-r5}
	POP	{r3}
	BX	r3

.LExit_Error:
	MOV	r0, #0x00                      @ Return 0 on failure
	B	.LExit

ASM_FUNC_END(uSGE_Driver_Open)

/************************************************/
//! EOF
/************************************************/
