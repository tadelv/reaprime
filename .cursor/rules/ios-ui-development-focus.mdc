---
description: "UI/UX and SwiftUI best practices - HIG compliance, presentation APIs, layout patterns"
globs: ["**/*.swift"]
alwaysApply: false
---
# UI Development Standards

**CRITICAL: All UI and UX development must follow these standards**

## 🛑 ZERO TOLERANCE: UI Anti-Patterns

1. **Custom Sheets/Overlays:**
   - ❌ NEVER build custom `ZStack` overlays for modals.
   - ✅ ALWAYS use `.sheet(item:)` with `.presentationDetents()`.
   - *Reason:* Custom overlays break keyboard handling and accessibility.

2. **"Sleep" Logic:**
   - ❌ NEVER use `Task.sleep` to wait for data/player readiness.
   - ✅ ALWAYS use `await`, `AsyncStream`, or Combine publishers.

3. **Text Blend Modes on Materials:**
   - ❌ NEVER use `.blendMode(.overlay)` or other blend modes for text on translucent materials
   - ✅ ALWAYS use semantic foreground styles: `.foregroundStyle(.primary)` or `.foregroundStyle(.secondary)`
   - ✅ ALWAYS use `.liquidText()` modifier which implements semantic vibrancy correctly
   - *Reason:* HIG requires semantic vibrancy for text on materials. Blend modes create unpredictable contrast and violate WCAG accessibility standards.

## UI Development Guidelines

**CRITICAL: All UI and UX features MUST follow Apple's Human Interface Guidelines (HIG) and Liquid Glass design system**

- Always consult Apple HIG documentation (locally indexed) for component usage, design patterns, and accessibility requirements
- Integrate **current Apple design materials** (e.g. Liquid Glass per HIG) for new components **when available on the project's deployment target**; verify API names and availability in Apple docs for the SDK in use

## Liquid Glass Design System (project + SDK)

**CRITICAL: New UI must follow Apple's Human Interface Guidelines and current materials documentation (e.g. Liquid Glass where applicable).**

### Implementation Requirements

- **Mandatory Usage (when supported):** Use Liquid Glass (or successor) materials for new components when the **project's minimum deployment target and SDK** support them—use `#available` / project design-system wrappers when supporting multiple OS versions.
- **Materials:** Use Apple's documented APIs for the active SDK; leverage customization options (clear, tinted, dark appearances) as documented.
- **Accessibility:** Test for readability, verify VoiceOver/Dynamic Type support, ensure WCAG contrast ratios
- **Reference:** Always consult <https://developer.apple.com/documentation/technologyoverviews/liquid-glass> and HIG for the SDK you build with.

### Liquid Glass Implementation Signature

Modifier names and parameters are **SDK-specific**. When the project provides wrappers (e.g. `Core/UI/DesignSystem/LiquidGlass.swift`), use those consistently—**do not invent modifiers.** Example shapes only (verify against docs and project code):

- **Modifier (example):** `.liquidGlass(material: .thick, refraction: 0.8)`
- **Background (example):** `.background(.liquidMaterial(.sidebar))`

### When to Use Liquid Glass

- ✅ **DO use Liquid Glass for:**
  - All buttons and interactive controls
  - Navigation bars, tab bars, and sidebars
  - Cards and containers that overlay content
  - Media controls and playback interfaces
  - App icons and widget backgrounds
  - Modal presentations and sheets
  - Any translucent UI element

- ❌ **DON'T use Liquid Glass for:**
  - Solid backgrounds that need full opacity
  - Text content (use appropriate text styles instead)
  - When it compromises readability or accessibility
  - When it conflicts with specific design requirements

### Text Legibility on Liquid Glass Materials

**CRITICAL HIG Requirement:** Text on translucent materials must use semantic foreground styles, not blend modes.

- ✅ **REQUIRED:** Use `.foregroundStyle(.primary)` or `.foregroundStyle(.secondary)` - uses Apple's vibrancy system optimized for materials
- ✅ **REQUIRED:** The `.liquidText()` modifier must implement semantic vibrancy (not blend modes)
- ❌ **FORBIDDEN:** `.blendMode(.overlay)` on text (causes unpredictable contrast), hardcoded colors like `.foregroundColor(.white)` on materials
- **Testing:** Verify text readability in both light/dark modes on all backgrounds, ensure WCAG AA contrast ratios

## Apple Human Interface Guidelines Compliance

**MANDATORY: All UI/UX work must comply with Apple HIG and Liquid Glass design system**

### HIG Compliance Checklist (Project-Specific Requirements)

