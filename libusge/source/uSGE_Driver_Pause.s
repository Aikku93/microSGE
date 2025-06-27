/************************************************/
#include "uSGE_ASM.h"
#include "uSGE_Config.h"
#include "uSGE_HW.h"
#include "uSGE.h"
/************************************************/

@ r0: Driver

ASM_FUNC_GLOBAL(uSGE_Driver_Pause)
ASM_FUNC_BEG   (uSGE_Driver_Pause, ASM_FUNCSECT_TEXT;ASM_MODE_THUMB)

uSGE_Driver_Pause:
	LDR	r2, [r0, #0x00]           @ Magic -> r2
	LDR	r3, =USGE_DRIVER_STATE_READY
	SUB	r3, r2                    @ Not in Ready state?
	BNE	2f
1:	ADD	r2, #USGE_DRIVER_STATE_PAUSED - USGE_DRIVER_STATE_READY
	STRB	r2, [r0, #0x00]           @ Mark as Paused
	LDR	r2, =REG_SOUNDFIFO_A
	@MOV	r3, #0x00                 @ Stop DMA and timer
#if (USGE_STEREOMIX || USGE_DMACHAN == 1)
	STR	r3, [r2, #REG_DMACNT(1) - REG_SOUNDFIFO_A]
#endif
#if (USGE_STEREOMIX || USGE_DMACHAN == 2)
	STR	r3, [r2, #REG_DMACNT(2) - REG_SOUNDFIFO_A]
#endif
	STR	r3, [r2, #REG_TIMER(USGE_HWTIMER_IDX) - REG_SOUNDFIFO_A]
2:	BX	lr

ASM_FUNC_END(uSGE_Driver_Pause)

/************************************************/
//! EOF
/************************************************/
