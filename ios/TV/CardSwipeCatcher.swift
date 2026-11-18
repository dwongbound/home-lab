// Swiping the TV's cards with the Siri Remote (Dylan, 2026-11-18). A thin
// UIKit view over the card area that can take focus: a swipe left on the
// touch surface asks for the next card, a swipe right for the previous one.
// A swipe's own focus move is kept here so it doesn't wander off to the
// buttons; pressing the clickpad ring (any direction) moves focus as usual. It takes focus
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

        /// True while a left or right press on the clickpad ring is down.
        /// Presses move focus to the buttons as usual (Dylan, 2026-11-18:
        /// "if i press left and right i should still be able to select the
        /// buttons"); only a swipe on the touch surface pages the cards.
        private var arrowPressed = false

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            if presses.contains(where: { $0.type == .leftArrow || $0.type == .rightArrow }) {
                arrowPressed = true
            }
            super.pressesBegan(presses, with: event)
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            releaseArrow()
            super.pressesEnded(presses, with: event)
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            releaseArrow()
            super.pressesCancelled(presses, with: event)
        }

        /// Cleared a moment after the press, so the focus move it starts
        /// still sees it.
        private func releaseArrow() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.arrowPressed = false }
        }

        /// A sideways swipe stays here (it pages the cards); a sideways press,
        /// and up or down, may leave for the buttons.
        override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
            if context.previouslyFocusedItem === self, !arrowPressed,
               context.focusHeading.contains(.left) || context.focusHeading.contains(.right) {
                return false
            }
            return super.shouldUpdateFocus(in: context)
        }

        override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
            onFocus(context.nextFocusedItem === self)
        }
    }
}
