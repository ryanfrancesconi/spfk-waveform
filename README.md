# SPFKWaveform

[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-waveform)](https://github.com/ryanfrancesconi/spfk-waveform/tags)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-waveform%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-waveform)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-waveform%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-waveform)

The capability between an audio file and a drawn waveform: scanning audio into peak data, caching
the result on disk, and rasterizing peaks into images. It imports no AppKit and no Metal, so the
drawing layer above it can be either. spfk-audio-ui draws ShadowTag's waveforms from it.

Scanning reads a file through AVFoundation, or decoded audio from any `SequentialPCMSource` for
containers AVFoundation cannot open, and both produce the same `WaveformData`. The cache is sharded
on disk, keyed by file and audio track, and treats an entry as stale once the file's modification
date or size changes. The package also caches reversed copies of audio files for reversed playback,
under the same freshness rules.

Decoding containers belongs to spfk-audio-conversion and spfk-matroska, building reversed audio to
spfk-audio-conversion, and drawing on screen to spfk-audio-ui.

## Freshness

A cached waveform is invalidated by its file's modification date. After writing metadata to a file,
refresh the cache's freshness for it, or the app's own write discards a waveform that is still
correct.

## About

Spongefork is the personal software projects of musician and developer [Ryan Francesconi](https://spongefork.com). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2026, Spongefork returns as his software container for more musical experimentation. In addition to [software releases](https://spongefork.com/shadowtag/), open source components can be found on his [GitHub page](https://github.com/ryanfrancesconi).
