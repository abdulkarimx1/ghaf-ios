import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import MessageUI
import GhafCore

struct GhafImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var scheme
    let settings: GhafSettings
    @State private var selectedKind: Kind?
    @State private var pendingRestore: Kind?
    @State private var preview: GhafFileImportPreview?
    @State private var fileURL: URL?
    @State private var message: String?
    @State private var isFailure = false
    @State private var showMail = false
    @State private var showShare = false
    @State private var shareItems: [Any] = []

    private enum Kind: String, Identifiable { case ghaf, expend, other; var id: String { rawValue } }
    private var ar: Bool { settings.languageCode == "ar" }
    private var theme: GhafTheme { GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: scheme == .dark) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "square.and.arrow.down.fill").font(.system(size: 34)).foregroundStyle(theme.accent)
                        .frame(width: 64, height: 64).background(theme.elevatedSurface, in: Circle())
                    Text(ar ? "استيراد بياناتك" : "Bring your data into Ghaf").font(GhafTypography.heading(26, languageCode: settings.languageCode)).foregroundStyle(theme.primaryText).multilineTextAlignment(.center)
                    Text(ar ? "اختر نوع النسخة التي تريد استيرادها." : "Choose the kind of file you want to restore.").font(GhafTypography.body(17, languageCode: settings.languageCode)).foregroundStyle(theme.secondaryText).multilineTextAlignment(.center)
                    VStack(spacing: 12) {
                        choice(ar ? "نسخة غاف الاحتياطية" : "Ghaf backup", subtitle: ar ? "استعادة نسخة غاف بصيغة JSON" : "Restore a Ghaf JSON backup", icon: "externaldrive.fill", kind: .ghaf)
                        choice(ar ? "نسخة Expend" : "Expend backup", subtitle: ar ? "استيراد ملف مُصدَّر من Expend" : "Import an Expend export", icon: "wallet.pass.fill", kind: .expend)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(ar ? "قد لا تُستورد ملفات التطبيقات الأخرى بشكل كامل. إذا لم يعمل ملفك، أرسله إلينا لنضيف دعمه في تحديث قادم." : "Other apps' files may not import perfectly. If yours doesn't work, send it to us and we'll add support in an update.")
                                .font(GhafTypography.body(14, languageCode: settings.languageCode)).foregroundStyle(theme.secondaryText)
                            choice(ar ? "ملف CSV أو JSON آخر" : "Other CSV or JSON", subtitle: ar ? "راجع السجلات قبل الاستيراد" : "Review the rows before importing", icon: "tablecells", kind: .other)
                        }.padding(18).background(theme.surface, in: RoundedRectangle(cornerRadius: 24))
                    }
                    if let message {
                        Text(message).font(GhafTypography.body(15, languageCode: settings.languageCode)).foregroundStyle(isFailure ? theme.over : theme.comfortable).multilineTextAlignment(.center)
                        if fileURL != nil { sendButton }
                    }
                    if let preview { previewCard(preview) }
                }.padding(24)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(ar ? "استيراد" : "Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(ar ? "إغلاق" : "Close") { dismiss() }.foregroundStyle(theme.primaryText) } }
            .fileImporter(isPresented: Binding(get: { selectedKind != nil }, set: { if !$0 { selectedKind = nil } }),
                          allowedContentTypes: [.json, .commaSeparatedText, .plainText], allowsMultipleSelection: false, onCompletion: handlePick)
            .sheet(isPresented: $showMail) { if let fileURL { GhafMailComposer(file: fileURL) { showMail = false } } }
            .sheet(isPresented: $showShare) { GhafShareSheet(items: shareItems) }
            .alert(ar ? "تعذّر الاستيراد" : "Couldn’t import this file", isPresented: Binding(get: { message != nil && isFailure && preview == nil }, set: { if !$0 { message = nil } })) {
                Button(ar ? "حسنًا" : "OK", role: .cancel) { }
            } message: { Text(message ?? "") }
            .alert(ar ? "استبدال البيانات الحالية؟" : "Replace current data?", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })) {
                Button(ar ? "إلغاء" : "Cancel", role: .cancel) { pendingRestore = nil }
                Button(ar ? "متابعة" : "Continue", role: .destructive) { selectedKind = pendingRestore; pendingRestore = nil }
            } message: { Text(ar ? "سيؤدي الاستيراد إلى استبدال السجلات والحسابات الحالية." : "This restore replaces your current records and accounts. Make sure you have a backup before continuing.") }
        }
        .ghafDirection(settings.languageCode)
    }

    private func choice(_ title: String, subtitle: String, icon: String, kind: Kind) -> some View {
        Button { if kind == .other { selectedKind = kind } else { pendingRestore = kind } } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 20, weight: .medium)).foregroundStyle(theme.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(theme.primaryText); Text(subtitle).font(.system(size: 14)).foregroundStyle(theme.secondaryText) }
                Spacer(minLength: 4); Image(systemName: "chevron.forward").font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.secondaryText)
            }.padding(18).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading).background(theme.surface, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain)
    }

    private func previewCard(_ preview: GhafFileImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(ar ? "مراجعة الاستيراد" : "Review before importing").font(.system(size: 20, weight: .semibold)).foregroundStyle(theme.primaryText)
            Text(ar ? "جاهز للاستيراد: \(preview.rows.count) · صفوف متخطاة: \(preview.skipped) · حسابات جديدة: \(preview.accountsToCreate.count)" : "\(preview.rows.count) rows · \(preview.skipped) skipped · \(preview.accountsToCreate.count) accounts to create")
                .font(.system(size: 14, weight: .medium)).foregroundStyle(theme.secondaryText)
            ForEach(Array(preview.rows.prefix(5))) { row in
                HStack { VStack(alignment: .leading, spacing: 3) { Text(row.merchant).font(.system(size: 15, weight: .semibold)); Text(row.date.formatted(date: .abbreviated, time: .omitted)).font(.system(size: 13)).foregroundStyle(theme.secondaryText) }; Spacer(); Text("\(row.amount.formatted()) \(row.currency)").font(.system(size: 15, weight: .semibold)) }.foregroundStyle(theme.primaryText)
            }
            if !preview.accountsToCreate.isEmpty {
                Text(ar ? "سيتم إنشاء هذه الحسابات بعد تأكيدك:" : "These accounts will be created only after you confirm:").font(.system(size: 14)).foregroundStyle(theme.secondaryText)
                ForEach(preview.accountsToCreate, id: \.self) { Text("• \($0)").font(.system(size: 15, weight: .medium)).foregroundStyle(theme.primaryText) }
            }
            sendButton
            Button(ar ? "تأكيد الاستيراد" : "Confirm import") { commit(preview) }
                .ghafProminentButton(theme: theme, languageCode: ar ? "ar" : "en")
        }.padding(20).background(theme.surface, in: RoundedRectangle(cornerRadius: 24))
    }

    private var sendButton: some View {
        Button(ar ? "إرسال هذا الملف إلى المطوّر" : "Send this file to the developer") { if let fileURL { compose(fileURL) } }
            .font(.system(size: 15, weight: .medium)).foregroundStyle(theme.accent).frame(minHeight: 44)
    }

    /// A restored Ghaf backup is a set-up app: never drop the user back into first-run onboarding.
    private func markSetUp() {
        guard let restored = try? context.fetch(FetchDescriptor<GhafSettings>()).first else { return }
        restored.hasCompletedOnboarding = true
        try? context.save()
    }

    private func handlePick(_ result: Result<[URL], Error>) {
        guard let kind = selectedKind else { return }; selectedKind = nil
        do {
            let url = try result.get().first ?? { throw GhafFileImportError.unsupported }()
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let localFile = FileManager.default.temporaryDirectory.appendingPathComponent("ghaf-import-\(UUID().uuidString).\(url.pathExtension)")
            try Data(contentsOf: url).write(to: localFile, options: .atomic)
            fileURL = localFile; isFailure = false; message = nil
            switch kind {
            case .ghaf:
                let unassigned = try GhafBackupService.restore(from: localFile, context: context)
                markSetUp()
                message = ar ? "تمت استعادة نسخة غاف. سجلات بلا حساب: \(unassigned)." : "Ghaf backup restored. Records left without an account: \(unassigned)."
            case .expend: let result = try GhafExpendImportService.importFile(from: localFile, context: context); message = ar ? "تم استيراد \(result.transactionsImported) عملية من Expend." : "Imported \(result.transactionsImported) transactions from Expend."
            case .other: preview = try GhafFileImport.preview(localFile, context: context)
            }
        } catch { isFailure = true; message = ar ? "تعذّر استيراد الملف. تحقّق من نوعه ومحتواه، ثم حاول مجددًا." : error.localizedDescription }
    }

    private func commit(_ preview: GhafFileImportPreview) {
        do {
            let result = try GhafFileImport.commit(preview, createAccounts: true, context: context)
            self.preview = nil; isFailure = false
            message = ar ? "تم استيراد \(result.imported) معاملة، وتخطي \(result.duplicates) مكررة." : "Imported \(result.imported) transactions. \(result.duplicates) duplicates skipped."
        } catch { isFailure = true; message = ar ? "تعذّر حفظ الاستيراد. لم تُحفظ التغييرات." : error.localizedDescription }
    }
    private func compose(_ url: URL) { if MFMailComposeViewController.canSendMail() { showMail = true } else { prepareShare(url) } }
    private func prepareShare(_ url: URL) { shareItems = [url]; showShare = true }
}

private struct GhafMailComposer: UIViewControllerRepresentable {
    let file: URL
    let completion: () -> Void
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController(); composer.setToRecipients([GhafLinks.supportEmail]); composer.setSubject("Ghaf import support"); composer.setMessageBody("Please review this file to help add import support.", isHTML: false)
        if let data = try? Data(contentsOf: file) { composer.addAttachmentData(data, mimeType: file.pathExtension.lowercased() == "csv" ? "text/csv" : "application/json", fileName: file.lastPathComponent) }
        composer.mailComposeDelegate = context.coordinator; return composer
    }
    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let completion: () -> Void
        init(completion: @escaping () -> Void) { self.completion = completion }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) { completion(); controller.dismiss(animated: true) }
    }
}

private struct GhafShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
