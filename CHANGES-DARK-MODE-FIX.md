# Change: Dark Mode Support for HypertensionGraphView

## Summary

Fixed the hypertension classification graph to render correctly in both light and dark mode. Previously, zone borders, zone text labels, and the plot point were hardcoded to `Color.black`, making them invisible when the user has dark mode enabled on their iOS device.

## Problem

In `HypertensionGraphView.swift`, several visual elements used hardcoded black colors:

- **Zone borders** (4 instances): `.stroke(Color.black, lineWidth: 2)` — invisible on dark backgrounds
- **Zone text labels** (5 instances): `.foregroundStyle(.black)` — invisible on dark backgrounds
- **Plot point fill**: `.fill(.black)` — invisible on dark backgrounds
- **Plot point border**: `.strokeBorder(.white, lineWidth: 3.5)` — low contrast on light backgrounds in some contexts
- **Plot point shadow**: `.shadow(color: .black.opacity(0.5), ...)` — invisible shadow on dark backgrounds

All axis labels (diastolic/systolic tick values and axis titles) already correctly used `.foregroundStyle(.secondary)`, which adapts to the color scheme automatically.

## Fix

Replaced all hardcoded colors with adaptive equivalents:

| Element | Before | After | Reason |
|---------|--------|-------|--------|
| Zone border strokes (x4) | `Color.black` | `Color.primary` | Adapts: black in light mode, white in dark mode |
| Zone text labels (x5) | `.foregroundStyle(.black)` | `.foregroundStyle(.primary)` | Same adaptive behavior |
| Plot point fill | `.fill(.black)` | `.fill(Color.primary)` | Visible in both modes |
| Plot point border | `.strokeBorder(.white, ...)` | `.strokeBorder(Color(UIColor.systemBackground), ...)` | Contrasts with primary in both modes |
| Plot point shadow | `.black.opacity(0.5)` | `Color.primary.opacity(0.5)` | Visible shadow in both modes |

`Color.primary` is a SwiftUI system color that automatically resolves to black in light mode and white in dark mode. `UIColor.systemBackground` resolves to white in light mode and black in dark mode, providing the opposite contrast for the plot point border.

## Files Changed

- `App/HypertensionGraphView.swift` — 14 color value replacements across zone borders, zone labels, and plot point

## Testing

1. **Light mode**: Graph should look identical to before (primary = black, systemBackground = white)
2. **Dark mode**: Zone borders, labels, and plot point should now be visible (primary = white, systemBackground = black)
3. **Zone colors**: The colored zone fills (red, pink, orange, green, cyan) are unaffected and provide sufficient contrast in both modes
4. **Preview**: The `#Preview` block can be tested in Xcode with both color scheme settings

## Compatibility

- No API changes — `Color.primary` and `UIColor.systemBackground` are available in iOS 13+
- No behavior changes in light mode — the visual output is identical to the previous version
- No new dependencies

## Related

- This fix was identified as part of a broader contribution effort. See the accompanying `CONTRIBUTING.md` for contribution guidelines.
