# SPFKWaveform

[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-waveform)](https://github.com/ryanfrancesconi/spfk-waveform/tags)
[![Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-waveform%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-waveform)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-waveform%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-waveform)

Waveform data for audio files: scanning audio into peaks, caching the result on disk, and rendering
peaks to images. It does not import AppKit or Metal.

## Features

- Scan a file through AVFoundation, or decoded audio from any `SequentialPCMSource`, into
  `WaveformData`
- A sharded disk cache keyed by file and audio track, with entries treated as stale once the file's
  modification date or size changes (`refreshFreshness(urls:)` updates them after a metadata write)
- A cache of reversed copies of audio files, under the same freshness rules
- Rendering of peaks to images (`WaveformImage`)

## About

Spongefork is the personal software projects of musician and developer [Ryan Francesconi](https://spongefork.com). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2026, Spongefork returns as his software container for more musical experimentation. In addition to [software releases](https://spongefork.com/shadowtag/), open source components can be found on his [GitHub page](https://github.com/ryanfrancesconi).
