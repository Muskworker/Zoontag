import SwiftUI
import AppKit
import QuickLookThumbnailing
import QuickLookUI

struct FileThumbnailView: View {
    let url: URL
    let maxDimension: CGFloat

    @State private var image: NSImage?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: placeholder)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(0.4)
                    .overlay {
                        ProgressView().controlSize(.small)
                    }
            }
        }
        .frame(height: maxDimension)
        .onAppear(perform: loadThumbnail)
        .onChange(of: url) { _, _ in
            loadThumbnail()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private var placeholder: NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: maxDimension, height: maxDimension)
        return icon
    }

    private func loadThumbnail() {
        loadTask?.cancel()
        loadTask = Task {
            if Task.isCancelled { return }
            let generated = await ThumbnailGenerator.generate(for: url, dimension: maxDimension)
            if Task.isCancelled { return }
            await MainActor.run {
                if Task.isCancelled { return }
                image = generated ?? placeholder
            }
        }
    }
}

struct QuickLookPreviewContainer: View {
    let url: URL

    var body: some View {
        QuickLookPreviewRepresentable(url: url)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black.opacity(0.05), lineWidth: 1)
            }
    }
}

private struct QuickLookPreviewRepresentable: NSViewRepresentable {
    let url: URL

    final class Coordinator {
        var previewView: QLPreviewView?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> QLPreviewView {
        let preview = createPreviewView()
        preview.autostarts = true
        preview.previewItem = url as NSURL
        context.coordinator.previewView = preview
        return preview
    }

    func updateNSView(_ nsView: QLPreviewView, context: Context) {
        context.coordinator.previewView?.previewItem = url as NSURL
    }

    private func createPreviewView() -> QLPreviewView {
        if #available(macOS 15.0, *) {
            return QLPreviewView(frame: .zero, style: .normal) ?? QLPreviewView()
        } else {
            return QLPreviewView(frame: .zero) ?? QLPreviewView()
        }
    }
}

enum ThumbnailGenerator {
    private static let generator = QLThumbnailGenerator.shared
    private static let cache = NSCache<NSString, NSImage>()

    static func generate(for url: URL, dimension: CGFloat) async -> NSImage? {
        let size = CGSize(width: dimension, height: dimension)
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let cacheKey = "\(url.path)|\(dimension)|\(scale)" as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return cached
        }

        let request = QLThumbnailGenerator.Request(fileAt: url,
                                                   size: size,
                                                   scale: scale,
                                                   representationTypes: [.thumbnail, .icon])
        return await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
            generator.generateBestRepresentation(for: request) { representation, error in
                guard let representation else {
                    continuation.resume(returning: nil)
                    return
                }
                let image = NSImage(cgImage: representation.cgImage, size: .zero)
                cache.setObject(image, forKey: cacheKey)
                continuation.resume(returning: image)
            }
        }
    }
}
