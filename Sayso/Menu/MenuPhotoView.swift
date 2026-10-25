import SwiftUI
import UIKit

/// The menu photo, with the selected dish highlighted and zoomed to.
struct MenuPhotoView: View {
    let image: UIImage
    let lines: [OCRLine]
    let highlighted: Set<Int>
    var height: CGFloat = 230

    private var focus: CGRect? {
        let boxes = lines.filter { highlighted.contains($0.index) }.map(\.box)
        return boxes.dropFirst().reduce(boxes.first) { $0?.union($1) }
    }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            let aspect = image.size.height / image.size.width
            // Whole photo when nothing is selected, zoomed in on the dish when something is.
            let fit = min(W / 1, H / aspect)
            // Zoom so the dish fills most of the width, but never so far that the text blurs.
            let zoomed = focus.map { min(max(W * 0.9 / max($0.width, 0.15), W), W * 2.6) } ?? fit
            let width = zoomed
            let imgH = width * aspect
            let center = focus.map { CGPoint(x: $0.midX * width, y: $0.midY * imgH) } ?? CGPoint(x: width / 2, y: imgH / 2)
            let ox = width <= W ? (W - width) / 2 : min(0, max(W - width, W / 2 - center.x))
            let oy = imgH <= H ? (H - imgH) / 2 : min(0, max(H - imgH, H / 2 - center.y))

            ZStack(alignment: .topLeading) {
                Image(uiImage: image).resizable().frame(width: width, height: imgH)
                ForEach(lines.filter { highlighted.contains($0.index) }) { line in
                    // Black inside white, so it shows on a light or a dark menu.
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(.white, lineWidth: 5)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.black, lineWidth: 2.5))
                        .background(Color.black.opacity(0.08))
                        .frame(width: line.box.width * width + 8, height: line.box.height * imgH + 6)
                        .offset(x: line.box.minX * width - 4, y: line.box.minY * imgH - 3)
                }
            }
            .frame(width: width, height: imgH, alignment: .topLeading)
            .offset(x: ox, y: oy)
            .animation(.smooth(duration: 0.45), value: highlighted)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

/// Takes a photo with the camera. The photo is handed straight back as data and never saved.
struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (Data) -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPick: (Data) -> Void
        init(onPick: @escaping (Data) -> Void) { self.onPick = onPick }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let data = (info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.9) { onPick(data) }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }
    }
}
