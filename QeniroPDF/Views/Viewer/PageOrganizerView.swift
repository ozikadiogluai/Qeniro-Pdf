import SwiftUI
import AppKit
import PDFKit

final class ThumbnailCache {
    private var images: [String: NSImage] = [:]

    func image(for page: PDFPage) -> NSImage {
        let key = "\(ObjectIdentifier(page).hashValue)-\(page.rotation)"
        if let img = images[key] { return img }
        let img = page.thumbnail(of: CGSize(width: 150, height: 190), for: .cropBox)
        images[key] = img
        if images.count > 600 { images.removeAll() }
        return img
    }
}

/// PDF Sayfaları Düzenle: küçük resim ızgarası, sürükle-sırala, döndür, sil, çıkar, ekle.
struct PageOrganizerView: View {
    @ObservedObject var session: DocumentSession
    @State private var selection: Set<Int> = []
    @State private var cache = ThumbnailCache()
    @State private var dropTarget: Int?
    let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 18)]

    private var sortedSelection: [Int] { selection.sorted() }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("PDF Sayfaları Düzenle").font(.headline)
                Text("\(session.pageCount) sayfa" + (selection.isEmpty ? "" : " · \(selection.count) seçili"))
                    .foregroundStyle(.secondary)
                Spacer()
                Group {
                    Button { session.rotate(pages: sortedSelection, by: -90) } label: { Label("Sola döndür", systemImage: "rotate.left") }
                    Button { session.rotate(pages: sortedSelection, by: 90) } label: { Label("Sağa döndür", systemImage: "rotate.right") }
                    Button(role: .destructive) {
                        session.deletePages(sortedSelection)
                        selection.removeAll()
                    } label: { Label("Sil", systemImage: "trash") }
                    Button { session.extractPages(sortedSelection) } label: { Label("Çıkar", systemImage: "square.and.arrow.up") }
                }
                .disabled(selection.isEmpty)
                Divider().frame(height: 18)
                Button { session.insertBlankPage(at: (sortedSelection.last.map { $0 + 1 }) ?? session.pageCount) } label: {
                    Label("Boş sayfa", systemImage: "doc.badge.plus")
                }
                Button {
                    if let u = Dialogs.openPDFs(title: "Eklenecek PDF'yi seçin").first {
                        session.insertPDF(from: u, at: (sortedSelection.last.map { $0 + 1 }) ?? session.pageCount)
                    }
                } label: { Label("PDF'den ekle", systemImage: "plus.rectangle.on.rectangle") }
                Button(selection.count == session.pageCount ? "Seçimi kaldır" : "Tümünü seç") {
                    if selection.count == session.pageCount { selection.removeAll() } else { selection = Set(0..<session.pageCount) }
                }
            }
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            Divider()
            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(0..<session.pageCount, id: \.self) { i in
                        if let page = session.document.page(at: i) {
                            pageCell(index: i, page: page)
                        }
                    }
                }
                .padding(20)
                .id(session.revision)
            }
            .background(Color(nsColor: Theme.canvasNS))
            Text("İpucu: Sayfaları sürükleyerek yeniden sıralayın. ⌘ ile çoklu seçim, ⇧ ile aralık seçimi; çift tıklayınca sayfaya gidilir.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(6)
        }
        .onChange(of: session.pageCount) { _, n in selection = selection.filter { $0 < n } }
    }

    @ViewBuilder
    private func pageCell(index i: Int, page: PDFPage) -> some View {
        let selected = selection.contains(i)
        VStack(spacing: 6) {
            Image(nsImage: cache.image(for: page))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 180)
                .background(Color.white)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
            Text("\(i + 1)")
                .font(.system(size: 12, weight: selected ? .bold : .regular))
                .foregroundStyle(selected ? Theme.selection : Color.secondary)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.activeNav : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(dropTarget == i ? Theme.accent : (selected ? Theme.selection : Color.clear), lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            session.showOrganizer = false
            Task { @MainActor in session.goTo(page: i) }
        }
        .onTapGesture { tap(i) }
        .draggable("qpage:\(i)")
        .dropDestination(for: String.self) { items, _ in
            dropTarget = nil
            guard let s = items.first, s.hasPrefix("qpage:"), let from = Int(s.dropFirst(6)) else { return false }
            session.movePage(from: from, to: i)
            selection = [i]
            return true
        } isTargeted: { inside in
            dropTarget = inside ? i : (dropTarget == i ? nil : dropTarget)
        }
        .contextMenu {
            Button("Sağa döndür") { session.rotate(pages: [i], by: 90) }
            Button("Sola döndür") { session.rotate(pages: [i], by: -90) }
            Button("Önüne boş sayfa ekle") { session.insertBlankPage(at: i) }
            Button("Ayrı PDF olarak çıkar") { session.extractPages([i]) }
            Divider()
            Button("Sil", role: .destructive) { session.deletePages([i]) }
        }
    }

    private func tap(_ i: Int) {
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            if selection.contains(i) { selection.remove(i) } else { selection.insert(i) }
        } else if flags.contains(.shift), let anchor = selection.min() {
            selection = Set(min(anchor, i)...max(anchor, i))
        } else {
            selection = [i]
        }
    }
}
