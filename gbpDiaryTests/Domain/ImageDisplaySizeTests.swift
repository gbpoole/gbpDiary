import CoreGraphics
import Testing
@testable import gbpDiary

struct ImageDisplaySizeTests {
    private let intrinsic = CGSize(width: 800, height: 400)   // 2:1 aspect

    @Test func fitsToProposedWidth_whenNarrower() {
        let s = ImageDisplaySize.fit(intrinsic: intrinsic, proposedWidth: 300, widthFraction: nil)
        #expect(s.width == 300)
        #expect(s.height == 150)   // preserves 2:1
    }

    @Test func neverUpscalesPastIntrinsic() {
        let s = ImageDisplaySize.fit(intrinsic: intrinsic, proposedWidth: 2000, widthFraction: nil)
        #expect(s.width == 800)
        #expect(s.height == 400)
    }

    @Test func fractionScalesProposedWidth() {
        // 50% of a 700pt pane = 350pt (below intrinsic 800), aspect-preserved.
        let s = ImageDisplaySize.fit(intrinsic: intrinsic, proposedWidth: 700, widthFraction: 0.5)
        #expect(s.width == 350)
        #expect(s.height == 175)
    }

    @Test func fractionStillCapsAtIntrinsic() {
        // 100% of a 2000pt pane would be 2000, but never exceed the 800pt intrinsic width.
        let s = ImageDisplaySize.fit(intrinsic: intrinsic, proposedWidth: 2000, widthFraction: 1.0)
        #expect(s.width == 800)
    }

    @Test func unconstrained_returnsIntrinsic() {
        let s = ImageDisplaySize.fit(intrinsic: intrinsic, proposedWidth: nil, widthFraction: 0.5)
        #expect(s == intrinsic)   // no proposed width → nothing to take a fraction of
    }

    @Test func zeroIntrinsic_returnsUnchanged() {
        let zero = CGSize(width: 0, height: 0)
        #expect(ImageDisplaySize.fit(intrinsic: zero, proposedWidth: 300, widthFraction: 0.5) == zero)
    }
}
