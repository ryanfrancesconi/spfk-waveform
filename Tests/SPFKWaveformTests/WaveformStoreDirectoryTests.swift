// Copyright Ryan Francesconi. All Rights Reserved.

import Foundation
import SPFKBase
import SPFKTesting
import Testing

@testable import SPFKWaveform

/// A file where a store's directory goes would leave the store writing nowhere, so building it
/// has to fail.
@Suite(.tags(.file))
final class WaveformStoreDirectoryTests: BinTestCase {
    private func plantFile(named name: String) throws {
        let data = bin.appendingPathComponent("Data", isDirectory: true)
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        try Data("not a directory".utf8).write(to: data.appendingPathComponent(name))
    }

    @Test func aFileWhereTheWaveformStoreGoesFailsTheStore() throws {
        try plantFile(named: "Waveform")

        #expect(throws: (any Error).self) {
            _ = try WaveformDataStore(inDirectory: self.bin)
        }
    }

    @Test func aFileWhereTheReversedStoreGoesFailsTheStore() throws {
        try plantFile(named: "Reversed")

        #expect(throws: (any Error).self) {
            _ = try ReversedAudioStore(inDirectory: self.bin)
        }
    }
}
