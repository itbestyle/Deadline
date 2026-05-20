import SwiftUI

/// A simple container that centers its content and constrains its maximum width on large screens,
/// while allowing the content to expand to the full width on compact screens.
public struct AdaptiveWidthContainer<Content: View>: View {
    private let maxContentWidth: CGFloat
    private let horizontalPadding: CGFloat
    @ViewBuilder private let content: Content

    /// - Parameters:
    ///   - maxContentWidth: The maximum width the content should occupy on wide layouts. Default is 600.
    ///   - horizontalPadding: The horizontal padding to apply around the content. Default is 0 because callers often add their own.
    ///   - content: The view builder for the container's content.
    public init(maxContentWidth: CGFloat = 600,
                horizontalPadding: CGFloat = 0,
                @ViewBuilder content: () -> Content) {
        self.maxContentWidth = maxContentWidth
        self.horizontalPadding = horizontalPadding
        self.content = content()
    }

    public var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width <= maxContentWidth

            Group {
                if isCompact {
                    content
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, horizontalPadding)
                } else {
                    HStack {
                        Spacer(minLength: 0)
                        content
                            .frame(maxWidth: maxContentWidth, alignment: .center)
                            .padding(.horizontal, horizontalPadding)
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
    }
}
