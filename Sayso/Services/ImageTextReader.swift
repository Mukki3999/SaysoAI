import UIKit
import Vision

enum ImageTextError: LocalizedError {
    case unreadable, noText
    var errorDescription: String? {
        switch self {
        case .unreadable: "Sayso couldn't open that photo."
        case .noText: "Sayso couldn't find any text in that photo."
        }
    }
}

/// Reads text from an image with Vision. Runs on-device; the image is never sent anywhere.
enum ImageTextReader {
    static func read(_ data: Data) async throws -> String {
        guard let cgImage = UIImage(data: data)?.cgImage else { throw ImageTextError.unreadable }
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: cgImage).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { throw ImageTextError.noText }
            return text
        }.value
    }
}
