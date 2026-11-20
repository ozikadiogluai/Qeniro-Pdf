import SwiftUI
import UIKit
import VisionKit
import PencilKit
import PDFKit

// MARK: - Paylaşım menüsü

/// UIActivityViewController ("Dosyalara Kaydet", AirDrop, Mail, WhatsApp…).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// `.sheet(item:)` için paylaşılacak dosyalar.
struct ShareItem: Identifiable {
    let id = UUID()
    let urls: [URL]
}

// MARK: - Belge tarayıcı (VisionKit)

/// Kamerayla belge tarar; sayfa görüntülerini döndürür.
struct DocumentScannerView: UIViewControllerRepresentable {
    var onFinish: ([UIImage]) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScannerView
        init(_ p: DocumentScannerView) { parent = p }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount { images.append(scan.imageOfPage(at: i)) }
            parent.onFinish(images)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onCancel()
        }
    }

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }
}

// MARK: - İmza çizim alanı (PencilKit)

/// Parmak veya Apple Pencil ile imza çizimi.
struct SignaturePadView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var inkColor: UIColor

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let v = PKCanvasView()
        v.drawingPolicy = .anyInput
        v.backgroundColor = .clear
        v.isOpaque = false
        v.isScrollEnabled = false
        v.overrideUserInterfaceStyle = .light
        v.tool = PKInkingTool(.pen, color: inkColor, width: 3)
        v.delegate = context.coordinator
        v.drawing = drawing
        return v
    }

    func updateUIView(_ v: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        if v.drawing != drawing { v.drawing = drawing }
        v.tool = PKInkingTool(.pen, color: inkColor, width: 3)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: SignaturePadView
        init(_ p: SignaturePadView) { parent = p }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            if parent.drawing != canvasView.drawing { parent.drawing = canvasView.drawing }
        }
    }
}

/// İmza görüntüleri için yardımcılar.
enum SignatureImages {
    /// Çizimi saydam arka planlı, sıkıca kırpılmış görüntüye çevirir.
    static func image(from drawing: PKDrawing) -> UIImage? {
        let b = drawing.bounds
        guard !b.isEmpty, b.width > 2, b.height > 2 else { return nil }
        let rect = b.insetBy(dx: -6, dy: -6)
        // Koyu temada bile açık görünüm renkleriyle çiz.
        var img: UIImage?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            img = drawing.image(from: rect, scale: 3)
        }
        return img
    }

    /// Yazılan adı el yazısı benzeri yazı tipiyle görüntüye çevirir.
    static func image(fromText text: String, fontName: String, color: UIColor, size: CGFloat = 64) -> UIImage? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let font = UIFont(name: fontName, size: size) ?? UIFont.italicSystemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let s = (clean as NSString).size(withAttributes: attrs)
        let canvas = CGSize(width: ceil(s.width) + 16, height: ceil(s.height) + 12)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 2
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            (clean as NSString).draw(at: CGPoint(x: 8, y: 6), withAttributes: attrs)
        }
    }

    /// El yazısı görünümlü, iOS'ta yüklü gelen yazı tipleri.
    static let scriptFonts: [(name: String, title: String)] = [
        ("SnellRoundhand", "Snell Roundhand"),
        ("Zapfino", "Zapfino"),
        ("SavoyeLetPlain", "Savoye"),
        ("BradleyHandITCTT-Bold", "Bradley Hand"),
        ("Noteworthy-Light", "Noteworthy")
    ]
}

// MARK: - Küçük görünümler

/// Son dosyalar listesindeki kırmızı "PDF" rozeti.
struct PDFBadge: View {
    var body: some View {
        Text("PDF")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Theme.pdfBadgeText)
            .frame(width: 36, height: 44)
            .background(Theme.pdfBadgeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Bir dosya satırı (ad, boyut · tarih, yıldız).
struct FileRow: View {
    let entry: FileEntry
    let starred: Bool

    var body: some View {
        HStack(spacing: 12) {
            PDFBadge()
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(Fmt.fileSize(entry.size)) · \(Fmt.relativeDate(entry.date))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 0)
            if starred {
                Image(systemName: "star.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.orange)
                    .accessibilityLabel("Yıldızlı")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// Bekleme göstergesi (tam ekran yarı saydam).
struct BusyOverlay: View {
    let message: String
    var body: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().controlSize(.large)
                Text(message).font(.subheadline.weight(.medium)).multilineTextAlignment(.center)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(40)
        }
    }
}

/// Sayfa küçük resmi (organize et ızgarası için).
struct PageThumbnail: View {
    let page: PDFPage
    let size: CGSize
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.white
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView()
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: ObjectIdentifier(page)) {
            image = page.thumbnail(of: CGSize(width: size.width * 2, height: size.height * 2), for: .cropBox)
        }
    }
}
