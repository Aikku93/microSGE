/************************************************/
#include <stdint.h>
#include <stdio.h>
#include <gba_base.h>
#include <gba_console.h>
#include <gba_input.h>
#include <gba_interrupt.h>
#include <gba_systemcalls.h>
#include <gba_timers.h>
/************************************************/
#include "uSGE.h"
#include "uSGE_Config.h"
#include "TinesPiano_bin.h"
/************************************************/

#define SAMPRATE_HZ 31536
#define N_VOICES    16
#define NBUFFERS    2
#define BUFLENGTH   528

/************************************************/

//! Use uSGE_Driver_GetWorkAreaSize() to get this area size!
uint8_t DriverArea[2512] EWRAM_BSS ALIGN(4);
static inline struct uSGE_Driver_t *GetDriver(void) {
	return (struct uSGE_Driver_t*)DriverArea;
}

/************************************************/

static uint32_t GetDriverSize(void) {
	return uSGE_Driver_GetWorkAreaSize(N_VOICES, NBUFFERS, BUFLENGTH);
}

static int OpenDriver(void) {
	uint32_t Result = uSGE_Driver_Open(GetDriver(), N_VOICES, SAMPRATE_HZ, NBUFFERS, BUFLENGTH);
	return (Result != 0);
}

static void SyncDriver(void) {
	uSGE_Driver_Sync(GetDriver());
}

static void UpdateDriver(void) {
	uSGE_Driver_Update(GetDriver());
}

static void PauseDriver(void) {
	uSGE_Driver_Pause(GetDriver());
}

static void ResumeDriver(void) {
	uSGE_Driver_Resume(GetDriver());
}

static void PlayEffect(uint32_t VoxIdx, uint32_t Rate, uint32_t Pan) {
	struct uSGE_Vox_t *Vox = &GetDriver()->Vox[VoxIdx];
	Vox->Stat    = 0;
	Vox->VolL    = 128 * (128-Pan) >> 7;
	Vox->VolR    = 128 * (    Pan) >> 7;
	Vox->Attack  = 0;
	Vox->Hold    = 55;  //! Approx 2.0 seconds
	Vox->Decay   = 180; //! Approx 20.0 seconds
	Vox->Sustain = 0;
	Vox->Release = 25;  //! Approx 1.0 seconds
	Vox->Rate    = Rate;
	Vox->Wav     = (const struct uSGE_Wav_t*)TinesPiano_bin;
	Vox->Stat    = USGE_VOX_STAT_ACTIVE | USGE_VOX_STAT_KEYON;
}

static void KeyOffVoice(uint32_t VoxIdx) {
	struct uSGE_Vox_t *Vox = &GetDriver()->Vox[VoxIdx];
	uint32_t OldIME = REG_IME;
	REG_IME = 0;
		Vox->Stat |= USGE_VOX_STAT_KEYOFF;
	REG_IME = OldIME;
}

/************************************************/

static uint32_t DriverUsage = 0;
static uint32_t DriverVBlankCounts = 0;
static void VBlankFunc(void) {
	SyncDriver();

	//! VBlank-critical stuff goes here...

	REG_TM3CNT_H = 0;
	REG_TM3CNT_L = 0;
	REG_TM3CNT_H = TIMER_START | 1; //! 1/64 timing
	UpdateDriver();
	DriverUsage += REG_TM3CNT_L*64;
	DriverVBlankCounts++;
}

/************************************************/

int main(void) {
	irqInit();
	irqSet(IRQ_VBLANK, VBlankFunc);
	irqEnable(IRQ_VBLANK);
	consoleDemoInit();

	//! Verify driver size
	uint32_t ActualDriverSize = GetDriverSize();
	if(sizeof(DriverArea) != ActualDriverSize) {
		iprintf("Driver size incorrect.\nShould be %lu bytes.", ActualDriverSize);
		for(;;) VBlankIntrWait();
	}

	//! Initialize driver
	if(!OpenDriver()) {
		iprintf("Unable to open driver x_x");
		for(;;) VBlankIntrWait();
	}

	//! Enter main loop
	iprintf(
		"uSGE Driver Demo\n"
		"\n"
		"A = Play Sound\n"
		"B = Stop Sound\n"
		"\n"
		"Sel+A = Resume Driver\n"
		"Sel+B = Pause Driver\n"
		"Start = Exit\n"
		"\n"
	);
	uint32_t PlayIdx = 0;
	uint32_t VoxIdx = 0;
	for(;;) {
		VBlankIntrWait();
		scanKeys();

		//! Update CPU usage every 0.25 seconds or so
		if(DriverVBlankCounts >= 15) {
			uint32_t OldIME = REG_IME;
			REG_IME = 0;
				uint32_t CPUUse = (uint32_t)(DriverUsage * 10000ull / (280896ull*DriverVBlankCounts));
				iprintf(CON_POS(0,9) "CPU Usage: %2lu.%02lu%%", CPUUse/100, CPUUse%100);
				DriverUsage = 0;
				DriverVBlankCounts = 0;
			REG_IME = OldIME;
		}

		int KeysHeld   = keysHeld();
		int KeysTapped = keysDown();
		if(KeysTapped & KEY_A) {
			if(KeysHeld & KEY_SELECT) {
				ResumeDriver();
			} else {
				static const uint8_t Pans[] = {
					112,
					80,
					48,
					16,
				};
				static const uint16_t Rates[] = {
					(uint16_t)(2.0000 * 32000 / SAMPRATE_HZ * (1 << USGE_FRACBITS)),
					(uint16_t)(1.4983 * 32000 / SAMPRATE_HZ * (1 << USGE_FRACBITS)),
					(uint16_t)(1.2599 * 32000 / SAMPRATE_HZ * (1 << USGE_FRACBITS)),
					(uint16_t)(1.0000 * 32000 / SAMPRATE_HZ * (1 << USGE_FRACBITS)),
				};
				PlayEffect(VoxIdx, Rates[PlayIdx], Pans[PlayIdx]);

				if(++PlayIdx >= 4) PlayIdx = 0;
				if(++VoxIdx >= N_VOICES) VoxIdx = 0;
			}
		} else if(KeysTapped & KEY_B) {
			if(KeysHeld & KEY_SELECT) {
				PauseDriver();
			} else {
				uint32_t i;
				for(i=0;i<N_VOICES;i++) KeyOffVoice(i);
			}
		} else if(KeysTapped & KEY_START) {
			break;
		}
	}

	//! Close driver by pausing it
	PauseDriver();

	//! Do we even need to return anything?
	return 0;
}

/************************************************/
//! EOF
/************************************************/
