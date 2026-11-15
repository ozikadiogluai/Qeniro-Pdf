import SwiftUI
import AppKit

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("Genel", systemImage: "gearshape") }
            SignatureSettings()
                .tabItem { Label("İmzalar", systemImage: "signature") }
        }
        .frame(width: 520, height: 360)
    }
}

private struct GeneralSettings: View {
    var body: some View {
        Form {
            LabeledContent("Sürüm") {
                Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
            }
            LabeledContent("Metin tanıma (OCR)") {
                Text("Apple Vision · Türkçe ve İngilizce")
            }
            LabeledContent("LibreOffice") {
                if LibreOfficeBridge.isAvailable {
                    Text("Bulundu — Office dönüştürmeleri için kullanılabilir").foregroundStyle(Theme.green)
                } else {
                    HStack {
                        Text("Kurulu değil (isteğe bağlı)").foregroundStyle(.secondary)
                        Link("İndir", destination: URL(string: "https://www.libreoffice.org/download/download/")!)
                    }
                }
            }
            LabeledContent("Varsayılan uygulama") {
                Text("Finder'da bir PDF'ye sağ tıklayın > Bilgi Al > Birlikte Aç > Qeniro PDF > Tümünü Değiştir")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            LabeledContent("Veriler") {
                Button("İmza klasörünü göster") {
                    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    NSWorkspace.shared.open(base.appendingPathComponent("QeniroPDF/Signatures"))
                }
            }
        }
        .padding(20)
    }
}

private struct SignatureSettings: View {
    @EnvironmentObject var signatures: SignatureStore
    @State private var showCreator = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if signatures.signatures.isEmpty {
                Text("Kayıtlı imza yok.").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(signatures.signatures) { sig in
                            HStack {
                                if let img = signatures.image(for: sig.id) {
                                    Image(nsImage: img).resizable().scaledToFit().frame(height: 44)
                                        .padding(4)
                                        .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
                                }
                                Text(Fmt.relativeDate(sig.created)).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button(role: .destructive) { signatures.delete(sig.id) } label: { Image(systemName: "trash") }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            Spacer()
            Button("Yeni İmza Oluştur…") { showCreator = true }
        }
        .padding(20)
        .sheet(isPresented: $showCreator) {
            SignatureCreatorView { img in _ = signatures.add(img) }
        }
    }
}
