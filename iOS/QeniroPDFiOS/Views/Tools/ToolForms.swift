import SwiftUI
import PDFKit

/// İş bitince gösterilen sonuç: dosyalar ve isteğe bağlı not.
struct ToolOutput: Identifiable, Sendable {
    let id = UUID()
    var urls: [URL]
    var note: String?
}

/// Ağır işleri arka planda çalıştırır, sonucu ana iş parçacığında verir.
@MainActor
final class ToolJob: ObservableObject {
    @Published var running = false
    @Published var error: String?
    @Published var output: ToolOutput?

    func run(_ message: String = "İşleniyor…", _ work: @escaping @Sendable () throws -> ToolOutput) {
        guard !running else { return }
        running = true
        error = nil
        Task {
            do {
                let out = try await Task.detached(priority: .userInitiated) { try work() }.value
                running = false
                output = out
            } catch {
                running = false
                self.error = error.localizedDescription
            }
        }
    }
}

/// Mavi, tam genişlikte ana düğme (52 pt, kapsül).
struct PrimaryButton: View {
    let title: String
    var color: Color = Theme.blue
    var busy = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if busy { ProgressView().tint(.white) } else { Text(title) }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(color, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }
}

/// İkincil, çerçeveli küçük düğme.
struct OutlineButton: View {
    let title: String
    var icon: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 15)) }
                Text(title).font(.system(size: 13.5)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Dönüştür panelindeki gibi seçim satırı (mavi halka = seçili).
struct RadioRow: View {
    let title: String
    var trailing: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .strokeBorder(selected ? Theme.blue : Theme.chevron, lineWidth: selected ? 6 : 2)
                    .frame(width: 20, height: 20)
                Text(title)
                    .font(.system(size: 15.5))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 0)
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 12.5, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Theme.secondary)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(selected ? Theme.blue : Theme.border, lineWidth: selected ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Sonuç kartı: dosya adları + Paylaş (Dosyalara Kaydet dahil) + PDF ise Aç.
struct ToolResultView: View {
    @EnvironmentObject private var app: AppModel
    let output: ToolOutput
    var allowOpen = true
    @State private var share: ShareItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                Text(output.urls.count == 1 ? "Hazır" : "\(output.urls.count) dosya hazır")
                    .font(.system(size: 16, weight: .semibold))
            }
            if let note = output.note {
                Text(note).font(.system(size: 13.5)).foregroundStyle(Theme.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(output.urls.prefix(6), id: \.self) { u in
                    Text("• \(u.lastPathComponent)  (\(Fmt.fileSize(Fmt.fileSize(of: u))))")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if output.urls.count > 6 {
                    Text("… ve \(output.urls.count - 6) dosya daha").font(.system(size: 13)).foregroundStyle(Theme.secondary)
                }
            }
            PrimaryButton(title: "Paylaş veya Dosyalara Kaydet") { share = ShareItem(urls: output.urls) }
            // Görüntüleyici açıkken başka belge açılmaz (kaydedilmemiş değişiklikler kaybolmasın).
            if allowOpen, app.session == nil, output.urls.count == 1, let u = output.urls.first, u.pathExtension.lowercased() == "pdf" {
                OutlineButton(title: "Qeniro PDF'de aç", icon: "doc") {
                    let target = DocTools.uniqueDocumentURL(u.deletingPathExtension().lastPathComponent)
                    do {
                        try FileManager.default.copyItem(at: u, to: target)
                        app.toolRun = nil
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 450_000_000)
                            app.open(target)
                        }
                    } catch {
                        app.errorMessage = error.localizedDescription
                    }
                }
            }
        }
        .padding(16)
        .card()
        .sheet(item: $share) { item in ActivityView(items: item.urls) }
    }
}

// MARK: - Böl

struct SplitForm: View {
    let data: Data
    let name: String
    @StateObject private var job = ToolJob()
    @State private var mode = 0
    @State private var ranges = "1-2, 3-"
    @State private var every = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Bölme şekli", selection: $mode) {
                Text("Aralıklar").tag(0)
                Text("Her N sayfa").tag(1)
                Text("Her sayfa").tag(2)
            }
            .pickerStyle(.segmented)
            if mode == 0 {
                TextField("Örnek: 1-3, 5, 8-", text: $ranges)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numbersAndPunctuation)
                Text("Her aralık ayrı bir PDF olur.").font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
            } else if mode == 1 {
                Stepper("Her \(every) sayfada bir dosya", value: $every, in: 1...500)
            }
            PrimaryButton(title: "Böl", busy: job.running) {
                let m: SplitMode = mode == 0 ? .ranges(ranges) : (mode == 1 ? .everyN(every) : .single)
                let d = data, base = (name as NSString).deletingPathExtension
                job.run {
                    let folder = try DocTools.freshOutputFolder()
                    let urls = try PDFSplitService.split(data: d, mode: m, folder: folder, baseName: base)
                    return ToolOutput(urls: urls)
                }
            }
            if let e = job.error { Text(e).font(.system(size: 13)).foregroundStyle(Theme.accent) }
            if let out = job.output { ToolResultView(output: out, allowOpen: out.urls.count == 1) }
        }
    }
}

