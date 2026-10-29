import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import XCTest
@testable import TwoFACore

final class QRCodeReaderTests: XCTestCase {
    private let payload = "otpauth://totp/Demo:demo%40example.com?secret=GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ&issuer=Demo"

    func testImageRecognizesAuthenticationQRCode() throws {
        let image = try makeQR()
        let bitmap = try XCTUnwrap(CIContext().createCGImage(image, from: image.extent))
        XCTAssertEqual(QRCodeReader.payloads(in: bitmap), [payload])
    }

    func testCameraPixelBufferRecognizesSamePayload() throws {
        let image = try makeQR()
        XCTAssertEqual(QRCodeReader.payloads(in: try pixelBuffer(image)), [payload])
    }

    func testCameraRecognizesSmallCodeInWideFrame() throws {
        let code = try makeQR().transformed(by: CGAffineTransform(scaleX: 0.2, y: 0.2))
        let frame = CIImage(color: CIColor(red: 0.3, green: 0.3, blue: 0.3))
            .cropped(to: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        let image = code.transformed(by: CGAffineTransform(translationX: 840, y: 430)).composited(over: frame)
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 0.4]).cropped(to: frame.extent)
        XCTAssertEqual(QRCodeReader.payloads(in: try pixelBuffer(image)), [payload])
    }

    func testCameraRecognizesMirroredCode() throws {
        let code = try makeQR()
        let image = code.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: code.extent.width, ty: 0))
        XCTAssertEqual(QRCodeReader.payloads(in: try pixelBuffer(image)), [payload])
    }

    func testCameraRecognizesDimTiltedCode() throws {
        let code = try makeQR().applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: 0.5, kCIInputBrightnessKey: -0.15])
        let tilted = code.applyingFilter("CIPerspectiveTransform", parameters: [
            "inputTopLeft": CIVector(x: 380, y: 740), "inputTopRight": CIVector(x: 680, y: 700),
            "inputBottomLeft": CIVector(x: 400, y: 400), "inputBottomRight": CIVector(x: 700, y: 420)
        ])
        let frame = CIImage(color: CIColor(red: 0.3, green: 0.3, blue: 0.3))
            .cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 960))
        XCTAssertEqual(QRCodeReader.payloads(in: try pixelBuffer(tilted.composited(over: frame))), [payload])
    }

    private func pixelBuffer(_ image: CIImage) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let result = CVPixelBufferCreate(kCFAllocatorDefault, Int(image.extent.width), Int(image.extent.height),
            kCVPixelFormatType_32BGRA, [kCVPixelBufferCGImageCompatibilityKey: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &pixelBuffer)
        XCTAssertEqual(result, kCVReturnSuccess)
        let buffer = try XCTUnwrap(pixelBuffer)
        CIContext().render(image, to: buffer)
        return buffer
    }

    func testBlankImageReturnsNoPayloads() throws {
        let image = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 320, height: 240))
        let bitmap = try XCTUnwrap(CIContext().createCGImage(image, from: image.extent))
        XCTAssertTrue(QRCodeReader.payloads(in: bitmap).isEmpty)
    }

    private func makeQR() throws -> CIImage {
        let generator = CIFilter.qrCodeGenerator()
        generator.message = Data(payload.utf8)
        generator.correctionLevel = "M"
        let code = try XCTUnwrap(generator.outputImage).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let size = CGSize(width: code.extent.width + 48, height: code.extent.height + 48)
        let background = CIImage(color: .white).cropped(to: CGRect(origin: .zero, size: size))
        return code.transformed(by: CGAffineTransform(translationX: 24, y: 24)).composited(over: background)
    }
}
