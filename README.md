# uSGE

Bare-bones (no music playback implemented), highly optimized audio driver for GBA.

Some ideas are borrowed from my SGE project, but mostly I just suck at naming things so I came up with "micro SGE" (just pretend it's a Greek lowercase m).

The idea is to use this as the synthesizer for a music playback system.

## Features

* Self-modifying mixing loops and mixing inside registers for extreme performance
  * ~2.5% CPU per voice @ 31536Hz using default waitstates (stereo, with 1/8 dynamic subdividing volume ramping)
    * ~2.2% CPU per voice in mono mode, with all else being equal
* Highly-customizable build options (mono/stereo output, maximum voice count, etc.)
* AHDSR envelope generator
  * Can be overriden in "manual" mode if desired
* Volume ramping (by slicing a mix chunk into 2^N pieces or less, as needed)

## Limitations/Caveats/Notes

* Waveform loops should be at least 64 samples long to avoid excessive looping overhead
  * This isn't actually a hard limitation, but is very strongly recommended.
* Waveforms must be padded with 32 samples past the end of the loop
  * Looped samples should be padded with loop data, one-shot samples should be padded with silence.
* Playback rate precision is 14 bits at most (see `USGE_FRACBITS` in uSGE_Config.h), and maximum playback rate is 4.0
  * When using 14-bit precision, playback rate is capped at 4.0-2^-14 (ie. FFFFh * 2^-14).
* No support for interpolation
* The simple example code requires libgba for building

## Authors
* **Ruben Nunez** - *Initial work* - [Aikku93](https://github.com/Aikku93)

## Acknowledgements

The idea of a sound mixer that mixes samples in registers instead of a buffer was inspired by the excellent AAS module player. I just decided to go further and make a more general driver.
