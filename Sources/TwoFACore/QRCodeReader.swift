import CoreGraphics
import CoreVideo
import Foundation
import Vision

public enum QRCodeReader {
    public static func payloads(in image: CGImage) -> [String] {
        read(VNImageRequestHandler(cgImage: image, options: [:]))
    }

    public static func payloads(in buffer: CVPixelBuffer) -> [String] {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        let payloads = read(handler)
        if !payloads.isEmpty { return payloads }
        // 宽画面中的小二维码容易在整帧分析时漏检，裁出取景框附近再识别一次。
        return read(handler, region: CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
    }

    private static func read(_ handler: VNImageRequestHandler, region: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        request.regionOfInterest = region
        guard (try? handler.perform([request])) != nil else { return [] }
        return (request.results ?? []).compactMap(\.payloadStringValue)
    }
}
