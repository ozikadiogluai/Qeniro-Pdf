import SwiftUI
import AppKit

struct CloudView: View {
    @EnvironmentObject var app: AppState
    @State private var locations: [CloudLocation] = []
    @State private var selected: CloudLocation?
    @State private var files: [CloudFile] = []
    @State private var loading = false
    @State private var query = ""

    private var filtered: [CloudFile] {
        query.isEmpty ? files : files.filter { $0.url.lastPathComponent.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Bulut Depolama").font(Theme.titleFont)
            if locations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Bulut klasörü bulunamadı", systemImage: "icloud.slash").font(.headline)
                    Text("iCloud Drive'ı Sistem Ayarları > Apple Hesabı > iCloud bölümünden açabilirsiniz. Google Drive, Dropbox ve OneDrive masaüstü uygulamaları da ~/Library/CloudStorage altında görünür.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Yeniden Tara") { reloadLocations() }
                }
                .padding(16)
                .frame(maxWidth: 560, alignment: .leading)
                .qCard()
            } else {
                HStack(spacing: 10) {
                    Picker("Konum", selection: $selected) {
                        ForEach(locations) { loc in
                            Text(loc.name).tag(Optional(loc))
                        }
                    }
                    .frame(maxWidth: 300)
                    TextField("PDF ara", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 220)
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Yenile")
                    if let selected {
                        Button("Finder'da Aç") { NSWorkspace.shared.open(selected.url) }
                    }
                    Spacer()
                }
                if loading {
                    ProgressView("PDF'ler aranıyor…").padding(.top, 30).frame(maxWidth: .infinity)
                } else if filtered.isEmpty {
                    Text("Bu konumda PDF bulunamadı.").foregroundStyle(.secondary).padding(.top, 20)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(filtered) { f in
                                CloudRow(file: f)
                                Divider()
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .frame(maxWidth: 1100, alignment: .leading)
        .onAppear { reloadLocations() }
        .onChange(of: selected) { _, _ in load() }
    }

    private func reloadLocations() {
        locations = CloudStore.locations()
        if selected == nil || !locations.contains(where: { $0 == selected }) { selected = locations.first }
        load()
    }

    private func load() {
        guard let loc = selected else { files = []; return }
        loading = true
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) { CloudStore.pdfs(in: loc) }.value
            files = result
            loading = false
        }
    }
}

struct CloudRow: View {
    @EnvironmentObject var app: AppState
    let file: CloudFile
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.richtext").font(.system(size: 18)).foregroundStyle(Theme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.lastPathComponent).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text("\(Fmt.fileSize(file.size)) · \(Fmt.relativeDate(file.modified)) · \(file.url.deletingLastPathComponent().lastPathComponent)")
                    .font(Theme.captionFont).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(hover ? Theme.activeNav.opacity(0.5) : Color.clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { app.open(file.url) }
        .contextMenu {
            Button("Aç") { app.open(file.url) }
            Button("Finder'da Göster") { Dialogs.revealInFinder([file.url]) }
        }
    }
}
