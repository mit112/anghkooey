import Testing
import Foundation
@testable import AnghkooeyUI

/// #53 — swipe feedback must not be color-only (WCAG 1.4.1). These tests pin
/// down the pure mapping from a drag translation to the symbol/label cue
/// `ReviewView` will render, gated exactly the way `handleSwipeEnd` gates
/// commits: grade cues (again/good/easy) require `isAnswerRevealed`; edit
/// does not, because `handleSwipeEnd` never reveal-guards the down swipe.
@Suite("ReviewView.swipeCue")
struct ReviewSwipeCueTests {

    @Test("revealed: left swipe maps to .again")
    func revealedLeftMapsToAgain() {
        let cue = ReviewView.swipeCue(translation: CGSize(width: -90, height: 2), isAnswerRevealed: true)
        #expect(cue == .again)
    }

    @Test("revealed: right swipe maps to .good")
    func revealedRightMapsToGood() {
        let cue = ReviewView.swipeCue(translation: CGSize(width: 90, height: -2), isAnswerRevealed: true)
        #expect(cue == .good)
    }

    @Test("revealed: up swipe maps to .easy")
    func revealedUpMapsToEasy() {
        let cue = ReviewView.swipeCue(translation: CGSize(width: 1, height: -90), isAnswerRevealed: true)
        #expect(cue == .easy)
    }

    @Test("revealed: down swipe maps to .edit")
    func revealedDownMapsToEdit() {
        let cue = ReviewView.swipeCue(translation: CGSize(width: -1, height: 90), isAnswerRevealed: true)
        #expect(cue == .edit)
    }

    @Test("not revealed: left swipe is suppressed (nil) — grade would not commit")
    func notRevealedLeftSuppressed() {
        let cue = ReviewView.swipeCue(translation: CGSize(width: -90, height: 2), isAnswerRevealed: false)
        #expect(cue == nil)
    }

    @Test("not revealed: right swipe is suppressed (nil) — grade would not commit")
    func notRevealedRightSuppressed() {
        let cue = ReviewView.swipeCue(translation: CGSize(width: 90, height: -2), isAnswerRevealed: false)
        #expect(cue == nil)
    }

    @Test("not revealed: up swipe is suppressed (nil) — grade would not commit")
    func notRevealedUpSuppressed() {
        let cue = ReviewView.swipeCue(translation: CGSize(width: 1, height: -90), isAnswerRevealed: false)
        #expect(cue == nil)
    }

    @Test("not revealed: down swipe still maps to .edit — edit isn't reveal-gated")
    func notRevealedDownStillEdit() {
        let cue = ReviewView.swipeCue(translation: CGSize(width: -1, height: 90), isAnswerRevealed: false)
        #expect(cue == .edit)
    }

    @Test("tiny translation stays in the activation deadzone (nil), revealed")
    func deadzoneRevealedNil() {
        let cue = ReviewView.swipeCue(translation: CGSize(width: 3, height: 2), isAnswerRevealed: true)
        #expect(cue == nil)
    }

    @Test("tiny translation stays in the activation deadzone (nil), not revealed")
    func deadzoneNotRevealedNil() {
        let cue = ReviewView.swipeCue(translation: CGSize(width: -3, height: 2), isAnswerRevealed: false)
        #expect(cue == nil)
    }

    @Test("near-45° diagonal without clear axis dominance is nil (ambiguous), even when revealed")
    func diagonalAmbiguousIsNil() {
        // 50/40 ratio (1.25x) is below the 1.5x dominance rule handleSwipeEnd uses.
        let cue = ReviewView.swipeCue(translation: CGSize(width: -50, height: -40), isAnswerRevealed: true)
        #expect(cue == nil)
    }

    @Test("diagonal with clear horizontal dominance (>1.5x) resolves to the horizontal cue")
    func diagonalHorizontalDominanceResolves() {
        // 90/50 ratio (1.8x) clears the 1.5x dominance rule, so horizontal wins.
        let cue = ReviewView.swipeCue(translation: CGSize(width: -90, height: 50), isAnswerRevealed: true)
        #expect(cue == .again)
    }

    // MARK: - isSwipeCommitted (drives the committed-state scale + haptic)

    @Test("committed: eligible cue below the threshold is not committed")
    func committedBelowThresholdIsFalse() {
        #expect(ReviewView.isSwipeCommitted(translation: CGSize(width: -50, height: 1), isAnswerRevealed: true) == false)
    }

    @Test("committed: exactly at the threshold is not committed (strict >, matches handleSwipeEnd)")
    func committedAtExactThresholdIsFalse() {
        #expect(ReviewView.isSwipeCommitted(translation: CGSize(width: -80, height: 0), isAnswerRevealed: true) == false)
    }

    @Test("committed: eligible cue past the threshold is committed")
    func committedPastThresholdIsTrue() {
        #expect(ReviewView.isSwipeCommitted(translation: CGSize(width: -90, height: 2), isAnswerRevealed: true) == true)
    }

    @Test("committed: an ineligible (pre-reveal grade) direction is never committed even past the threshold")
    func committedIneligibleCueIsFalse() {
        #expect(ReviewView.isSwipeCommitted(translation: CGSize(width: -90, height: 2), isAnswerRevealed: false) == false)
    }

    @Test("committed: down-to-edit past the threshold is committed even before reveal")
    func committedEditPreRevealIsTrue() {
        #expect(ReviewView.isSwipeCommitted(translation: CGSize(width: 1, height: 90), isAnswerRevealed: false) == true)
    }
}
