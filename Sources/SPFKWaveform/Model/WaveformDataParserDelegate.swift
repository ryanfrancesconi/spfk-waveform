// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-waveform

import Foundation

public protocol WaveformDataParserDelegate: AnyObject, Sendable {
    func waveformDataParser(event: WaveformDataLoadEvent) async
}
