import SwiftUI
import PDFKit
import UniformTypeIdentifiers

/// Sayfaları organize et: küçük resim ızgarası, sürükle-bırak ile sıralama, döndür, sil, çıkar.
struct PageOrganizerView: View {
    @ObservedObject var session: DocumentSession
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<Int> = []
    @State private var dragging: Int?
    @State private var share: ShareItem?
    @State private var confirmDelete = false

    let columns = [GridItem(.adaptive(minimum: 100, maximum: 140), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(0..<session.pageCount, id: \.self) { i in
                        if let page = session.document.page(at: i) {
                            cell(page: page, index: i)
                        }
                    }
                }
                .padding(16)
                // Belge değişince ızgara yeniden kurulur.
                .id(session.revision)
            }
            .background(Theme.viewerBackground)
            .navigationTitle("Sayfaları organize et")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { session.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(!session.canUndo)
                        .accessibilityLabel("Geri al")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Bitti") { dismiss() }.fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { session.rotate(pages: targets, by: -90) } label: { Image(systemName: "rotate.left") }
                        .accessibilityLabel("Sola döndür")
                    Button { session.rotate(pages: targets, by: 90) } label: { Image(systemName: "rotate.right") }
                        .accessibilityLabel("Sağa döndür")
                    Spacer()
                    Text(selection.isEmpty ? String(localized: "Sayfa seçmek için dokunun") : String(localized: "\(selection.count) sayfa seçili"))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                    Button { extract() } label: { Image(systemName: "doc.on.doc") }
                        .disabled(selection.isEmpty)
                        .accessibilityLabel("Seçili sayfaları yeni PDF olarak çıkar")
                    Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                        .disabled(selection.isEmpty)
                        .accessibilityLabel("Seçili sayfaları sil")
                }
            }
            .confirmationDialog("\(selection.count) sayfa silinsin mi?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Sil", role: .destructive) {
                    session.deletePages(Array(selection))
                    selection = []
                }
                Button("Vazgeç", role: .cancel) {}
            }
            .sheet(item: $share) { item in ActivityView(items: item.urls) }
        }
    }

    /// Seçim yoksa geçerli sayfa.
    private var targets: [Int] {
        selection.isEmpty ? [session.currentPageIndex] : Array(selection).sorted()
    }

    private func cell(page: PDFPage, index i: Int) -> some View {
        let selected = selection.contains(i)
        return VStack(spacing: 6) {
            PageThumbnail(page: page, size: CGSize(width: 100, height: 130))
                .rotationEffect(.zero)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(selected ? Theme.blue : Theme.border, lineWidth: selected ? 3 : 1))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white, Theme.blue)
                            .padding(4)
                    }
                }
            Text("\(i + 1)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondary)
        }
        .opacity(dragging == i ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            if selected { selection.remove(i) } else { selection.insert(i) }
        }
        .onDrag {
            dragging = i
            return NSItemProvider(object: "\(i)" as NSString)
        }
        .onDrop(of: [UTType.text], delegate: PageDropDelegate(target: i, session: session, dragging: $dragging, selection: $selection))
        .contextMenu {
            Button { session.goTo(page: i); dismiss() } label: { Label("Bu sayfaya git", systemImage: "arrow.right.doc.on.clipboard") }
            Button { session.rotate(pages: [i], by: 90) } label: { Label("Döndür", systemImage: "rotate.right") }
            Button { session.insertBlankPage(after: i) } label: { Label("Sonrasına boş sayfa ekle", systemImage: "doc.badge.plus") }
            Button(role: .destructive) { session.deletePages([i]) } label: { Label("Sil", systemImage: "trash") }
        }
    }

    private func extract() {
        let indices = Array(selection).sorted()
        guard !indices.isEmpty else { return }
        session.commitInlineIfNeeded()
        let out = DocTools.rebuiltCopy(of: session.documentForWriting(), pages: indices)
        do {
            let dir = try DocTools.freshOutputFolder()
            let url = dir.appendingPathComponent("\((session.displayName as NSString).deletingPathExtension)_sayfalar.pdf")
            try DocTools.write(out, to: url)
            share = ShareItem(urls: [url])
        } catch {
            session.errorMessage = error.localizedDescription
        }
    }
}

/// Bir sayfanın üzerine bırakınca sürüklenen sayfayı oraya taşır.
struct PageDropDelegate: DropDelegate {
    let target: Int
    let session: DocumentSession
    @Binding var dragging: Int?
    @Binding var selection: Set<Int>

    func performDrop(info: DropInfo) -> Bool {
        defer { dragging = nil }
        guard let from = dragging, from != target else { return false }
        MainActor.assumeIsolated {
            session.movePage(from: from, to: target)
        }
        selection = []
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
}
