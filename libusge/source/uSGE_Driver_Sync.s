/************************************************/
#include "uSGE_ASM.h"
#include "uSGE_Config.h"
#include "uSGE_HW.h"
#include "uSGE.h"
/************************************************/

@ r0: Driver

ASM_FUNC_GLOBAL(uSGE_Driver_Sync)
ASM_FUNC_BEG   (uSGE_Driver_Sync, ASM_FUNCSECT_TEXT;ASM_MODE_THUMB)

uSGE_Driver_Sync:
	LDR	r3, [r0, #0x00]           @ State -> r3
	LDR	r2, =USGE_DRIVER_STATE_READY
	SUB	r3, r2                    @ Invalid state?
	BNE	3f
0:	LDRB	r1, [r0, #0x04]           @ BfIdx -> r1
	LDRB	r2, [r0, #0x05]           @ BfCnt -> r2
	ADD	r1, #0x01                 @ ++BfIdx >= BfCnt?
	CMP	r1, r2
	BCC	2f
1:	LDR	r2, =REG_DMACNT_H(1)      @ Reset DMA
#if (USGE_STEREOMIX || USGE_DMACHAN == 1)
	STRH	r3, [r2, #REG_DMACNT_H(1) - REG_DMACNT_H(1)]
#endif
#if (USGE_STEREOMIX || USGE_DMACHAN == 2)
	STRH	r3, [r2, #REG_DMACNT_H(2) - REG_DMACNT_H(1)]
#endif
	MOV	r1, #0xB6                 @ DST_INC | SRC_INC | REPEAT | DATA32 | MODE_SOUNDFIFO | ENABLE
	LSL	r1, #0x08                 @ <- This also sets the lower 8 bits to 0, to get BfIdx=0
#if (USGE_STEREOMIX || USGE_DMACHAN == 1)
	STRH	r1, [r2, #REG_DMACNT_H(1) - REG_DMACNT_H(1)]
#endif
#if (USGE_STEREOMIX || USGE_DMACHAN == 2)
	STRH	r1, [r2, #REG_DMACNT_H(2) - REG_DMACNT_H(1)]
#endif
2:	STRB	r1, [r0, #0x04]           @ Store BfIdx
3:	BX	lr

ASM_FUNC_END(uSGE_Driver_Sync)

/************************************************/
//! EOF
/************************************************/
