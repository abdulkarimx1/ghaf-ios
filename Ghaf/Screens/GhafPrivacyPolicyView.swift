import SwiftUI

struct GhafPrivacyPolicyView: View {
    @Environment(\.colorScheme) private var systemColorScheme
    let settings: GhafSettings

    private var theme: GhafTheme {
        GhafTheme.resolve(
            name: settings.themeName,
            appearanceMode: settings.appearanceMode,
            systemIsDark: systemColorScheme == .dark
        )
    }

    private var isArabic: Bool { settings.languageCode == "ar" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                GhafScreenTitle(
                    title: isArabic ? "سياسة الخصوصية" : "Privacy policy",
                    subtitle: isArabic ? "تاريخ السريان: ٧ نوفمبر ٢٠٢٦" : "Effective date: 7 November 2026",
                    languageCode: settings.languageCode,
                    theme: theme
                )

                section(
                    isArabic ? "كيف يتعامل غاف مع بياناتك" : "How Ghaf handles your data",
                    isArabic
                    ? "غاف تطبيق مالي شخصي على iPhone. تُحفظ سجلاتك المالية محلياً على جهازك، ولا يشغّل غاف حالياً خدمة حسابات أو خادماً لحفظ بياناتك المالية."
                    : "Ghaf is a personal finance app for iPhone. Your financial records are stored locally on your device. Ghaf does not currently operate an account service or a server that stores your financial data."
                )

                section(
                    isArabic ? "السجلات المالية" : "Financial records",
                    isArabic
                    ? "تُحفظ العمليات وأسماء المتاجر والفئات والأرصدة والحسابات والميزانيات والملاحظات والإعدادات في قاعدة بيانات محلية داخل التطبيق."
                    : "Transactions, merchant names, categories, balances, accounts, budgets, notes and settings are stored in the app's local database."
                )

                section(
                    isArabic ? "الرسائل البنكية" : "Bank messages",
                    isArabic
                    ? "يعالج غاف فقط نص الرسالة الذي تختار تمريره صراحةً إلى إجراء تسجيل الرسالة البنكية عبر تطبيق الاختصارات من Apple. لا يقرأ غاف رسائل SMS أو إشعارات التطبيقات من تلقاء نفسه."
                    : "Ghaf processes only message text that you explicitly pass to its Log Bank Message action through Apple Shortcuts. Ghaf does not independently read SMS messages or other apps' notifications."
                )

                section(
                    isArabic ? "الإضافة بالصوت" : "Voice entry",
                    isArabic
                    ? "عند بدء التسجيل، يطلب غاف إذن الميكروفون والتعرّف على الكلام. يستخدم iOS لإنشاء نص قابل للمراجعة. قد تستخدم Apple خدمتها السحابية عندما لا تتوفر المعالجة على الجهاز، وفق شروط Apple. لا يرسل غاف الصوت أو النص إلى خادم تابع له."
                    : "When you start voice entry, Ghaf requests microphone and speech-recognition permission. iOS creates an editable transcript. Apple may use its speech service when on-device recognition is unavailable, subject to Apple's terms. Ghaf does not send audio or transcripts to a Ghaf-operated server."
                )

                section(
                    isArabic ? "الحماية البيومترية" : "Biometric protection",
                    isArabic
                    ? "عند تفعيل Face ID أو رمز دخول الجهاز، يتولى iOS عملية التحقق. لا يتلقى غاف بياناتك البيومترية ولا يخزنها."
                    : "When Face ID or device passcode protection is enabled, iOS handles authentication. Ghaf does not receive or store biometric data."
                )

                section(
                    isArabic ? "النسخ الاحتياطي والمشاركة" : "Backups and sharing",
                    isArabic
                    ? "يوفر غاف حالياً تصدير JSON واستعادته يدوياً. الملف غير مشفّر وقد يحتوي على معلومات مالية حساسة؛ احفظه في مكان خاص ومحمي. قد تتيح قائمة المشاركة حفظ الملف في iCloud Drive أو Google Drive أو وجهة أخرى، وتخضع هذه الخدمات لسياساتها الخاصة. لا يرفع غاف النسخ تلقائياً."
                    : "Ghaf currently supports manual JSON export and restore. The file is not encrypted and may contain sensitive financial information; store it securely. The iOS share sheet may let you save it to iCloud Drive, Google Drive or another destination. Those services follow their own privacy policies. Ghaf does not upload backups automatically."
                )

                section(
                    isArabic ? "الميزات غير المتاحة حالياً" : "Features not currently available",
                    isArabic
                    ? "لم يتم تنفيذ النسخ السحابي التلقائي أو الربط المباشر بحساب Google Drive أو تسجيل الدخول باستخدام Apple."
                    : "Automatic cloud backup, direct Google Drive account integration and Sign in with Apple are not currently implemented."
                )

                section(
                    isArabic ? "مشاركة البيانات والإعلانات" : "Data sharing and advertising",
                    isArabic
                    ? "لا يشغّل غاف حالياً إعلانات أو تتبعاً بين التطبيقات أو جمعاً للتحليلات، ولا يبيع المعلومات الشخصية."
                    : "Ghaf does not currently operate advertising, cross-app tracking or analytics collection, and does not sell personal information."
                )

                section(
                    isArabic ? "الاحتفاظ بالبيانات وحذفها" : "Data retention and deletion",
                    isArabic
                    ? "تبقى سجلاتك على الجهاز حتى تحذفها أو تزيل التطبيق. يمكنك تصدير نسخة قبل حذف البيانات. يجب حذف النسخ المحفوظة خارج غاف بشكل منفصل من وجهتها."
                    : "Your records remain on the device until you delete them or remove the app. You can export a copy before deleting data. Backups saved outside Ghaf must be deleted separately from their destination."
                )

                section(
                    isArabic ? "التواصل" : "Contact",
                    isArabic
                    ? "المطور: عبدالكريم بياسي. ستُدرج وسيلة التواصل الخاصة بالخصوصية في صفحة غاف على App Store عند النشر."
                    : "Developer: Abdulkarim Bayassi. A privacy contact channel will be provided on Ghaf's App Store listing when published."
                )

                Text(isArabic
                     ? "قد تُحدّث هذه السياسة عند إضافة ميزات جديدة أو إجراء تغييرات جوهرية."
                     : "This policy may be updated when new features are introduced or material changes are made.")
                    .font(GhafTypography.body(11, languageCode: settings.languageCode))
                    .foregroundStyle(theme.secondaryText)
                    .padding(.top, 4)
            }
            .padding(20)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.never)
        .scrollIndicators(.hidden)
        .background(theme.background.ignoresSafeArea())
        .navigationTitle(isArabic ? "الخصوصية" : "Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.locale, Locale(identifier: settings.languageCode))
        .environment(\.layoutDirection, isArabic ? .rightToLeft : .leftToRight)
    }

    private func section(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(GhafTypography.heading(17, languageCode: settings.languageCode))
                .foregroundStyle(theme.primaryText)
            Text(detail)
                .font(GhafTypography.body(13, languageCode: settings.languageCode))
                .foregroundStyle(theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .ghafCard(theme: theme, radius: 18)
    }
}
