import UIKit
import Vision

struct MenuScan: Sendable {
    let imageData: Data      // upright JPEG, so the boxes line up with what is shown
    let lines: [OCRLine]
}

/// Reads a menu photo with Vision, keeping each line's text and where it sits. Runs on-device.
enum MenuOCRService {
    static func read(_ data: Data) async throws -> MenuScan {
        try await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(data: data) else { throw ImageTextError.unreadable }
            let upright = normalized(image)
            guard let cg = upright.cgImage, let jpeg = upright.jpegData(compressionQuality: 0.85) else { throw ImageTextError.unreadable }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            try VNImageRequestHandler(cgImage: cg).perform([request])

            // Vision's origin is bottom left; flip to top left.
            let raw = (request.results ?? []).compactMap { o -> (String, CGRect)? in
                guard let text = o.topCandidates(1).first?.string.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
                let b = o.boundingBox
                return (text, CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height))
            }
            let lines = arrange(raw)
            guard !lines.isEmpty else { throw ImageTextError.noText }
            return MenuScan(imageData: jpeg, lines: lines)
        }.value
    }

    /// Redraws the photo upright and at a sensible size.
    private static func normalized(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        let scale = min(1, 2400 / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    // MARK: Reading order (pure, tested)

    /// Puts observations in reading order: top to bottom, and column by column on two-column menus.
    /// A price sitting alone on the same row as a dish name is joined back onto that line.
    static func arrange(_ raw: [(String, CGRect)]) -> [OCRLine] {
        var rows = raw.sorted { ($0.1.minY, $0.1.minX) < ($1.1.minY, $1.1.minX) }
        rows = joinPrices(rows)
        rows = orderColumns(rows)
        return rows.enumerated().map { OCRLine(index: $0.offset, text: $0.element.0, box: $0.element.1) }
    }

    private static func joinPrices(_ rows: [(String, CGRect)]) -> [(String, CGRect)] {
        var out: [(String, CGRect)] = []
        for row in rows {
            guard MenuPrice.isPriceOnly(row.0) else { out.append(row); continue }
            // The closest earlier line on the same row, to the left of the price.
            let match = out.indices.reversed().first { i in
                let r = out[i].1
                return abs(r.midY - row.1.midY) < max(r.height, row.1.height) * 0.6 && r.maxX <= row.1.minX + 0.02
                    && !MenuPrice.isPriceOnly(out[i].0)
            }
            if let i = match {
                out[i] = (out[i].0 + " " + row.0, out[i].1.union(row.1))
            } else {
                out.append(row)
            }
        }
        return out
    }

    private static func orderColumns(_ rows: [(String, CGRect)]) -> [(String, CGRect)] {
        let narrow = rows.filter { $0.1.width < 0.6 }
        guard narrow.count >= 8 else { return rows }
        let straddle = narrow.filter { $0.1.minX < 0.47 && $0.1.maxX > 0.53 }.count
        let left = rows.filter { $0.1.midX < 0.5 }
        let right = rows.filter { $0.1.midX >= 0.5 }
        let total = Double(rows.count)
        guard Double(straddle) <= total * 0.1, Double(left.count) >= total * 0.25, Double(right.count) >= total * 0.25 else { return rows }
        return left + right
    }
}
