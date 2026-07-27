// Tests/OklchUITests/HostedRenderer.swift
//
// Renders through a real view hierarchy, because ImageRenderer does not carry
// environment traits (pin P-ENV-1, measured in probes A2b/A2c/A2d).
// A characterization test built on ImageRenderer would report `.standard`
// contrast forever and pass while proving nothing.
import XCTest
import SwiftUI
@testable import OklchUI
import OklchCore

#if canImport(UIKit)
import UIKit
#endif

@available(iOS 17.0, macOS 14.0, *)
@MainActor
enum HostedRenderer {

    /// What `resolve(in:)` actually saw, captured from a hosted hierarchy.
    struct Observation: Sendable {
        var scheme: ColorScheme
        var contrast: ColorSchemeContrast
        var gamut: Gamut
        var resolved: Color.Resolved
    }

    /// A ShapeStyle that records the environment it is resolved in, then
    /// delegates to the style under test.
    struct Recording: ShapeStyle {
        final class Log: @unchecked Sendable {
            private let lock = NSLock()
            private var storage: [Observation] = []
            var observations: [Observation] {
                lock.lock(); defer { lock.unlock() }
                return storage
            }
            func append(_ o: Observation) {
                lock.lock(); defer { lock.unlock() }
                storage.append(o)
            }
        }

        let log: Log
        let inner: OklchStyle

        func resolve(in environment: EnvironmentValues) -> Color {
            let colour = inner.resolve(in: environment)
            log.append(Observation(
                scheme: environment.colorScheme,
                contrast: environment.colorSchemeContrast,
                gamut: environment.colorGamut,
                resolved: colour.resolve(in: environment)))
            return colour
        }
    }

    /// Renders `style` inside a real window and returns the first observation.
    /// `configure` applies environment overrides that ARE settable — note
    /// `colorSchemeContrast` is NOT among them (P-ENV-1).
    static func capture(
        _ style: OklchStyle,
        configure: (AnyView) -> AnyView = { $0 }
    ) throws -> Observation {
        #if canImport(UIKit)
        let log = Recording.Log()
        let base = AnyView(
            Rectangle()
                .fill(Recording(log: log, inner: style))
                .frame(width: 8, height: 8))

        let host = UIHostingController(rootView: configure(base))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        _ = renderer.image { ctx in window.layer.render(in: ctx.cgContext) }

        guard let first = log.observations.first else {
            // FAIL, do not skip: a hosted hierarchy that never calls
            // resolve(in:) IS the tier-5 regression this suite exists to
            // catch (ARCHITECTURE.md §5.5). Skipping here would let that regression go
            // green forever — the same failure shape fixed for FixtureLoader
            // in commit c46e9c3 ("fails hard instead of skipping").
            XCTFail("resolve(in:) was never invoked — the hierarchy did not draw")
            throw HierarchyDidNotDraw()
        }
        return first
        #else
        throw XCTSkip("hosted-hierarchy characterization is UIKit-only")
        #endif
    }

    /// Hosts an arbitrary view and forces one draw pass.
    @discardableResult
    static func hostAndDraw(_ view: AnyView) throws -> Bool {
        #if canImport(UIKit)
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 64, height: 64))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        _ = renderer.image { ctx in window.layer.render(in: ctx.cgContext) }
        return true
        #else
        throw XCTSkip("UIKit-only")
        #endif
    }
}

/// Thrown when a hosted hierarchy never invoked `resolve(in:)`. Paired with
/// an `XCTFail` at the throw site above — this type exists only to satisfy
/// `capture`'s `throws`, not to carry information; the failure message is
/// what XCTest reports.
struct HierarchyDidNotDraw: Error, CustomStringConvertible {
    var description: String {
        "resolve(in:) was never invoked — the hierarchy did not draw"
    }
}
