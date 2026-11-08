import CoreGraphics

/// Accessibility frames use a top-left origin on the primary display; Cocoa uses bottom-left.
public enum Geometry {
    public static func cocoaRect(fromAX r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    /// The same flip is its own inverse.
    public static func axRect(fromCocoa r: CGRect, primaryHeight: CGFloat) -> CGRect {
        cocoaRect(fromAX: r, primaryHeight: primaryHeight)
    }

    /// Indices of frames to keep, dropping any that nearly coincide with an earlier one
    /// (e.g. a button and its wrapper group). Earlier frames win.
    public static func dedupe(_ frames: [CGRect], threshold: CGFloat = 0.9) -> [Int] {
        var kept: [Int] = []
        for (i, f) in frames.enumerated() {
            let duplicate = kept.contains { j in
                let k = frames[j]
                let inter = k.intersection(f)
                guard !inter.isNull else { return false }
                let interArea = inter.width * inter.height
                let union = k.width * k.height + f.width * f.height - interArea
                return union > 0 && interArea / union > threshold
            }
            if !duplicate { kept.append(i) }
        }
        return kept
    }
}
