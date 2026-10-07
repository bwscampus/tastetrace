import Foundation

/// How big a photo should be before it is uploaded.
///
/// 1568px on the long edge is not arbitrary. The model this talks to is
/// high-resolution tier, so a full 12-megapixel photo hits its visual-token
/// ceiling and costs roughly twice as much as this for no better reading of a
/// plate or a label. Downscaling also shrinks the upload, which is the slowest
/// part of the round trip on a phone.
public enum MealPhotoEncoding {
    public static let maxEdge: CGFloat = 1568
    public static let quality: CGFloat = 0.7
    /// Second attempt if the first encode is still too big for the endpoint.
    public static let fallbackQuality: CGFloat = 0.5
    public static let maxBytes = 4 * 1024 * 1024

    /// The scale factor to fit `size` inside `maxEdge`, never enlarging.
    static func scale(for size: CGSize, maxEdge: CGFloat = maxEdge) -> CGFloat {
        let longest = max(size.width, size.height)
        guard longest > maxEdge, longest > 0 else { return 1 }
        return maxEdge / longest
    }

    static func fittedSize(for size: CGSize, maxEdge: CGFloat = maxEdge) -> CGSize {
        let factor = scale(for: size, maxEdge: maxEdge)
        guard factor < 1 else { return size }
        return CGSize(width: (size.width * factor).rounded(), height: (size.height * factor).rounded())
    }
}

#if canImport(UIKit)
import UIKit

public extension MealPhotoEncoding {
    /// Downscale and JPEG-encode, re-encoding harder if it is still too large.
    ///
    /// Always JPEG: the camera produces HEIC by default and the API rejects it,
    /// so re-encoding here is what keeps that from ever reaching the server.
    static func jpeg(from image: UIImage) -> Data? {
        let target = fittedSize(for: image.size)
        let rendered: UIImage
        if target == image.size {
            rendered = image
        } else {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1  // points are pixels here; the target is already in pixels
            rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: target))
            }
        }

        guard let data = rendered.jpegData(compressionQuality: quality) else { return nil }
        if data.count <= maxBytes { return data }
        return rendered.jpegData(compressionQuality: fallbackQuality)
    }
}
#endif
