// Tools/probe/compile/A2a_ContrastSettable.swift
// A2a: Is \.colorSchemeContrast settable via .environment(_:_:)?
// If EnvironmentValues.colorSchemeContrast is get-only, this fails to compile.
import SwiftUI

@available(macOS 14.0, iOS 17.0, *)
func probeA2a() -> some View {
    EmptyView().environment(\.colorSchemeContrast, .increased)
}
