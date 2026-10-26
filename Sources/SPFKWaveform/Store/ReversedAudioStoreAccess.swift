// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-waveform

import Foundation

public protocol ReversedAudioStoreAccess: Sendable {
    /// The cached reversal if its source is unchanged, or nil. A stale entry is deleted.
    func fetchFreshReversedAudio(key: ReversedAudioKey) async throws -> ReversedAudioEntry?

    /// A path in the store's own volume to build into, so ``commitReversedAudio(key:from:frameCount:sampleRate:)``
    /// is a rename.
    func makeReversedAudioScratchURL() async throws -> URL

    /// Moves a finished build into place, stamped fresh against the source as it is now.
    func commitReversedAudio(key: ReversedAudioKey, from temporaryURL: URL, frameCount: Int, sampleRate: Double) async throws

    /// Re-stamps every entry for `url` after the app's own metadata write. See ``ReversedAudioStore/refreshFreshness(url:)``.
    func refreshReversedAudioFreshness(url: URL) async throws

    /// Moves every entry for a file that moved without its content changing.
    func rekeyReversedAudio(from oldURL: URL, to newURL: URL) async throws

    /// Removes every entry for `url`, across all of its tracks. Nothing cached is not an error.
    func deleteReversedAudio(for url: URL) async

    /// Removes every entry and any build left in scratch.
    func deleteAllReversedAudio() async
}
