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
    @State private var isFileImporterPresented = false
    @State private var pendingRestore: Kind?
    @State private var preview: GhafFileImportPreview?
    @State private var fileURL: URL?
    @State private var message: String?
    @State private var isFailure = false
    @State private var showMail = false

    private enum Kind: String, Identifiable { case ghaf, expend, other; var id: String { rawValue } }
    private var ar: Bool { settings.languageCode == "ar" }
    private var theme: GhafTheme { GhafTheme.resolve(name: settings.themeName, appearanceMode: settings.appearanceMode, systemIsDark: scheme == .dark) }
    private var mailIsConfigured: Bool { MFMailComposeViewController.canSendMail() }
    private var canEmailDeveloper: Bool { mailIsConfigured }

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
                        choice(ar ? "نسخة من تطبيق ميزانية آخر" : "Other budgeting app backup", subtitle: ar ? "استيراد نسخة مدعومة من تطبيق آخر" : "Import a supported backup from another app", icon: "wallet.pass.fill", kind: .expend)
                        VStack(alignment: .leading, spacing: 12) {
                            Text(ar ? "قد لا تُستورد ملفات التطبيقات الأخرى بشكل كامل. إذا لم يعمل ملفك، أرسله إلينا لنضيف دعمه في تحديث قادم." : "Other apps' files may not import perfectly. If yours doesn't work, send it to us and we'll add support in an update.")
                                .font(GhafTypography.body(14, languageCode: settings.languageCode)).foregroundStyle(theme.secondaryText)
                            choice(ar ? "ملف CSV أو JSON آخر" : "Other CSV or JSON", subtitle: ar ? "راجع السجلات قبل الاستيراد" : "Review the rows before importing", icon: "tablecells", kind: .other)
                        }.padding(18).background(theme.surface, in: RoundedRectangle(cornerRadius: 24))
                    }
                    sendButton
                    if let message {
                        Text(message).font(GhafTypography.body(15, languageCode: settings.languageCode)).foregroundStyle(isFailure ? theme.over : theme.comfortable).multilineTextAlignment(.center)
                    }
                    if let preview { previewCard(preview) }
                }.padding(24)
            }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle(ar ? "استيراد" : "Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(ar ? "إغلاق" : "Close") { dismiss() }.foregroundStyle(theme.primaryText) } }
            // Keep picker visibility separate from its route. SwiftUI dismisses
            // the picker before calling `onCompletion`, so clearing the route
            // through the presentation binding can silently skip the import.
            .fileImporter(isPresented: $isFileImporterPresented,
                          allowedContentTypes: [.json, .commaSeparatedText, .plainText], allowsMultipleSelection: false, onCompletion: handlePick)
            .sheet(isPresented: $showMail) { if let fileURL { GhafMailComposer(file: fileURL, arabic: ar) { showMail = false } } }
            .alert(ar ? "تعذّر الاستيراد" : "Couldn’t import this file", isPresented: Binding(get: { message != nil && isFailure && preview == nil }, set: { if !$0 { message = nil } })) {
                Button(ar ? "حسنًا" : "OK", role: .cancel) { }
            } message: { Text(message ?? "") }
            .alert(ar ? "استبدال البيانات الحالية؟" : "Replace current data?", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })) {
                Button(ar ? "إلغاء" : "Cancel", role: .cancel) { pendingRestore = nil }
                Button(ar ? "متابعة" : "Continue", role: .destructive) {
                    selectedKind = pendingRestore
                    pendingRestore = nil
                    isFileImporterPresented = true
                }
            } message: { Text(ar ? "سيؤدي الاستيراد إلى استبدال السجلات والحسابات الحالية." : "This restore replaces your current records and accounts. Make sure you have a backup before continuing.") }
        }
        .ghafDirection(settings.languageCode)
        .onAppear { runDebugImportFixtureIfRequested() }
    }

    private func runDebugImportFixtureIfRequested() {
#if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard GhafScreenshotFixture.importSheetRoute,
              let kindIndex = args.firstIndex(of: "-GhafImportKind"), args.indices.contains(kindIndex + 1),
              let pathIndex = args.firstIndex(of: "-GhafImportFile"), args.indices.contains(pathIndex + 1),
              let kind = Kind(rawValue: args[kindIndex + 1]) else { return }
        selectedKind = kind
        handlePick(.success([URL(fileURLWithPath: args[pathIndex + 1])]))
#endif
    }

    private func choice(_ title: String, subtitle: String, icon: String, kind: Kind) -> some View {
        Button {
            if kind == .other {
                selectedKind = kind
                isFileImporterPresented = true
            } else {
                pendingRestore = kind
            }
        } label: {
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
            Button(ar ? "تأكيد الاستيراد" : "Confirm import") { commit(preview) }
                .ghafProminentButton(theme: theme, languageCode: ar ? "ar" : "en")
        }.padding(20).background(theme.surface, in: RoundedRectangle(cornerRadius: 24))
    }

    private var sendButton: some View {
        VStack(spacing: 3) {
            Button(ar ? "هل حدثت مشكلة بعد الاستيراد؟ أرسل الملف للمطوّر" : "Something wrong after import? Send the file to the developer") {
                if let fileURL { compose(fileURL) }
            }
            .font(GhafTypography.body(12, languageCode: settings.languageCode, weight: .medium))
            .foregroundStyle(theme.accent).frame(minHeight: 44)
            .disabled(fileURL == nil || !canEmailDeveloper)
            .opacity(fileURL != nil && canEmailDeveloper ? 1 : 0.45)
            Text(ar ? "نستخدم الملف لإصلاح غاف فقط، ولا نشاركه مع جهات أخرى." : "We use the file only to fix Ghaf and do not share it further.")
                .font(GhafTypography.body(10, languageCode: settings.languageCode)).foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if !mailIsConfigured {
                Text(ar ? "لإرسال الملف، أضف حساباً إلى تطبيق Mail." : "To send the file, set up an account in the Mail app.")
                    .font(GhafTypography.body(10, languageCode: settings.languageCode)).foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
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
                let result = try GhafBackupService.restore(from: localFile, context: context)
                markSetUp()
                message = ar
                    ? "اكتمل الاستيراد · الحسابات: \(result.accountsImported) · المعاملات: \(result.transactionsImported) · الاشتراكات: \(result.subscriptionsImported) · بلا حساب: \(result.recordsWithoutAccounts)"
                    : "Import complete · Accounts: \(result.accountsImported) · Transactions: \(result.transactionsImported) · Subscriptions: \(result.subscriptionsImported) · Unassigned: \(result.recordsWithoutAccounts)"
            case .expend: let result = try GhafExpendImportService.importFile(from: localFile, context: context); message = ar ? "تم استيراد \(result.transactionsImported) عملية من تطبيق ميزانية آخر." : "Imported \(result.transactionsImported) transactions from another budgeting app."
            case .other: preview = try GhafFileImport.preview(localFile, context: context)
            }
        } catch {
            if isPickerCancellation(error) { return }
            isFailure = true
            message = importErrorMessage(error)
        }
    }

    private func isPickerCancellation(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSCocoaErrorDomain && nsError.code == NSUserCancelledError
    }

    private func importErrorMessage(_ error: Error) -> String {
        switch error {
        case GhafBackupError.unsupportedVersion:
            return ar ? "إصدار نسخة غاف هذه غير مدعوم." : "This Ghaf backup version is not supported."
        case GhafBackupError.invalidBackup:
            return ar ? "ملف نسخة غاف تالف أو غير مكتمل." : "This Ghaf backup is damaged or incomplete."
        case GhafExpendImportError.unreadableFile:
            return ar ? "تعذرت قراءة الملف المحدد." : "The selected file could not be read."
        case GhafExpendImportError.unsupportedFormat:
            return ar ? "ملف JSON هذا ليس تصديرًا مدعومًا من تطبيق ميزانية آخر." : "This JSON file is not a supported export from another budgeting app."
        case GhafExpendImportError.noValidWallets:
            return ar ? "لم نعثر على محافظ صالحة في الملف." : "No valid wallets were found in the file."
        case GhafExpendImportError.invalidTransactionData:
            return ar ? "بيانات المعاملات في الملف غير مكتملة." : "The transaction data in the file is incomplete."
        case GhafExpendImportError.walletBalanceMismatch:
            return ar ? "أرصدة المحافظ في الملف لا تتطابق مع سجل المعاملات. لم يتم الاستيراد."
                : "The wallet balances do not match the file's transactions. Nothing was imported."
        case GhafFileImportError.unsupported:
            return ar ? "صيغة الملف غير مدعومة. اختر ملف CSV أو JSON للمعاملات."
                : "This file format isn't supported. Choose a CSV or transaction JSON file."
        case GhafFileImportError.noTransactions:
            return ar ? "لم نعثر على معاملات بتاريخ ومبلغ ووصف صالح."
                : "No transactions with a valid date, amount, and description were found."
        case GhafCore.DelimitedImportError.unclosedQuote:
            return ar ? "أحد الحقول المحاطة بعلامتي اقتباس غير مكتمل." : "A quoted field is missing its closing quotation mark."
        case GhafCore.DelimitedImportError.noRows:
            return ar ? "لا يحتوي الملف على صفوف بيانات." : "The file contains no data rows."
        default:
            return ar ? "تعذر استيراد الملف. تحقق من نوعه ومحتواه، ثم حاول مجددًا."
                : "The file couldn't be imported. Check its type and contents, then try again."
        }
    }

    private func commit(_ preview: GhafFileImportPreview) {
        do {
            let result = try GhafFileImport.commit(preview, createAccounts: true, context: context)
            self.preview = nil; isFailure = false
            message = ar ? "تم استيراد \(result.imported) معاملة، وتخطي \(result.duplicates) مكررة." : "Imported \(result.imported) transactions. \(result.duplicates) duplicates skipped."
        } catch { isFailure = true; message = ar ? "تعذّر حفظ الاستيراد. لم تُحفظ التغييرات." : error.localizedDescription }
    }
    private func compose(_ url: URL) { guard canEmailDeveloper else { return }; showMail = true }
}

private struct GhafMailComposer: UIViewControllerRepresentable {
    let file: URL
    let arabic: Bool
    let completion: () -> Void
    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController(); composer.setToRecipients([GhafLinks.supportEmail])
        composer.setSubject(arabic ? "مساعدة في استيراد غاف" : "Ghaf import support")
        composer.setMessageBody(arabic ? "أرفقت الملف الذي لم يُستورد كما يجب، لمساعدتكم في إصلاح المشكلة." : "I've attached the file that didn't import correctly, to help you fix it.", isHTML: false)
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
