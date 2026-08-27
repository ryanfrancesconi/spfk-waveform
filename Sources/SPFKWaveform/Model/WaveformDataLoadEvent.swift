// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-waveform

import Foundation
import SPFKBase

public typealias WaveformDataLoadEventHandler = @Sendable (WaveformDataLoadEvent) async -> Void

public enum WaveformDataLoadEvent: Sendable {
    case progress(url: URL, value: UnitInterval)
    case complete(url: URL, value: WaveformData)

    public var progress: UnitInterval {
        switch self {
        case let .progress(url: _, value: value):
            value

        case .complete:
            1
        }
    }
}