- ✅ Uses Liquid Glass (or current HIG materials) per project deployment target and design system
- ✅ **Text on materials uses semantic foreground styles (not blend modes)**
- ✅ **ScrollViews use `.safeAreaInset(edge: .top)` to prevent content from scrolling under Dynamic Island/notch**
- ✅ **ScrollViews use `.safeAreaInset(edge: .bottom)` for pinned footers (preferred over ZStack pattern)**
- ✅ **Fixed controls separated from scrollable content (media screens)**

### Common HIG Violations to Avoid

- ❌ **Text blend modes (`.blendMode(.overlay)`) on materials instead of semantic vibrancy**
- ❌ **Hardcoded text colors on translucent backgrounds**
- ❌ **Primary controls inside ScrollView (should be fixed/pinned)**
- ❌ **ScrollViews that allow content to scroll under Dynamic Island/notch when bouncing back**
- ❌ Custom components that duplicate system functionality
- ❌ Non-standard navigation patterns

*For comprehensive HIG guidelines, see `swift-5-9-development-standards.mdc` or `swift-6-development-standards.mdc` (per project Swift language mode)*

## SwiftUI Best Practices

- Use native SwiftUI presentation APIs: `.sheet()`, `.alert()`, `.popover()`, `.fullScreenCover()`
- See "🛑 ZERO TOLERANCE: UI Anti-Patterns" section for sheet requirements
- **Integrate Liquid Glass materials into SwiftUI views and components**

*For comprehensive SwiftUI guidelines, see `swift-5-9-development-standards.mdc` or `swift-6-development-standards.mdc` (per project Swift language mode)*

## Layout Patterns for Media/Playback Screens

**CRITICAL HIG:** Media playback screens require fixed controls that never scroll.

- ✅ Primary controls (play/pause, skip, navigation) must be FIXED (outside `ScrollView`)
- ✅ **PREFERRED:** Use `.safeAreaInset(edge: .bottom)` on ScrollView for pinned footers when supported by the project's minimum deployment target
- ✅ **FALLBACK:** Use `ZStack(alignment: .bottom)` with pinned footer pattern when `safeAreaInset` is unavailable
- ❌ NEVER place primary playback controls inside `ScrollView`
- ❌ NEVER use manual spacers (e.g., `Color.clear.frame(height: 200)`) - unreliable across device sizes
- *Why:* HIG requires primary actions to be always accessible. Scrolling controls away violates this principle.

**Preferred Pattern (when `safeAreaInset` is available at deployment target):**

```swift
ScrollView {
    VStack {
        // Scrollable content
    }
    .padding()
}
.safeAreaInset(edge: .bottom, spacing: 0) {
    // Fixed footer with playback controls
    BottomBarView(...)
        .padding(.horizontal)
        .background(.liquidMaterial(.regular))
}
```

**Fallback Pattern (Legacy):**

```swift
ZStack(alignment: .bottom) {
    ScrollView {
        VStack {
            // Scrollable content
            Color.clear.frame(height: 200) // Manual spacer (not recommended)
        }
    }
    // Fixed footer (pinned outside ScrollView)
    BottomBarView(...)
}
```

## Safe Area Handling for ScrollViews

**CRITICAL:** ScrollViews must respect safe areas to prevent content from being obscured by Dynamic Island, notch, or other system UI elements.

- ✅ **REQUIRED:** Use `.safeAreaInset(edge: .top)` on ScrollViews to ensure content never scrolls under Dynamic Island/notch
- ✅ **REQUIRED:** When content bounces back after scrolling, it must respect safe area boundaries
- ✅ **REQUIRED:** Reduce fixed top padding on content (e.g., from 40 to 20) when using `.safeAreaInset`, as it automatically adds safe area padding
- ❌ **FORBIDDEN:** Fixed top padding that doesn't account for Dynamic Island/notch variations across devices
- ❌ **FORBIDDEN:** Content that can scroll under system UI elements when ScrollView bounces back

**Pattern for ScrollViews:**

```swift
ScrollView {
    VStack {
        // Content with reduced top padding (e.g., 20 instead of 40)
        AlbumArtworkView(...)
            .padding(.top, 20)
        // ... rest of content
    }
    .padding()
}
.safeAreaInset(edge: .top, spacing: 0) {
    // Ensures content never scrolls under Dynamic Island
    Color.clear.frame(height: 0)
}
```

**Why:** Dynamic Island and notch heights vary by device. Using `.safeAreaInset` ensures automatic adaptation across all devices while preventing content from being obscured when ScrollView bounces back after being "thrown" upwards.

## Remember

- **All UI must follow Apple HIG and Liquid Glass design system** - Consult locally indexed HIG and Liquid Glass documentation for every UI feature
- **Match project deployment target** - Use HIG-aligned materials and APIs available at that minimum; verify in Apple documentation
- **See "🛑 ZERO TOLERANCE: UI Anti-Patterns" section** - For native SwiftUI presentation API requirements
