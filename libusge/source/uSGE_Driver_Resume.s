/************************************************/
#include "uSGE_ASM.h"
#include "uSGE_Config.h"
#include "uSGE_HW.h"
#include "uSGE.h"
/************************************************/

#if USGE_STEREOMIX
# define FIFO_REGISTER REG_SOUNDFIFO_A
# define FIFO_A_MASK (~0)
# define FIFO_B_MASK (~0)
#elif (USGE_FIFOTARGET == 0)
# define FIFO_REGISTER REG_SOUNDFIFO_A
# define FIFO_A_MASK (~0)
# define FIFO_B_MASK 0
#elif (USGE_FIFOTARGET == 1)
# define FIFO_REGISTER REG_SOUNDFIFO_B
# define FIFO_A_MASK 0
# define FIFO_B_MASK (~0)
#endif

/************************************************/

@ r0: Driver

ASM_FUNC_GLOBAL(uSGE_Driver_Resume)
ASM_FUNC_BEG   (uSGE_Driver_Resume, ASM_FUNCSECT_TEXT;ASM_MODE_THUMB)

uSGE_Driver_Resume:
	MOV	r3, lr
	PUSH	{r3-r5}
	MOV	r4, r0                        @ Driver -> r4
1:	LDR	r2, [r0, #0x00]               @ State -> r2
	LDR	r3, =USGE_DRIVER_STATE_PAUSED
	CMP	r2, r3                        @ Not already paused?
	BNE	.LExit

.LClearOutBufs:
	LDRB	r2, [r4, #0x06]               @ VoxCnt -> r2
	MOV	r3, #USGE_VOX_SIZE
	ADD	r0, #USGE_DRIVER_HEADER_SIZE  @ Seek to voices
	MUL	r2, r3
	LDRB	r3, [r4, #0x05]               @ BufCnt -> r3
	ADD	r0, r2                        @ Seek to OutBuf - Done!
	LDRH	r5, [r4, #0x0A]               @ BufLen -> r2
	SUB	r1, r3, #0x01                 @ BufIdxR = BufCnt-1
	STRB	r1, [r4, #0x04]               @  * This forces a reset on the next Sync().
	STRB	r1, [r4, #0x07]               @ BufIdxW = BufCnt-1
	MUL	r5, r3                        @ memset(OutBuf, 0, sizeof(int8_t[1+STEREO][BufCnt][BufLen]))
#if USGE_STEREOMIX
	LSL	r2, r5, #0x01
#else
	MOV	r2, r5
#endif
	MOV	r1, #0x00
	@MOV	r0, r0
	BL	memset

.LPrepareHardware:
	LDR	r2, =REG_SOUNDCNT                          @ Enable all required audio hardware
	LDRH	r1, [r2, #REG_SOUNDCNT_X - REG_SOUNDCNT]
	MOV	r3, #REG_SOUNDCNT_X_MASTER_ENABLE
	ORR	r1, r3
	STRH	r1, [r2, #REG_SOUNDCNT_X - REG_SOUNDCNT]
	LDR	r1, [r2]
	LDR	r3, =REG_SOUNDCNT_LH_VALUE(0, \
		      (( \
		       REG_SOUNDCNT_H_FIFO_A_VOL_MASK   | \
		       REG_SOUNDCNT_H_FIFO_A_ENABLE_R   | \
		       REG_SOUNDCNT_H_FIFO_A_ENABLE_L   | \
		       REG_SOUNDCNT_H_FIFO_A_TIMER_MASK   \
		      ) & FIFO_A_MASK)                  | \
		      (( \
		       REG_SOUNDCNT_H_FIFO_B_VOL_MASK   | \
		       REG_SOUNDCNT_H_FIFO_B_ENABLE_R   | \
		       REG_SOUNDCNT_H_FIFO_B_ENABLE_L   | \
		       REG_SOUNDCNT_H_FIFO_B_TIMER_MASK   \
		      ) & FIFO_B_MASK)                    \
		     )
	BIC	r1, r3
#if USGE_STEREOMIX
	LDR	r3, =REG_SOUNDCNT_LH_VALUE(0, \
		      ( \
		       REG_SOUNDCNT_H_FIFO_A_VOL_100                 | \
		       REG_SOUNDCNT_H_FIFO_A_ENABLE_L                | \
		       REG_SOUNDCNT_H_FIFO_A_TIMER(USGE_HWTIMER_IDX) | \
		       REG_SOUNDCNT_H_FIFO_A_FLUSH                     \
		      )                                              | \
		      ( \
		       REG_SOUNDCNT_H_FIFO_B_VOL_100                 | \
		       REG_SOUNDCNT_H_FIFO_B_ENABLE_R                | \
		       REG_SOUNDCNT_H_FIFO_B_TIMER(USGE_HWTIMER_IDX) | \
		       REG_SOUNDCNT_H_FIFO_B_FLUSH                     \
		      )                                                \
		     )
#else
	LDR	r3, =REG_SOUNDCNT_LH_VALUE(0, \
		      (( \
		       REG_SOUNDCNT_H_FIFO_A_VOL_100                 | \
		       REG_SOUNDCNT_H_FIFO_A_ENABLE_L                | \
		       REG_SOUNDCNT_H_FIFO_A_ENABLE_R                | \
		       REG_SOUNDCNT_H_FIFO_A_TIMER(USGE_HWTIMER_IDX) | \
		       REG_SOUNDCNT_H_FIFO_A_FLUSH                     \
		      ) & FIFO_A_MASK)                               | \
		      (( \
		       REG_SOUNDCNT_H_FIFO_B_VOL_100                 | \
		       REG_SOUNDCNT_H_FIFO_B_ENABLE_L                | \
		       REG_SOUNDCNT_H_FIFO_B_ENABLE_R                | \
		       REG_SOUNDCNT_H_FIFO_B_TIMER(USGE_HWTIMER_IDX) | \
		       REG_SOUNDCNT_H_FIFO_B_FLUSH                     \
		      ) & FIFO_B_MASK)                                 \
		     )
#endif
	ORR	r1, r3
	STR	r1, [r2]
1:	ADD	r2, #FIFO_REGISTER - REG_SOUNDCNT
	MOV	r1, #0x00
	STR	r1, [r2]
#if USGE_STEREOMIX
	STR	r1, [r2, #REG_SOUNDFIFO_B - FIFO_REGISTER]
#endif
#if (USGE_STEREOMIX || USGE_DMACHAN == 1)
1:	LDRH	r3, [r2, #REG_DMACNT_H(1) - FIFO_REGISTER] @ Wait DMA1 (safety)
	LSR	r3, #0x10
	BCS	1b
#endif
#if (USGE_STEREOMIX || USGE_DMACHAN == 2)
1:	LDRH	r3, [r2, #REG_DMACNT_H(2) - FIFO_REGISTER] @ Wait DMA2 (safety)
	LSR	r3, #0x10
	BCS	1b
#endif
1:	STR	r3, [r2, #REG_TIMER(USGE_HWTIMER_IDX) - FIFO_REGISTER] @ Stop timer
1:	MOV	r1, r2
#if (USGE_STEREOMIX || USGE_DMACHAN == 1)
	ADD	r1, #REG_DMASAD(1) - FIFO_REGISTER
	MOV	r3, #0xB7                                  @ Cnt = DST_FIXED | SRC_FIXED | REPEAT | DATA32 | MODE_SOUNDFIFO | ENABLE
	LSL	r3, #0x08
	ADD	r3, #0x40
	LSL	r3, #0x10
	STMIA	r1!, {r0,r2,r3}                            @ DMA1SAD = LeftBuf,  DMA1DAD = FIFO, DMA1CNT = Cnt
#endif
#if USGE_STEREOMIX
	ADD	r0, r5
	ADD	r2, #REG_SOUNDFIFO_B - FIFO_REGISTER
	STMIA	r1!, {r0,r2,r3}                            @ DMA2SAD = RightBuf, DMA1DAD = FIFO, DMA1CNT = Cnt
#elif (USGE_DMACHAN == 2)
	ADD	r1, #REG_DMASAD(2) - FIFO_REGISTER
	MOV	r3, #0xB7                                  @ Cnt = DST_FIXED | SRC_FIXED | REPEAT | DATA32 | MODE_SOUNDFIFO | ENABLE
	LSL	r3, #0x08
	ADD	r3, #0x40
	LSL	r3, #0x10
	STMIA	r1!, {r0,r2,r3}                            @ DMA2SAD = LeftBuf,  DMA2DAD = FIFO, DMA2CNT = Cnt
#endif
	MOV	r5, r1                                     @ &DMA3SAD -> r5 (or &DMA2SAD in mono mode with DMA1)
2:	LDR	r0, =GBA_HW_FREQ_HZ*2                      @ Get Period = Round[HW_FREQ / RateHz]
	LDRH	r1, [r4, #0x08]
	BL	__aeabi_uidiv
	ADD	r0, #0x01
	LSR	r0, #0x01
	MOV	r1, #REG_TIMER_H_ENABLE+1                  @ Start timer and return Period
	LSL	r1, #0x10
	SUB	r1, r0
#if (USGE_STEREOMIX || USGE_DMACHAN == 2)
	STR	r1, [r5, #REG_TIMER(USGE_HWTIMER_IDX) - REG_DMASAD(3)]
#else
	STR	r1, [r5, #REG_TIMER(USGE_HWTIMER_IDX) - REG_DMASAD(2)]
#endif

.LExit_Ready:
	MOV	r1, #(USGE_DRIVER_STATE_READY) & 0xFF      @ Mark State as Ready
	STRB	r1, [r4, #0x00]

.LExit:
	POP	{r3-r5}
	BX	r3

ASM_FUNC_END(uSGE_Driver_Resume)

/************************************************/
//! EOF
/************************************************/
