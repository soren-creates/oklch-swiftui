// Tools/probe/Sources/OklchProbe/RecordingStyle.swift
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Records the environment every time SwiftUI resolves it.
@available(iOS 17.0, macOS 14.0, *)
public struct RecordingStyle: ShapeStyle {
    public final class Log: @unchecked Sendable {
        public private(set) var calls: [(contrast: ColorSchemeContrast, gamut: String)] = []
        private let lock = NSLock()
        public init() {}
        public func append(_ contrast: ColorSchemeContrast, _ gamut: String) {
            lock.lock(); defer { lock.unlock() }
            calls.append((contrast, gamut))
        }
    }

    let log: Log
    public init(log: Log) { self.log = log }

    public func resolve(in environment: EnvironmentValues) -> Color {
        log.append(environment.colorSchemeContrast, Self.currentGamut())
        return .blue
    }

    /// What UITraitCollection reports at the moment resolve runs.
    public static func currentGamut() -> String {
        #if canImport(UIKit)
        switch UITraitCollection.current.displayGamut {
        case .P3:      return "P3"
        case .SRGB:    return "sRGB"
        case .unspecified: return "unspecified"
        @unknown default:  return "unknown"
        }
        #else
        return "non-UIKit"
        #endif
    }
}
