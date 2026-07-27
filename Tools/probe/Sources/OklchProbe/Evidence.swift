// Tools/probe/Sources/OklchProbe/Evidence.swift
import Foundation

/// Emits one JSON line per measurement, prefixed so the shell wrapper can
/// grep it out of the surrounding xcodebuild noise.
public enum Evidence {
    public static func record(_ probe: String, _ payload: [String: Any]) {
        var full = payload
        full["probe"] = probe
        guard let data = try? JSONSerialization.data(
            withJSONObject: full, options: [.sortedKeys]
        ) else {
            print("EVIDENCE {\"probe\":\"\(probe)\",\"error\":\"unserializable\"}")
            return
        }
        print("EVIDENCE \(String(decoding: data, as: UTF8.self))")
    }
}
