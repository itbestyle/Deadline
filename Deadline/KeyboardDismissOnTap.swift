import SwiftUI
import UIKit

private struct KeyboardDismissOnTapView: UIViewRepresentable {
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(to: view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        DispatchQueue.main.async {
            context.coordinator.attachIfNeeded(to: uiView)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: () -> Void
        private weak var hostView: UIView?
        private var recognizer: UITapGestureRecognizer?

        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }

        deinit {
            if let recognizer, let hostView {
                hostView.removeGestureRecognizer(recognizer)
            }
        }

        func attachIfNeeded(to view: UIView) {
            guard let superview = view.superview else { return }
            if hostView === superview { return }

            if let recognizer, let hostView {
                hostView.removeGestureRecognizer(recognizer)
            }

            let newRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            newRecognizer.cancelsTouchesInView = false
            newRecognizer.delegate = self
            superview.addGestureRecognizer(newRecognizer)

            hostView = superview
            recognizer = newRecognizer
        }

        @objc private func handleTap() {
            onTap()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

private struct KeyboardDismissOnTapModifier: ViewModifier {
    let onTap: () -> Void

    func body(content: Content) -> some View {
        content.background(KeyboardDismissOnTapView(onTap: onTap))
    }
}

extension View {
    func keyboardDismissOnTap(_ onTap: @escaping () -> Void) -> some View {
        modifier(KeyboardDismissOnTapModifier(onTap: onTap))
    }
}

