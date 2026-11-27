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
                    subtitle: isArabic ? "تاريخ السريان: ٢٥ نوفمبر ٢٠٢٦" : "Effective date: 25 November 2026",
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
                    : "Ghaf processes only message text that you explicitly pass to its Capture Bank Alert action through Apple Shortcuts. Ghaf does not independently read SMS messages or other apps' notifications."
                )

                section(
                    isArabic ? "الإضافة بالصوت" : "Voice entry",
                    isArabic
                    ? "عند بدء التسجيل، يطلب غاف إذن الميكروفون والتعرّف على الكلام. يستخدم iOS لإنشاء نص قابل للمراجعة. قد تستخدم Apple خدمتها السحابية عندما لا تتوفر المعالجة على الجهاز، وفق شروط Apple. لا ترسل الإضافة بالصوت الصوت أو النص إلى خادم تابع لغاف."
                    : "When you start voice entry, Ghaf requests microphone and speech-recognition permission. iOS creates an editable transcript. Apple may use its speech service when on-device recognition is unavailable, subject to Apple's terms. Voice entry does not send audio or transcripts to a Ghaf-operated server."
                )

                section(
                    isArabic ? "ذكاء غاف" : "Ghaf AI",
                    isArabic
                    ? "ذكاء غاف متوقف حتى تفعّله، ولا يرسل بيانات إلا عندما تسأله. عند الكتابة: يُرسَل سؤالك وآخر رسائل المحادثة وملخص المجاميع والحسابات وأبرز التجار والذكريات المحفوظة اللازمة للإجابة عبر خادم غاف إلى Gemini من Google أو Cloudflare Workers AI. لا تُرسَل قائمة العمليات ولا أرقام الحسابات. الردود المنطوقة: يُرسَل نص الرد عبر خادم غاف إلى Google لقراءته بصوت مسموع. المحادثة الصوتية: ينتقل صوتك من جهازك مباشرةً إلى خدمة Gemini Live من Google، ويكتفي خادم غاف بإصدار مفتاح دخول قصير الصلاحية. لا يحفظ غاف هذا المحتوى ولا يطّلع عليه. تعالجه Google وCloudflare وفق شروط واجهاتهما البرمجية، وبحسب الخطة التي يستخدمها غاف لديهما قد تحتفظان به لفترة محدودة، وقد تستخدمانه في الخطط المجانية لتحسين خدماتهما."
                    : "Ghaf AI is off until you turn it on, and it sends data only when you ask it something. Typed questions: your question, recent messages in the chat and a summary of the totals, accounts, top merchants and saved memories needed to answer travel through Ghaf's server to Google Gemini or Cloudflare Workers AI. Your transaction list and account numbers aren't sent. Spoken replies: the reply text goes through Ghaf's server to Google to be read aloud. Voice conversations: your voice goes directly from your iPhone to Google's Gemini Live service; Ghaf's server only issues a short-lived access key. Ghaf doesn't store or read this content. Google and Cloudflare process it under their API terms; depending on the plan Ghaf uses with them, they may keep it for a limited time and, on free plans, use it to improve their services."
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
                    ? "يمكنك تصدير نسخة احتياطية بصيغة JSON واستعادتها يدوياً. الملف غير مشفّر وقد يحتوي على معلومات مالية حساسة، فاحفظه في مكان آمن. قد تتيح قائمة المشاركة حفظه في iCloud Drive أو Google Drive أو غيرهما، وتخضع هذه الخدمات لسياساتها الخاصة. إذا ربطت Google Drive من الإعدادات، يحفظ غاف النسخة أو يستعيدها عندما تطلب ذلك فقط، في مجلد خاص بالتطبيق داخل Drive لا يستخدمه إلا غاف، ولا يستطيع غاف رؤية ملفاتك الأخرى. يعرض غاف بريد حساب Google لتعرف الحساب المرتبط. عند فصل الحساب يُزال وصول غاف من هذا الجهاز."
                    : "You can export and restore a JSON backup manually. The file is not encrypted and may contain sensitive financial information; store it securely. The share sheet may save it to iCloud Drive, Google Drive or elsewhere; those services follow their own privacy policies. If you connect Google Drive in Settings, Ghaf saves or restores a backup only when you ask, in a private app folder in your Drive that only Ghaf can use; Ghaf can't see your other Drive files. Ghaf shows your Google account email so you know which account is connected. Disconnecting removes Ghaf's access from this iPhone."
                )

                section(
                    isArabic ? "الميزات غير المتاحة حالياً" : "Features not currently available",
                    isArabic
                    ? "النسخ الاحتياطي السحابي التلقائي وتسجيل الدخول باستخدام Apple غير متاحين حالياً."
                    : "Automatic cloud backup and Sign in with Apple are not currently available."
                )

                section(
                    isArabic ? "مشاركة البيانات والإعلانات" : "Data sharing and advertising",
                    isArabic
                    ? "لا يعرض غاف إعلانات ولا يتتبعك ولا يبيع معلوماتك. عند استخدام ذكاء غاف يسجّل الخادم إحصاءات مجهولة فقط، والغرض منها أمران: تطبيق حدود الاستخدام العادل، ومعرفة تكلفة تشغيل ذكاء غاف. لا تتضمن هذه الإحصاءات اسمك ولا أسئلتك ولا الإجابات ولا صوتك ولا أي بيانات مالية، ولا تُستخدم لتتبعك أو لبناء ملف عنك، ولا يطّلع عليها إلا مطوّر غاف."
                    : "Ghaf does not show ads, does not track you and does not sell your information. When you use Ghaf AI, the server records anonymous statistics for two reasons only: to apply fair-use limits and to see what running Ghaf AI costs. They never include your name, questions, answers, voice or any financial data, are never used to track you or build a profile, and only Ghaf's developer can see them."
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
            .ghafScreenPadding().padding(.vertical, 20)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .ghafBackground(theme: theme)
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
