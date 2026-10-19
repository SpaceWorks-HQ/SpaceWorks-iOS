import XCTest
import UIKit
@testable import SpaceWorks

final class NativeQRSVGTests: XCTestCase {
    private func image(_ svg: String) -> UIImage? { NativeQRSVG.image(Data(svg.utf8)) }
    func testServerQRPathAndStrokeFormatsProduceOpaqueBoundedNativeImages() throws {
        let shapes = [
            #"<path d="M2 2h2v2H2z" fill="black"/>"#,
            #"<path d="M2 2.5h2M2 3.5h2" fill="none" stroke="black"/>"#
        ]
        for shape in shapes {
            let result = try XCTUnwrap(image("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"8mm\" height=\"8mm\" viewBox=\"0 0 8 8\">\(shape)</svg>"))
            XCTAssertEqual(result.size, CGSize(width: 1024, height: 1024))
            let cgImage = try XCTUnwrap(result.cgImage)
            var bytes = [UInt8](repeating: 0, count: 1024 * 1024 * 4)
            try bytes.withUnsafeMutableBytes { buffer in
                let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 4096,
                                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1024, height: 1024))
            }
            let dark = stride(from: 0, to: bytes.count, by: 4).filter { bytes[$0] == 0 && bytes[$0 + 1] == 0 && bytes[$0 + 2] == 0 }.count
            XCTAssertGreaterThan(dark, 16_384); XCTAssertLessThan(dark, 500_000)
            XCTAssertTrue(stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 255 })
        }
    }
    func testScriptsExternalEntitiesImagesTransformsAndUnknownDrawingCommandsAreRefused() {
        let unsafe = [
            #"<svg viewBox="0 0 8 8"><script>alert(1)</script></svg>"#,
            #"<!DOCTYPE svg [<!ENTITY secret SYSTEM "file:///etc/passwd">]><svg viewBox="0 0 8 8"><title>&secret;</title></svg>"#,
            #"<svg viewBox="0 0 8 8"><image href="https://other.example/token"/></svg>"#,
            #"<svg viewBox="0 0 8 8"><path transform="scale(2)" d="M2 2h2v2z"/></svg>"#,
            #"<svg viewBox="0 0 8 8"><path d="M2 2C2 2 3 3 4 4"/></svg>"#,
            #"<svg viewBox="0 0 8 8"><path d="M2 2L999999 999999"/></svg>"#,
            #"<svg viewBox="0 0 bad 8 8"><path d="M2 2h2v2z"/></svg>"#,
            #"<svg viewBox="0 0 8 8"><path opacity="0" d="M2 2h2v2z"/></svg>"#
        ]
        for value in unsafe { XCTAssertNil(image(value)) }
        XCTAssertNil(NativeQRSVG.image(Data(repeating: 32, count: 512 * 1024 + 1)))
    }
}
