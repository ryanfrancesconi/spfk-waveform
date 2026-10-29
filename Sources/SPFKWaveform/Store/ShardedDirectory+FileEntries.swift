// Copyright Ryan Francesconi. All Rights Reserved. Revision History at https://github.com/ryanfrancesconi/spfk-waveform

import Foundation
import SPFKBase
import SPFKUtils

extension ShardedDirectory {
    /// Every entry belonging to one of `urls`, paired with its file, listing each shard once.
    ///
    /// A file's entries are keyed by its hash alone or by its hash, `-`, and a per-track suffix,
    /// so all of them share the hash's shard.
    func entryKeys(suffix: String, forFilesAt urls: Set<URL>) -> [(key: String, url: URL)] {
        let urlsByFileKey = Dictionary(urls.map { ($0.sha256, $0) }, uniquingKeysWith: { first, _ in first })
        let fileKeysByShard = Dictionary(grouping: urlsByFileKey.keys) { $0.prefix(2) }

        var result: [(key: String, url: URL)] = []

        for fileKeys in fileKeysByShard.values {
            guard let anyKey = fileKeys.first else { continue }

            for key in entryKeys(suffix: suffix, inShardOf: anyKey) {
                let fileKey = key.firstIndex(of: "-").map { String(key[..<$0]) } ?? key

                if let url = urlsByFileKey[fileKey] {
                    result.append((key, url))
                }
            }
        }

        return result
    }
}
