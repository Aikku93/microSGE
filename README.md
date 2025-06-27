# uSGE

Bare-bones (no music playback implemented), highly optimized audio driver for GBA.

Some ideas are borrowed from my SGE project, but mostly I just suck at naming things so I came up with "micro SGE" (just pretend it's a Greek lowercase m).

The idea is to use this as the synthesizer for a music playback system.

## Features

* Self-modifying mixing loops and mixing inside registers for extreme performance
  * ~2.6% CPU per voice @ 31536Hz using default waitstates (stereo, with 1/8 subdividing volume ramping)
* Highly-customizable build options (mono/stereo output, maximum voice count, etc.)
* AHDSR envelope generator
  * Can be overriden in "manual" mode if desired
* Volume ramping (by slicing a mix chunk into 2^N pieces or less, as needed)

## Limitations/Caveats/Notes

* Waveform loops must be at least 64 samples long
  * This isn't actually a hard limitation, but is very strongly recommended. This *is* enforced for one-shot samples, though (see the next point)
* Waveforms must be padded with 32 samples past the end of the loop
  * One-shot waveforms must be padded with 96 samples of silence (a 64-sample loop, plus 32 samples of silence)
* Playback rate precision is 13 bits only, and maximum playback rate is 4.0
* No support for interpolation
* The simple example code requires libgba for building

## Authors
* **Ruben Nunez** - *Initial work* - [Aikku93](https://github.com/Aikku93)

## Acknowledgements

The idea of a sound mixer that mixes samples in registers instead of a buffer was inspired by the excellent AAS module player. I just decided to go further and make a more general driver.
