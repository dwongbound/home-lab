// Photos in the chat on iPhone and iPad (Dylan, 2026-11-18: "add images…
// send my food pictures to Jarvis").
// Taking or choosing photos, shrinking them before they go (PhotoLimits in
// JarvisKit), the thumbnails above the Ask box, the photos in a sent
// bubble and the full-screen viewer.
import PhotosUI
import SwiftUI
import UIKit
import JarvisKit

/// Turns a picked photo into something small enough to send.
enum PhotoEncoder {
    /// Shrinks to 1600 px on the long side and re-encodes as JPEG, lower
    /// quality if still over ~3 MB. Redrawing it drops every piece of
    /// metadata, location included.
    static func encode(_ image: UIImage) -> Data? {
        let size = PhotoLimits.scaled(width: Double(image.size.width), height: Double(image.size.height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let target = CGSize(width: size.width, height: size.height)
        let drawn = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        var quality = PhotoLimits.startQuality
        var data = drawn.jpegData(compressionQuality: quality)
        while let bytes = data, bytes.count > PhotoLimits.maxBytes, let lower = PhotoLimits.lowerQuality(after: quality) {
            quality = lower
            data = drawn.jpegData(compressionQuality: quality)
        }
        return data
    }

    /// A small square-ish preview for the composer and bubbles.
    static func thumbnail(_ image: UIImage, side: CGFloat = 240) -> UIImage {
        let scale = side / max(image.size.width, image.size.height, 1)
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: target).image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
    }
}

/// One photo picked for the next message: its preview and its bytes.
struct PickedPhoto: Identifiable, Equatable {
    let id = UUID()
    let preview: UIImage
    let jpeg: Data
}

/// The camera, for "Take Photo".
struct CameraPicker: UIViewControllerRepresentable {
    let onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPick(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// The picked photos above the Ask box, each with a remove button.
struct PickedStrip: View {
    @Binding var photos: [PickedPhoto]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(photos) { photo in
                    Image(uiImage: photo.preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(.smooth) { photos.removeAll { $0.id == photo.id } }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .black.opacity(0.6))
                                    .frame(width: 44, height: 44, alignment: .topTrailing)
                            }
                            .offset(x: 8, y: -8)
                            .accessibilityLabel("Remove photo")
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
        .scrollIndicators(.hidden)
    }
}

/// The photos in a sent bubble; tap one to see it full screen.
struct BubblePhotos: View {
    let photos: [UIImage]
    @State private var viewing: Int?

    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(photos.count == 1 ? 200 : 96), spacing: 6), count: min(photos.count, 2))
        LazyVGrid(columns: columns, alignment: .trailing, spacing: 6) {
            ForEach(Array(photos.enumerated()), id: \.offset) { index, photo in
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: photos.count == 1 ? 200 : 96, height: photos.count == 1 ? 200 : 96)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .onTapGesture { viewing = index }
                    .accessibilityLabel("Photo \(index + 1)")
                    .accessibilityAddTraits(.isButton)
            }
        }
        .fullScreenCover(item: Binding(get: { viewing.map(ViewingIndex.init) }, set: { viewing = $0?.index })) { item in
            PhotoViewer(image: photos[item.index]) { viewing = nil }
        }
    }

    private struct ViewingIndex: Identifiable {
        let index: Int
        var id: Int { index }
    }
}

/// One photo full screen, with Close.
struct PhotoViewer: View {
    let image: UIImage
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button("Close", action: onClose)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(minWidth: 88, minHeight: 44)
                .background(Capsule().fill(.white.opacity(0.15)))
                .padding()
        }
    }
}
