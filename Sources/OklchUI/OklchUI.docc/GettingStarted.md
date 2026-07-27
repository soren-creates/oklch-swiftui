# Getting Started

## A colour that adapts

```swift
Rectangle().fill(
    OklchStyle(Oklch(lightness: 0.55, chroma: 0.12, hue: 250))
        .dark(Oklch(lightness: 0.85, chroma: 0.09, hue: 250))
)
```

In light mode this resolves the base colour; in dark mode, the dark variant.
Neither is converted to RGB until SwiftUI asks.

## Text that meets a contrast target

```swift
VStack { Text("Readable") }
    .foregroundStyle(OklchStyle.contrasting(.wcag(4.5), hue: 250, chroma: 0.1))
    .oklchBackground(OklchStyle(Oklch(lightness: 1, chroma: 0, hue: 0)))
```

`oklchBackground` both draws the background and publishes it, so `contrasting`
solves against the colour actually on screen.

Against white, `.wcag(4.5)` at hue 250 and chroma 0.1 resolves to a lightness
of approximately `0.57`.

<!-- verified-by: testGettingStartedContrastingLightnessClaim -->

## When a target cannot be met

APCA Lc 120 against mid-grey has no solution at any lightness. Rather than
crash or silently miss, the solve returns the best achievable colour and
reports the shortfall:

```swift
.oklchDiagnostics { resolution in
    print("wanted \(resolution.requested), got \(resolution.achieved)")
}
```

<!-- verified-by: testGettingStartedUnreachableClaim -->
