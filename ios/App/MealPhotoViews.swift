// Meal photos on the Diet timeline (Dylan, 2026-11-19): a small rounded
// thumbnail on an entry that has a photo, and the full photo on tap in a
// viewer with pinch to zoom. A meal's photo never changes, so both sizes
// are kept in memory and on disk by id and size (JarvisKit MealPhotos).
import SwiftUI
import UIKit
import JarvisKit

/// Memory and disk cache for meal photos.
@MainActor
final class MealPhotoCache {
    static let shared = MealPhotoCache()
    private let memory = NSCache<NSString, UIImage>()
    private let folder: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = caches.appendingPathComponent("meal-photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// The photo from memory, then disk, then Jarvis; nil when there's none.
    func image(id: String, thumb: Bool, client: JarvisClient) async -> UIImage? {
        let key = MealPhotos.cacheKey(id: id, thumb: thumb)
        if let hit = memory.object(forKey: key as NSString) { return hit }
        let file = folder.appendingPathComponent(key + ".jpg")
        if let data = try? Data(contentsOf: file), let image = UIImage(data: data) {
            memory.setObject(image, forKey: key as NSString)
            return image
        }
        guard let data = await client.mealPhoto(id: id, thumb: thumb), let image = UIImage(data: data) else { return nil }
        try? data.write(to: file, options: .atomic)
        memory.setObject(image, forKey: key as NSString)
        return image
    }
}

/// A 56 pt rounded thumbnail: a quiet placeholder while it loads, nothing
/// at all when there's no photo. Loads when the row appears and stops when
/// it scrolls away.
struct MealThumbnail: View {
    let item: FoodItem
    let onOpen: () -> Void
    @EnvironmentObject private var app: AppModel
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        if !failed {
            Button(action: onOpen) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.06))
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(image == nil)
            .accessibilityLabel("Photo of \(item.name)")
            .task(id: item.id) {
                guard image == nil else { return }
                if let loaded = await MealPhotoCache.shared.image(id: item.id, thumb: true, client: app.client) {
                    image = loaded
                } else if !Task.isCancelled {
                    failed = true
                }
            }
        }
    }
}

/// The full photo, pinch to zoom, with the entry's name, time and macros.
struct MealPhotoViewer: View {
    let item: FoodItem
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var missing = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    Group {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .scaleEffect(scale)
                                .gesture(MagnifyGesture()
                                    .onChanged { scale = max(1, min(5, lastScale * $0.magnification)) }
                                    .onEnded { _ in lastScale = scale })
                                .onTapGesture(count: 2) {
                                    withAnimation(.smooth) { scale = scale > 1 ? 1 : 2.5; lastScale = scale }
                                }
                                .accessibilityLabel("Photo of \(item.name)")
                        } else if missing {
                            Text("The photo isn't available right now.").foregroundStyle(Theme.frostDim)
                        } else {
                            VStack(spacing: 12) {
                                ProgressView().controlSize(.large).tint(Theme.frost)
                                Text("Loading the photo…").foregroundStyle(Theme.frost)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(spacing: 4) {
                        Text(item.name).font(.headline).foregroundStyle(Theme.frost).multilineTextAlignment(.center)
                        Text([DietTimeline.timeLabel(item), "\(Diet.whole(item.macros.calories)) kcal", Diet.macroLine(item.macros)].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.subheadline)
                            .foregroundStyle(Theme.frostDim)
                    }
                    .padding(.bottom, 12)
                }
                .padding(.horizontal, 16)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            if let full = await MealPhotoCache.shared.image(id: item.id, thumb: false, client: app.client) {
                image = full
            } else {
                missing = true
            }
        }
    }
}
