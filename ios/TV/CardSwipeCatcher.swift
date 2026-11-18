// Swiping the TV's cards with the Siri Remote (Dylan, 2026-11-18). A thin
// UIKit view over the card area that can take focus: a swipe left on the
// touch surface (or a press on the right of the clickpad ring) asks for the
// next card, a swipe right (or a press on the left) for the previous one.
// While it has focus, sideways moves are kept here rather than wandering off
// to the buttons; up and down still move focus out as usual. It takes focus
// when the screen first appears, so swiping works straight away.
import SwiftUI
import UIKit

struct CardSwipeCatcher: UIViewRepresentable {
    /// +1 for the next card, -1 for the previous.
    let onSwipe: (Int) -> Void
    /// Whether it has focus (the page dots brighten).
    let onFocus: (Bool) -> Void

    func makeUIView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onSwipe = onSwipe
        view.onFocus = onFocus
        return view
    }

    func updateUIView(_ view: CatcherView, context: Context) {
        view.onSwipe = onSwipe
        view.onFocus = onFocus
    }

    final class CatcherView: UIView {
        var onSwipe: (Int) -> Void = { _ in }
        var onFocus: (Bool) -> Void = { _ in }
        private var askedForFocus = false

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            // A swipe on the touch surface.
            let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            addGestureRecognizer(pan)
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        override var canBecomeFocused: Bool { true }

        /// Takes focus once, when it first appears, so swiping works at once.
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, !askedForFocus else { return }
            askedForFocus = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                UIFocusSystem.focusSystem(for: self)?.requestFocusUpdate(to: self)
            }
        }

        /// A swipe: left means next, right means previous, once per swipe.
        @objc private func panned(_ pan: UIPanGestureRecognizer) {
            guard pan.state == .ended else { return }
            let dx = pan.translation(in: self).x
            let vx = pan.velocity(in: self).x
            if dx < -60 || vx < -600 { onSwipe(1) } else if dx > 60 || vx > 600 { onSwipe(-1) }
        }

        /// The clickpad ring: right is next, left is previous.
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var handled = false
            for press in presses {
                switch press.type {
                case .rightArrow: onSwipe(1); handled = true
                case .leftArrow: onSwipe(-1); handled = true
                default: break
                }
            }
            if !handled { super.pressesBegan(presses, with: event) }
        }

        /// Sideways moves stay here; up and down may leave for the buttons.
        override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
            if context.previouslyFocusedItem === self, context.focusHeading.contains(.left) || context.focusHeading.contains(.right) {
                return false
            }
            return super.shouldUpdateFocus(in: context)
        }

        override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
            onFocus(context.nextFocusedItem === self)
        }
    }
}
