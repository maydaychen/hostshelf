import AppKit
import SwiftUI

/// Spacing tokens. 8 / 12 / 16 / 24 are the regular rhythm; 4 is the compact step.
enum HostShelfSpacing {
    static let s4: CGFloat = 4
    static let s6: CGFloat = 6
    static let s8: CGFloat = 8
    static let s10: CGFloat = 10
    static let s12: CGFloat = 12
    static let s14: CGFloat = 14
    static let s16: CGFloat = 16
    static let s20: CGFloat = 20
    static let s24: CGFloat = 24
}

/// Corner radius tokens: chips, tags, fields and code blocks / selection and compact containers / panels.
enum HostShelfRadius {
    static let small: CGFloat = 6
    static let medium: CGFloat = 10
    static let large: CGFloat = 14
}

/// System semantic surfaces only. No hex values and no fixed white.
enum HostShelfSurface {
    static let text = Color(nsColor: .textBackgroundColor)
    static let control = Color(nsColor: .controlBackgroundColor)
    static let separator = Color(nsColor: .separatorColor)
    static let focusRing = Color(nsColor: .keyboardFocusIndicatorColor)
    static let selection = Color.accentColor.opacity(0.16)
    static let warning = Color.orange
}

private struct HairlineBorder: ViewModifier {
    @Environment(\.displayScale) private var displayScale
    let cornerRadius: CGFloat
    let color: Color

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(color, lineWidth: 1 / max(displayScale, 1))
                .allowsHitTesting(false)
        )
    }
}

extension View {
    /// Draws a 1 px (physical) semantic border inside the given rounded shape.
    func hairlineBorder(cornerRadius: CGFloat = HostShelfRadius.small, color: Color = HostShelfSurface.separator) -> some View {
        modifier(HairlineBorder(cornerRadius: cornerRadius, color: color))
    }

    /// Lightweight read-only surface: semantic fill plus 1 px separator border.
    func hostSurface(_ fill: Color = HostShelfSurface.text, cornerRadius: CGFloat = HostShelfRadius.small) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .hairlineBorder(cornerRadius: cornerRadius)
    }

    /// Shared title level for detail inspector sections.
    func hostSectionTitle() -> some View {
        font(.headline)
    }

    /// Search container chrome with a focus ring aligned to the whole container.
    func hostSearchFieldChrome(isFocused: Bool) -> some View {
        modifier(SearchFieldChrome(isFocused: isFocused))
    }
}

private struct SearchFieldChrome: ViewModifier {
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isFocused: Bool

    func body(content: Content) -> some View {
        let showsRing = isFocused && controlActiveState == .key
        let ringWidth: CGFloat = 3
        content
            .hostSurface(HostShelfSurface.control, cornerRadius: HostShelfRadius.small)
            .overlay(
                RoundedRectangle(cornerRadius: HostShelfRadius.small + ringWidth, style: .continuous)
                    .strokeBorder(HostShelfSurface.focusRing, lineWidth: ringWidth)
                    .padding(-ringWidth)
                    .opacity(showsRing ? 1 : 0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            )
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: showsRing)
    }
}

/// `#tag` presentation shared by the detail inspector and the quick launcher.
struct HostTag: View {
    let name: String
    var isCompact = false

    init(_ name: String, isCompact: Bool = false) {
        self.name = name
        self.isCompact = isCompact
    }

    var body: some View {
        Text("#\(name)")
            .font(isCompact ? .caption2 : .caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, isCompact ? HostShelfSpacing.s4 : HostShelfSpacing.s6)
            .padding(.vertical, isCompact ? 1 : 2)
            .hostSurface(HostShelfSurface.control, cornerRadius: HostShelfRadius.small)
            .accessibilityLabel("标签 \(name)")
    }
}

/// Borderless compact chip for groups and rule kinds; visually distinct from `HostTag`.
struct HostChip: View {
    let title: String
    var isCompact = false

    init(_ title: String, isCompact: Bool = false) {
        self.title = title
        self.isCompact = isCompact
    }

    var body: some View {
        Text(title)
            .font(isCompact ? .caption2.weight(.medium) : .caption.weight(.medium))
            .padding(.horizontal, isCompact ? HostShelfSpacing.s6 : HostShelfSpacing.s8)
            .padding(.vertical, isCompact ? 2 : 3)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: HostShelfRadius.small, style: .continuous))
    }
}
