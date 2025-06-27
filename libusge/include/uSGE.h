/************************************************/
#pragma once
/************************************************/

//! uSGE_Wav_t::Loop
#define USGE_WAV_MIN_LOOP 64 //! 8 loop iterations

//! uSGE_Vox_t::Stat
#define USGE_VOX_STAT_EG_ATK    0x00
#define USGE_VOX_STAT_EG_HLD    0x01
#define USGE_VOX_STAT_EG_DEC    0x02
#define USGE_VOX_STAT_EG_SUS    0x03
#define USGE_VOX_STAT_EG_MSK    0x03
#define USGE_VOX_STAT_EG_MANUAL 0x10
#define USGE_VOX_STAT_KEYOFF    0x20
#define USGE_VOX_STAT_KEYON     0x40
#define USGE_VOX_STAT_ACTIVE    0x80

//! uSGE_Driver_t::State
#define USGE_DRIVER_STATE_MAGIC   0x656773 //! "sge"
#define USGE_DRIVER_STATE_READY  (0x00 | USGE_DRIVER_STATE_MAGIC<<8)
#define USGE_DRIVER_STATE_PAUSED (0x80 | USGE_DRIVER_STATE_MAGIC<<8)
#define USGE_DRIVER_HEADER_SIZE   0x10
#define USGE_VOX_SIZE             0x18