// MARK: - Sıkıştır

struct CompressForm: View {
    let data: Data
    let name: String
    @StateObject private var job = ToolJob()
    @State private var level: CompressionLevel = .medium
    @State private var rasterize = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Şu anki boyut: \(Fmt.fileSize(Int64(data.count)))").font(.system(size: 14)).foregroundStyle(Theme.secondary)
            VStack(spacing: 8) {
                ForEach(CompressionLevel.allCases) { lv in
                    RadioRow(title: lv.title, selected: level == lv) { level = lv }
                }
            }
            Toggle("Sayfaları görüntüye çevir (en küçük boyut)", isOn: $rasterize)
                .font(.system(size: 14.5))
            PrimaryButton(title: "Sıkıştır", busy: job.running) {
                let d = data, n = name, lv = level, r = rasterize
                job.run {
                    let folder = try DocTools.freshOutputFolder()
                    let out = folder.appendingPathComponent((n as NSString).deletingPathExtension + "_sıkıştırılmış.pdf")
                    let res = try PDFCompressService.compress(data: d, name: n, output: out, level: lv, rasterize: r)
                    let saved = res.before > 0 ? Int((1 - Double(res.after) / Double(res.before)) * 100) : 0
                    var note = "\(Fmt.fileSize(res.before)) → \(Fmt.fileSize(res.after))" + (saved > 0 ? " (%\(saved) daha küçük)" : "")
                    if let n2 = res.note { note += "\n" + n2 }
                    return ToolOutput(urls: [res.output], note: note)
                }
            }
            if let e = job.error { Text(e).font(.system(size: 13)).foregroundStyle(Theme.accent) }
            if let out = job.output { ToolResultView(output: out) }
        }
    }
}

// MARK: - Şifreyle koru

struct ProtectForm: View {
    let data: Data
    let name: String
    @StateObject private var job = ToolJob()
    @State private var openPassword = ""
    @State private var confirm = ""
    @State private var permissionsPassword = ""
    @State private var allowPrinting = true
    @State private var allowCopying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SecureField("Açma şifresi", text: $openPassword).textFieldStyle(.roundedBorder)
            SecureField("Şifre (tekrar)", text: $confirm).textFieldStyle(.roundedBorder)
            SecureField("İzin şifresi (isteğe bağlı)", text: $permissionsPassword).textFieldStyle(.roundedBorder)
            Toggle("Yazdırmaya izin ver", isOn: $allowPrinting).font(.system(size: 14.5))
            Toggle("Metin kopyalamaya izin ver", isOn: $allowCopying).font(.system(size: 14.5))
            PrimaryButton(title: "Şifreyle Koru", busy: job.running) {
                guard !openPassword.isEmpty else { job.error = "Bir açma şifresi girin."; return }
                guard openPassword == confirm else { job.error = "Şifreler aynı değil."; return }
                let o = ProtectOptions(openPassword: openPassword, permissionsPassword: permissionsPassword,
                                       allowPrinting: allowPrinting, allowCopying: allowCopying)
                let d = data, n = name
                job.run {
                    let folder = try DocTools.freshOutputFolder()
                    let out = folder.appendingPathComponent((n as NSString).deletingPathExtension + "_korumalı.pdf")
                    try PDFProtectService.protect(data: d, name: n, output: out, options: o)
                    return ToolOutput(urls: [out], note: "Dosya 128 bit AES ile şifrelendi. Şifreyi unutmayın; kurtarılamaz.")
                }
            }
            if let e = job.error { Text(e).font(.system(size: 13)).foregroundStyle(Theme.accent) }
            if let out = job.output { ToolResultView(output: out, allowOpen: false) }
        }
    }
}

// MARK: - Hassas bilgileri kaldır

struct SanitizeForm: View {
    let data: Data
    let name: String
    @StateObject private var job = ToolJob()
    @State private var o = SanitizeOptions()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Meta veriler (yazar, başlık…)", isOn: $o.metadata)
            Toggle("Yorumlar ve açıklamalar", isOn: $o.comments)
            Toggle("Gömülü dosyalar", isOn: $o.attachments)
            Toggle("Komutlar ve JavaScript", isOn: $o.scripts)
            Toggle("Form alanı değerleri", isOn: $o.formData)
            Toggle("Bağlantılar", isOn: $o.links)
            PrimaryButton(title: "Temizle", busy: job.running) {
                let d = data, n = name, opts = o
                job.run {
                    let folder = try DocTools.freshOutputFolder()
                    let out = folder.appendingPathComponent((n as NSString).deletingPathExtension + "_temiz.pdf")
                    let report = try PDFSanitizeService.sanitize(data: d, name: n, output: out, options: opts)
                    return ToolOutput(urls: [out], note: report.joined(separator: "\n"))
                }
            }
            .padding(.top, 4)
            if let e = job.error { Text(e).font(.system(size: 13)).foregroundStyle(Theme.accent) }
            if let out = job.output { ToolResultView(output: out) }
        }
        .font(.system(size: 14.5))
    }
}
