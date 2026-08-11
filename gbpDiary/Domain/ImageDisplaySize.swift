import CoreGraphics

// Pure display-size math for a note image, mirroring Textual's default image attachment sizing plus an
// optional per-image width as a fraction of the available (pane) width. Never upscales past the image's
// intrinsic size, and preserves the aspect ratio. `proposedWidth` is the available width (nil =
// unconstrained); `widthFraction` is the user's chosen fraction of that width (nil = 1.0 / fit).
enum ImageDisplaySize {
    static func fit(intrinsic: CGSize, proposedWidth: CGFloat?, widthFraction: CGFloat?) -> CGSize {
        guard intrinsic.width > 0, intrinsic.height > 0 else { return intrinsic }
        let aspect = intrinsic.width / intrinsic.height
        var width = intrinsic.width
        if let proposedWidth {
            let target = proposedWidth * (widthFraction ?? 1.0)
            width = min(width, target)
        }
        return CGSize(width: width, height: width / aspect)
    }
}
