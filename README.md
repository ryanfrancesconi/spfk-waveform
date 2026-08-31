# SPFKWaveform

[![Version](https://img.shields.io/github/v/tag/ryanfrancesconi/spfk-waveform)](https://github.com/ryanfrancesconi/spfk-waveform/tags)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-waveform%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/ryanfrancesconi/spfk-waveform)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fryanfrancesconi%2Fspfk-waveform%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/ryanfrancesconi/spfk-waveform)

Peak-data waveform scanning, caching and rasterization for Swift.

The package covers everything between an audio file and the pixels a waveform is drawn from, and
nothing above it: `WaveformDataParser` reduces audio to per-chunk peaks, `WaveformDataStore`
persists the result to a sharded on-disk cache, and `WaveformImage` rasterizes peaks into a
`CGImage`. It imports no AppKit and no Metal, so the drawing layer above it is free to be either.

## Scanning

`WaveformDataParser` reduces a file to one array of peaks per channel, reporting the samples per
point, duration and sample rate alongside them.

`WaveformDrawingResolution` is an enum — `.low` through `.lossless`, 128 down to 1 samples per
point — and can also be initialized from a `samplesPerPoint` count or from a duration, which picks a
preset appropriate to the file's length. Pass an `eventHandler` to the parser to receive
`.progress` and `.complete` events during a long scan.

For containers `AVAudioFile` cannot open — Matroska is the one users hit — scan from a
`SequentialPCMSource` (declared in `SPFKBase`) instead, supplying the duration from the container's
own header, since a streamed source generally knows it without having read to the end.

Both entry points return the same `WaveformData`; nothing downstream can tell which produced it.

## Caching

The cache is keyed by file **and** audio track, because a container offering several tracks has a
waveform per track and a lookup by URL alone answers with whichever was scanned first. `fetchIfFresh`
checks the entry against the file's modification date and size, deletes a stale record rather than
returning it, and treats an unreadable entry as a miss — this is a derived cache, so a bad header
costs one re-scan instead of failing the load. After writing metadata to a file, call
`refreshFreshness(url:)` so the app's own modification-date bump does not invalidate an otherwise
valid waveform; it refreshes every track's entry at once.

Files are laid out under `<inDirectory>/Data/Waveform/<shard>/`, sharded by the first two hex digits
of the URL's SHA-256. `FlatToShardedMigration.waveform(inCachesDirectory:)` migrates a legacy flat
directory in a resumable background sweep.

`WaveformDataStoreAccess` is the protocol an app conforms to in order to vend the store to its UI
layer without handing over the store itself.

## Rasterizing

`createImages` returns one `CGImage` per channel; `createImage` renders a single channel. The
renderer reuses one bitmap context across calls, so repeated draws at the same size do not
reallocate.

## Installation

```swift
.package(url: "https://github.com/ryanfrancesconi/spfk-waveform", from: "1.0.0"),
```

## Requirements

- **Platforms:** macOS 13+, iOS 16+
- **Swift:** 6.2+

## About

Spongefork is the personal software projects of musician and developer [Ryan Francesconi](https://spongefork.com). Dedicated to creative sound manipulation, his first application, Spongefork, was released in 1999 for macOS 8. From 2026, Spongefork returns as his software container for more musical experimentation. In addition to [software releases](https://spongefork.com/shadowtag/), open source components can be found on his [GitHub page](https://github.com/ryanfrancesconi).
