/************************************************/
#pragma once
/************************************************/

//! 0 = Use TM0
//! 1 = Use TM1
#define USGE_HWTIMER_IDX 0

//! 1 = Use DMA1 (in mono mode)
//! 2 = Use DMA2 (in mono mode)
//! This has no effect with USGE_STEREOMIX
#define USGE_DMACHAN 1

//! 0 = Use FIFO_A
//! 1 = Use FIFO_B
//! This has no effect with USGE_STEREOMIX
#define USGE_FIFOTARGET 0

//! 0 = Generate mono output
//! 1 = Generate stereo output
#define USGE_STEREOMIX 1

//! 0 = Don't clip output
//! 1 = Apply clipping to output
#define USGE_CLIPMIXDOWN 1

//! 0 = Don't generate EG, and always assume MANUAL mode
//! 1 = Generate EG based on AHDSR values in voice structure
#define USGE_GENERATE_ENVELOPE 1

//! Update rate for fixed timing, as a fraction of 16777216 cycles
//! 0             = Derive timing from BufLen and RateHz
//! 280896        = VBlank timing
//! Can be any value, provided that updates are handled
//! at the specified nominal rate. There is no glitching
//! if this is not exact, only incorrect envelope timing.
#define USGE_FIXED_RATE 280896

//! Maximum number of voices
//! Maximum 38 voices for stereo, or 45 voices for mono.
//! Setting this to 8 voices or less has slight performance benefits.
#define USGE_MAX_VOICES 32

//! Fractional position accuracy
//! This is limited by our maximum Rate of 4.0, which requires 3
//! bits to store exactly, and Phase is 16 bits, giving us a
//! maximum accuracy of 13 bits.
#define USGE_FRACBITS 13

//! Threshold below which EG is considered to have stopped
//! Note that this is NOT used on manual envelopes!
//! Voices are cut once EG drops below 2^-USGE_EG_LOG2THRES.
#define USGE_EG_LOG2THRES 7

//! Log2 subdivision of mix buffer for volume ramping
#define USGE_VOLSUBDIV 3

/************************************************/

//! Sanity checks
#if (USGE_HWTIMER_IDX < 0 || USGE_HWTIMER_IDX > 1)
# error "USGE_HWTIMER_IDX must be 0 or 1."
#endif
#if (USGE_DMACHAN < 1 || USGE_DMACHAN > 2)
# error "USGE_DMACHAN must be 1 or 2."
#endif
#if (USGE_FIFOTARGET < 0 || USGE_FIFOTARGET > 1)
# error "USGE_FIFOTARGET must be 0 or 1."
#endif
#if (USGE_STEREOMIX < 0 || USGE_STEREOMIX > 1)
# error "USGE_STEREOMIX must be 0 or 1."
#endif
#if (USGE_MAX_VOICES < 1 || (USGE_STEREOMIX && USGE_MAX_VOICES > 38) || (!USGE_STEREOMIX && USGE_MAX_VOICES > 45))
# if USGE_STEREOMIX
#  error "USGE_MAX_VOICES must be >= 1 and <= 38."
# else
#  error "USGE_MAX_VOICES must be >= 1 and <= 45."
# endif
#endif
#if (USGE_FRACBITS < 11 || USGE_FRACBITS > 13)
# error "USGE_FRACBITS must be >= 11, and <= 13."
#endif
#if (USGE_EG_LOG2THRES > 16)
# error "USGE_EG_LOG2THRES must be <= 16."
#endif
#if (USGE_VOLSUBDIV > 4)
# error "USGE_VOLSUBDIV must be <= 4."
#endif

/************************************************/

//! Set size of each mixer voice entry
#if USGE_VOLSUBDIV
# if USGE_STEREOMIX
#  define USGE_VOXTABLE_ENTRY_SIZE 0x20
# else
#  define USGE_VOXTABLE_ENTRY_SIZE 0x1C
# endif
#else
# if USGE_STEREOMIX
#  define USGE_VOXTABLE_ENTRY_SIZE 0x18
# else
#  define USGE_VOXTABLE_ENTRY_SIZE 0x14
# endif
#endif

/************************************************/
//! EOF
/************************************************/