/************************************************/
#ifndef __ASSEMBLER__
/************************************************/
#include <stdint.h>
/************************************************/
#ifdef __cplusplus
extern "C" {
#endif
/************************************************/

#define USGE_FORCE_INLINE  __attribute__((always_inline)) static inline
#define USGE_PACKED        __attribute__((packed))
#define USGE_ALIGNED       __attribute__((aligned(4)))
#define USGE_PTRALIGNED    __attribute__((aligned(__SIZEOF_POINTER__)))

/************************************************/

//! Waveform structure [08h + var bytes]
//! Notes:
//!  -Waveform data must be clipped to -127..+127 range if the
//!   mixer is not configured with USGE_CLIPMIXDOWN.
//!  -Waveform data must be extended by 8*MAX_RATE samples past
//!   the end of the array. This is for optimization in the mixer.
//!   MAX_RATE is currently 4.0.
//!  -One-shot samples must end with MIN_LOOP samples of silence,
//!   which must be included as part of the Size member. This
//!   allows the mixer to loop the silent section while mixing
//!   to avoid having to add special-case code.
struct USGE_ALIGNED USGE_PACKED uSGE_Wav_t {
	uint32_t Size;    //! [00h] Waveform length (in samples)
	uint32_t Loop;    //! [04h] Loop size (in samples; 0 = No loop)
	 int8_t  Data[0]; //! [08h] Sample data
};

//! Voice structure structure [18h bytes]
//! Notes:
//!  -Timings are companded in a square root format:
//!     Msecs = Value^2 * 1000/1626
//!   This allows higher accuracy for shorter envelopes, with a total range of
//!   0.0 .. 39.99 seconds
//!   This is a much cheaper approximation to a true logarithmic companding.
//!  -Attack envelope is linear, decay is exponential.
//!  -Using a manual envelope will skip all envelope processing, and will just
//!   use the value in the EG member as the envelope level.
//!  -VolR is only used with USGE_STEREOMIX; in mono mode, only VolL is used.
//!  -Using a volume above 100% is allowed, but may cause overflow issues.
//!  -To start playback:
//!    1) Write Vox.Stat = 0 (thread safety)
//!    2) Write to {VolL,VolR,AHDSR,Rate,Wav}
//!    3) Write Vox.Stat = USGE_VOX_STAT_ACTIVE | USGE_VOX_STAT_KEYON
//!  -To stop playback:
//!    a) Vox.Stat |= USGE_VOX_STAT_KEYOFF (not thread safe!)
//!    b) Vox.Stat = 0 (will stop output abruptly)
//!    Because ORing a value to Vox.Stat is not thread safe, interrupts should
//!    be disabled prior to modifying that value, or some other mechanism be
//!    used to ensure that the mixer is not running when this happens.
struct USGE_PTRALIGNED USGE_PACKED uSGE_Vox_t {
	uint8_t  Stat;    //! [00h] Channel status
	uint8_t  VolL;    //! [01h] Playback volume (80h = 100%; left channel)
	uint8_t  VolR;    //! [02h] Playback volume (80h = 100%; right channel)
	uint8_t  Attack;  //! [03h] Attack time
	uint8_t  Hold;    //! [04h] Hold time
	uint8_t  Decay;   //! [05h] Decay time
	uint8_t  Sustain; //! [06h] Sustain level (FFh = 100%)
	uint8_t  Release; //! [07h] Release time
	uint16_t Rate;    //! [08h] Playback rate (in USGE_FRACBITS precision)
	uint16_t Offs;    //! [0Ah] Playback phase
	uint16_t EG;      //! [0Ch] Envelope value
	uint8_t  OldVolL; //! [0Eh] Volume at last update (left channel)
	uint8_t  OldVolR; //! [0Fh] Volume at last update (right channel)
	const int8_t            *Data; //! [10h] Sample data source
	const struct uSGE_Wav_t *Wav;  //! [14h] Linked waveform
};

//! Driver structure [10h + 18h*VoxCnt + (1+USGE_STEREOMIX)*BfCnt*BufLen bytes]
//! Immediately following the voices are the output buffers.
//! Notes:
//!  -EnvMul = BufLen * 1626 * 2^16 / RateHz
//!   This is only used when USGE_FIXED_RATE is disabled.
struct USGE_PTRALIGNED USGE_PACKED uSGE_Driver_t {
	uint32_t State;  //! [00h] Driver state flags
	uint8_t  BfIdxR; //! [04h] Buffer index (currently playing)
	uint8_t  BfCnt;  //! [05h] Buffer count
	uint8_t  VoxCnt; //! [06h] Voice count
	uint8_t  BfIdxW; //! [07h] Buffer index (next update)
	uint16_t RateHz; //! [08h] Sampling rate (in Hz)
	uint16_t BufLen; //! [0Ah] Length of each buffer (in samples)
	uint32_t EnvMul; //! [0Ch] Envelope scaling constant
	struct uSGE_Vox_t Vox[0];
};
USGE_FORCE_INLINE
int8_t *uSGE_GetOutputBuffers(struct uSGE_Driver_t *Driver) {
	return (int8_t*)(Driver->Vox + Driver->VoxCnt);
}

/************************************************/

//! uSGE_Driver_GetWorkAreaSize(VoxCnt, BufCnt, BufLen)
//! Description: Get size of uSGE_Driver_t structure for given parameters.
//! Arguments:
//!   VoxCnt: Number of voices.
//!   BufCnt: Number of output buffers.
//!   BufLen: Length of each buffer.
//! Returns: Size in bytes of a uSGE_Driver_t structure to suit the parameters.
//! Notes:
//!  -Returns 0 if the requested parameters cannot form a valid driver.
uint32_t uSGE_Driver_GetWorkAreaSize(uint8_t VoxCnt, uint8_t BufCnt, uint16_t BufLen);

/************************************************/

//! uSGE_Driver_Open(Driver, VoxCnt, RateHz, BufCnt, BufLen)
//! Description: Initialize SGE driver.
//! Arguments:
//!   Driver: Driver work area.
//!   VoxCnt: Number of voices.
//!   RateHz: Sampling rate (in Hz).
//!   BufCnt: Number of output buffers.
//!   BufLen: Number of samples per buffer.
//! Returns: On success, returns a non-zero value. On failure, returns 0.
//! Notes:
//!  -BufLen must be a multiple of 8.
//!  -BufCnt must be between 2 and 255.
//!  -BufLen*BufCnt must be a multiple of 16.
//!  -This routine automatically enables the audio hardware.
//!  -The driver takes over DMA channels 1+2 and a timer (see USGE_HWTIMER_IDX).
//!  -It is only possible to have one driver open at any time. Multiple drivers
//!   can be initialized, but only one can be active at any given time.
uint32_t uSGE_Driver_Open(
	struct uSGE_Driver_t *Driver,
	uint8_t  VoxCnt,
	uint16_t RateHz,
	uint8_t  BufCnt,
	uint16_t BufLen
);

//! uSGE_Driver_Sync(Driver)
//! Description: Synchronize hardware playback.
//! Arguments:
//!   Driver: Driver work area.
//! Returns: Nothing; playback synchronized.
//! Notes:
//!  -Because the GBA doesn't loop sound buffers automatically, this function
//!   is needed to reset the DMA stream upon reaching the end of buffer.
//!  -Timing of this function is EXTREMELY critical (leeway of 1596 cycles
//!   for 10512Hz, down to 399 cycles for 42048Hz). It is not so much /when/
//!   this function is called that matters, but rather the consistency of
//!   the timing. For best results, it should work best to call this function
//!   as soon as the interrupt handler passes control to the user function,
//!   as this should have guaranteed consistent timing.
void uSGE_Driver_Sync(struct uSGE_Driver_t *Driver);

//! uSGE_Driver_Update(Driver)
//! Description: Update driver state.
//! Arguments:
//!   Driver: Driver work area.
//! Returns: Nothing; driver state updated and audio mixed to output.
//! Notes:
//!  -This routine handles voice mixing, so may take a long time to finish.
//!   The recommended usage is to call uSGE_Driver_Sync(), then this function
//!   after, inside an interrupt (VBlank or slave timer).
//!  -This function is NOT thread safe, as self-modifying code will be used.
void uSGE_Driver_Update(struct uSGE_Driver_t *Driver);

//! uSGE_Driver_Pause(Driver)
//! Description: Pause playback of driver.
//! Arguments:
//!   Driver: Driver work area.
//! Returns: Nothing; driver state paused.
//! Notes:
//!  -This function stops DMA transfer and disables the hardware timer.
//!  -This routine does NOT disable the sound hardware.
//!  -Once this function is called, the driver area may be deleted if it is no
//!   longer needed.
void uSGE_Driver_Pause(struct uSGE_Driver_t *Driver);

//! uSGE_Driver_Resume(Driver)
//! Description: Resume paused driver.
//! Arguments:
//!   Driver: Driver work area.
//! Returns: Nothing; driver is hooked back into the hardware.
//! Notes:
//!  -Calling this function will once again take over DMA1+2 and a timer.
void uSGE_Driver_Resume(struct uSGE_Driver_t *Driver);

/************************************************/

//! uSGE_Exp2fxp(x)
//! Description: Base-2 exponentiation 2^x.
//! Arguments:
//!   x: Exponent (in 5.27fxp).
//! Returns: 2^x.
//! Notes:
//!  -This routine is only approximate.
uint32_t uSGE_Exp2fxp(uint32_t x);

/************************************************/
#ifdef __cplusplus
}
#endif
/************************************************/
#endif
/************************************************/
//! EOF
/************************************************/
