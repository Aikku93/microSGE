/************************************************/
#include "uSGE_ASM.h"
#include "uSGE_Config.h"
#include "uSGE.h"
/************************************************/

@ r0: VoxCnt
@ r1: BufCnt
@ r2: BufLen

ASM_FUNC_GLOBAL(uSGE_Driver_GetWorkAreaSize)
ASM_FUNC_BEG   (uSGE_Driver_GetWorkAreaSize, ASM_FUNCSECT_TEXT;ASM_MODE_THUMB)

uSGE_Driver_GetWorkAreaSize:
	CMP	r0, #0x00                    @ Invalid VoxCnt?
	BEQ	.LExit_Error
	CMP	r0, #USGE_MAX_VOICES
	BHI	.LExit_Error
	CMP	r1, #0x00                    @ Invalid BufCnt?
	BEQ	.LExit_Error
	CMP	r1, #0xFF
	BHI	.LExit_Error
	CMP	r2, #0x00                    @ Invalid BufLen?
	BEQ	.LExit_Error
	LSL	r3, r2, #0x20-3              @ BufLen not multiple of M?
	BNE	.LExit_Error
	LSR	r3, r2, #0x03                @ BufLen > 7Fh*M?
	CMP	r3, #0x7F
	BHI	.LExit_Error
1:	MOV	r3, #USGE_VOX_SIZE           @ Size = sizeof(Header) + sizeof(Vox_t[VoxCnt])
	MUL	r0, r3
	MUL	r1, r2                       @ BufCnt *= BufLen -> r1
	ADD	r0, #USGE_DRIVER_HEADER_SIZE
	LSL	r2, r1, #0x20-4              @ BufCnt*BufLen must be a multiple of 16 samples
	BNE	.LExit_Error
#if USGE_STEREOMIX
	LSL	r1, #0x01
#endif
	ADD	r0, r1                       @ Size += BufSize
	BX	lr

.LExit_Error:
	MOV	r0, #0x00                    @ Return Size=0 on error
	BX	lr

ASM_FUNC_END(uSGE_Driver_GetWorkAreaSize)

/************************************************/
//! EOF
/************************************************/
