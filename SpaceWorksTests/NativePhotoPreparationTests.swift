import ImageIO
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import SpaceWorks

@MainActor final class NativePhotoPreparationTests: XCTestCase {
    private func image(size: CGSize, scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.setFillColor(CGColor(gray: 0.5, alpha: 1))
            context.cgContext.fill(CGRect(origin: .zero, size: size))
        }
    }
    func testBoundsPixelDimensionsAndProducesDecodableJPEG() throws {
        let source = image(size: CGSize(width: 1600, height: 800), scale: 2)
        let data = try NativePhotoPreparation.jpeg(from: source)
        let decoded = try XCTUnwrap(UIImage(data: data))
        XCTAssertTrue(data.starts(with: [0xFF, 0xD8, 0xFF]))
        XCTAssertEqual(decoded.cgImage?.width, 1600)
        XCTAssertEqual(decoded.cgImage?.height, 800)
        XCTAssertLessThanOrEqual(data.count, 5 * 1024 * 1024)
    }
    func testSmallPhotoIsNotUpscaledAndOrientationIsNormalized() throws {
        let source = image(size: CGSize(width: 100, height: 50))
        let rotated = UIImage(cgImage: try XCTUnwrap(source.cgImage), scale: 1, orientation: .right)
        let decoded = try XCTUnwrap(UIImage(data: NativePhotoPreparation.jpeg(from: rotated)))
        XCTAssertEqual(decoded.imageOrientation, .up)
        XCTAssertEqual(decoded.size, rotated.size)
        XCTAssertEqual(max(decoded.size.width, decoded.size.height), 100)
    }
    func testReencodingRemovesOriginalGPSMetadata() throws {
        let original = image(size: CGSize(width: 64, height: 64))
        let tagged = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(tagged as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil))
        let properties: [CFString: Any] = [kCGImagePropertyGPSDictionary: [
            kCGImagePropertyGPSLatitude: 0, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 0, kCGImagePropertyGPSLongitudeRef: "E"]]
        CGImageDestinationAddImage(destination, try XCTUnwrap(original.cgImage), properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let input = try XCTUnwrap(CGImageSourceCreateWithData(tagged as CFData, nil))
        let originalMetadata = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(input, 0, nil) as? [CFString: Any])
        XCTAssertNotNil(originalMetadata[kCGImagePropertyGPSDictionary])
        let taggedImage = try XCTUnwrap(UIImage(data: tagged as Data))
        let output = try NativePhotoPreparation.jpeg(from: taggedImage)
        let source = try XCTUnwrap(CGImageSourceCreateWithData(output as CFData, nil))
        let metadata = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertNil(metadata[kCGImagePropertyGPSDictionary])
    }
    func testImpossibleServerCapAndInvalidImageReturnErrorsInsteadOfSendingOversizedEvidence() throws {
        XCTAssertThrowsError(try NativePhotoPreparation.jpeg(from: image(size: CGSize(width: 64, height: 64)), maximumBytes: 16)) {
            XCTAssertEqual($0 as? NativePhotoError, .tooLarge)
        }
        XCTAssertThrowsError(try NativePhotoPreparation.jpeg(from: UIImage())) {
            XCTAssertEqual($0 as? NativePhotoError, .invalidImage)
        }
    }
    func testCaptureAdapterDeliversOnceAndNeverUploadsOrConfirmsEvidence() {
        var results = 0
        var cancellations = 0
        let view = NativeEvidenceCamera(onPhoto: { _ in results += 1 }, onCancel: { cancellations += 1 })
        let coordinator = view.makeCoordinator()
        coordinator.deliver(.success(Data([1])))
        coordinator.deliver(.failure(.invalidImage))
        coordinator.imagePickerControllerDidCancel(UIImagePickerController())
        XCTAssertEqual(results, 1)
        XCTAssertEqual(cancellations, 0)
    }
}
