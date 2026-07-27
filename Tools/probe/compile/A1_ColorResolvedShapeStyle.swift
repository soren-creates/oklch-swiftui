// Tools/probe/compile/A1_ColorResolvedShapeStyle.swift
// A1: Does Color.Resolved conform to ShapeStyle?
// This file is a PROBE: it is compiled with `swiftc -typecheck`, never run.
// If it compiles, the conformance exists. If it fails, it does not.
import SwiftUI

func requireShapeStyle<S: ShapeStyle>(_: S.Type) {}

@available(macOS 14.0, iOS 17.0, *)
func probeA1() {
    requireShapeStyle(Color.Resolved.self)
}
