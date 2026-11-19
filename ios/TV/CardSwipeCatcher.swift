// Changing the TV's cards with the Siri Remote (Dylan, 2026-11-19: "the
// apple tv swipe functionality isn't working to change panels. if it
// interferes with left and right click, change it so up and down clicking /
// swiping changes panels"). Up goes to the card before, down to the next,
// by a click on the ring or a swipe on the touch surface. Left and right are
// left alone, so they move between the buttons as usual.
//
// The recognisers sit on the window, not on a focusable view, so they work
// wherever focus is. They stand aside while `enabled` is false (the chat or
// notices panel is open, or the night view is up), so those keep their own
// up and down.
import SwiftUI
import UIKit

struct CardPager: UIViewRepresentable {
    /// +1 for the next card, -1 for the previous.
    let onStep: (Int) -> Void
    /// False while another panel owns up and down.
    let enabled: Bool

    func makeUIView(context: Context) -> PagerView {
        let view = PagerView()
        view.onStep = onStep
        view.enabled = enabled
        return view
    }

    func updateUIView(_ view: PagerView, context: Context) {
        view.onStep = onStep
        view.enabled = enabled
    }

    final class PagerView: UIView {
        var onStep: (Int) -> Void = { _ in }
        var enabled = true
        private var installed: [UIGestureRecognizer] = []
        private lazy var rules = Rules(owner: self)

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            backgroundColor = .clear
        }

        required init?(coder: NSCoder) { fatalError("not used") }

        /// Puts the recognisers on the window (and takes them off when it goes).
        override func didMoveToWindow() {
            super.didMoveToWindow()
            installed.forEach { $0.view?.removeGestureRecognizer($0) }
            installed = []
            guard let window else { return }
            let up = UITapGestureRecognizer(target: self, action: #selector(stepBack))
            up.allowedPressTypes = [NSNumber(value: UIPress.PressType.upArrow.rawValue)]
            let down = UITapGestureRecognizer(target: self, action: #selector(stepOn))
            down.allowedPressTypes = [NSNumber(value: UIPress.PressType.downArrow.rawValue)]
            let swipeUp = UISwipeGestureRecognizer(target: self, action: #selector(stepBack))
            swipeUp.direction = .up
            let swipeDown = UISwipeGestureRecognizer(target: self, action: #selector(stepOn))
            swipeDown.direction = .down
            for recogniser in [up, down, swipeUp, swipeDown] {
                recogniser.delegate = rules
                recogniser.cancelsTouchesInView = false
                window.addGestureRecognizer(recogniser)
            }
            installed = [up, down, swipeUp, swipeDown]
        }

        @objc private func stepBack() { if enabled { onStep(-1) } }
        @objc private func stepOn() { if enabled { onStep(1) } }
    }

    /// The recognisers' rules: only while the cards own up and down, and
    /// alongside the focus engine's own use of the touch surface.
    final class Rules: NSObject, UIGestureRecognizerDelegate {
        weak var owner: PagerView?
        init(owner: PagerView) { self.owner = owner }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            owner?.enabled ?? false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
