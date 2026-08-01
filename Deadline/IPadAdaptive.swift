import SwiftUI

extension View {
    /// Centers auth-style screens on iPad without constraining the main app chrome.
    func iPadAuthContainer(maxWidth: CGFloat = 480) -> some View {
        modifier(IPadAuthContainerModifier(maxWidth: maxWidth))
    }

    /// Keeps dense content readable on very wide layouts.
    func iPadReadableContent(maxWidth: CGFloat = 920) -> some View {
        modifier(IPadReadableContentModifier(maxWidth: maxWidth))
    }

    func iPadSheetPresentation() -> some View {
        modifier(IPadSheetPresentationModifier())
    }

    func iPadFormSheetPresentation() -> some View {
        modifier(IPadFormSheetPresentationModifier())
    }
}

private struct IPadAuthContainerModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            AdaptiveWidthContainer(maxContentWidth: maxWidth) {
                content
            }
        } else {
            content
        }
    }
}

private struct IPadReadableContentModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                content
                    .frame(maxWidth: maxWidth)
                Spacer(minLength: 0)
            }
        } else {
            content
        }
    }
}

private struct IPadSheetPresentationModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(20)
                .presentationSizing(.page)
        } else {
            content
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct IPadFormSheetPresentationModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
                .presentationSizing(.form)
        } else {
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }
}
