# ``OklchUI``

OKLCH colour for SwiftUI that resolves late — against the real display gamut,
colour scheme, contrast setting and ambient background.

## Overview

Every OKLCH library for Swift converts to RGB eagerly, when you construct the
colour. At that moment none of the things that determine the right answer are
knowable: the destination gamut is a property of the display, the colour scheme
and Increase Contrast setting belong to the user, and the background the colour
will sit on has not been drawn yet.

``OklchStyle`` stays in OKLCH until SwiftUI calls `resolve(in:)`, then reads
exactly three environment values and produces a `Color` tagged in the matching
space. That "exactly three" claim holds fully for a fixed-variant style; a
style created by `contrasting(_:hue:chroma:preferring:against:)` also reads
`\.themeBackground` and writes to `\.oklchDiagnostics`.

## Topics

### Colours
- ``OklchStyle``
- ``Backdrop``

### Environment
- ``SwiftUICore/EnvironmentValues/colorGamut``
- ``SwiftUICore/EnvironmentValues/themeBackground``
- ``SwiftUICore/EnvironmentValues/oklchDiagnostics``

### Modifiers
- ``SwiftUICore/View/oklchBackground(_:)``
- ``SwiftUICore/View/colorGamut(_:)``
- ``SwiftUICore/View/oklchDiagnostics(_:)``

### Articles
- <doc:GettingStarted>
