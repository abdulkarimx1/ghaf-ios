import Foundation

/// Replies for messages that are not about money, used when the on-device model is not available.
/// Friendly with a light touch of humour, always steering back to what Ghaf can do, and never
/// repeating a reply that is in `avoiding` while another variant is left.
public enum GhafSmallTalk {

    public enum Topic: CaseIterable {
        case greeting, thanks, identity, weather, joke, time, food, sports, love, insult
    }

    private static let triggers: [Topic: [String]] = [
        .greeting: ["hello", " hi ", " hi,", " hey ", " hey,", "good morning", "good evening", "salam", "السلام", "مرحبا", "هلا", "صباح", "مساء"],
        .thanks: ["thank", "thx", "شكرا", "مشكور", "يعطيك العافية"],
        .identity: ["who are you", "what are you", "your name", "are you human", "are you real", "من أنت", "مين انت", "شو اسمك", "ما اسمك"],
        .weather: ["weather", " rain", "temperature", "forecast", "sunny", "الطقس", "الجو ", "الجو؟", "حرارة", "مطر"],
        .joke: ["joke", "funny", "make me laugh", "نكتة", "نكته", "ضحكني"],
        .time: ["what time", "what's the time", "what day is", "كم الساعة", "كم الساعه", "اي يوم", "أي يوم"],
        .food: ["recipe", "cook", "hungry", "طبخ", "وصفة", "جوعان"],
        .sports: ["football", " match ", "score", "messi", "ronaldo", "كورة", "مباراة", "مباراه"],
        .love: ["love you", "marry me", "أحبك", "احبك"],
        .insult: ["stupid", "useless", "dumb", "غبي", "فاشل"]
    ]

    private static let replies: [Topic: (en: [String], ar: [String])] = [
        .greeting: (
            ["Hey! Ready when you are. Ask about your spending or tell me what you bought.",
             "Hello! Your money and I are both here. What would you like to know?",
             "Hi there. Want this week's spending, your balance, or to log a purchase?"],
            ["هلا والله! اسألني عن مصروفك أو قل لي وش اشتريت.",
             "مرحباً! أنا وأموالك جاهزين. وش تبي تعرف؟",
             "أهلاً! تبي مصروف الأسبوع، رصيدك، أو نسجل عملية؟"]),
        .thanks: (
            ["Anytime. Your wallet thanks you too.", "Happy to help. Anything else on your money?",
             "You're welcome. I'll keep the numbers tidy."],
            ["العفو! محفظتك تشكرك بعد.", "بالخدمة دايماً. في شي ثاني عن فلوسك؟", "ولا يهمك، الأرقام عندي مرتبة."]),
        .identity: (
            ["I'm Ghaf AI, your money assistant. I only quote numbers from your own records.",
             "Ghaf AI here: part calculator, part note-taker, zero gossip about your spending.",
             "I'm the assistant inside Ghaf. I read your ledger, never invent it."],
            ["أنا غاف، مساعدك المالي. أعطيك أرقامك من سجلاتك فقط.",
             "معك غاف: حاسبة ومدوّنة، وأسرار مصروفك في أمان.",
             "أنا المساعد داخل غاف، أقرأ سجلاتك ولا أخترع أرقام."]),
        .weather: (
            ["I can't see the sky, but I can see your spending forecast. Want this week's numbers?",
             "No weather radar here. The only thing I forecast is your next subscription renewal.",
             "Probably sunny, it's the Gulf. Shall I check how your budget is holding up instead?"],
            ["ما أشوف السماء، بس أشوف توقعات مصروفك. تبي أرقام الأسبوع؟",
             "ما عندي رادار طقس. اللي أتوقعه بس موعد تجديد اشتراكاتك.",
             "غالباً مشمس، نحن في الخليج. أشيك لك على ميزانيتك بدالها؟"]),
        .joke: (
            ["Why did the dirham stay calm? It had a balanced account. Want to check yours?",
             "My best joke is a subscription you forgot about. Shall I list what's due?",
             "I tried to save a joke, but it was spent before payday. Ask me about your spending."],
            ["ليش الدرهم دايماً مرتاح؟ لأن حسابه متوازن. نشيك على حسابك؟",
             "أحلى نكتة عندي اشتراك ناسيه. أعرض لك المستحق؟",
             "حاولت أوفر نكتة بس انصرفت قبل الراتب. اسألني عن مصروفك."]),
        .time: (
            ["Your phone's clock is better at that than me. I'm better at your spending today.",
             "Time is money, and money I can help with. Want today's total?"],
            ["ساعة جوالك أدق مني، بس أنا أدق في مصروف اليوم.", "الوقت من ذهب، والذهب اختصاصي. تبي مجموع اليوم؟"]),
        .food: (
            ["I don't cook, but I can tell you how much restaurants cost you this month.",
             "No recipes here. Just tell me what lunch cost and I'll log it."],
            ["ما أطبخ، بس أقدر أقول لك كم صرفت على المطاعم هالشهر.", "ما عندي وصفات. قل لي كم كلفك الغداء وأسجله."]),
        .sports: (
            ["I don't track scores, only your spending streaks. Want to see this month?",
             "The only match I follow is your income versus spending."],
            ["ما أتابع النتائج، أتابع مصروفك بس. تبي تشوف هالشهر؟", "المباراة الوحيدة اللي أتابعها: دخلك ضد مصروفك."]),
        .love: (
            ["That's sweet. I show my love by keeping your numbers accurate.",
             "I'm flattered. My love language is a balanced budget."],
            ["كلامك حلو. أنا أعبّر عن حبي بأرقام دقيقة.", "تسلم! لغة الحب عندي ميزانية متوازنة."]),
        .insult: (
            ["Fair, I'm still learning. Tell me what went wrong and I'll do better.",
             "Ouch. Correct me once and I'll remember it next time."],
            ["معك حق، لسا أتعلم. قل لي وش الغلط وأتحسن.", "أوف! صححني مرة وأتذكرها المرة الجاية."])
    ]

    /// The off-topic subject of `message`, if it is one Ghaf has a reply for. Callers check money
    /// questions first, so "hi, what did I spend?" is still answered as a money question.
    public static func topic(of message: String) -> Topic? {
        let text = " " + message.lowercased() + " "
        return Topic.allCases.first { topic in triggers[topic, default: []].contains { text.contains($0) } }
    }

    public static func reply(to message: String, languageCode: String, avoiding: Set<String> = []) -> String? {
        guard let topic = topic(of: message), let options = replies[topic] else { return nil }
        return pick(languageCode == "ar" ? options.ar : options.en, avoiding: avoiding)
    }

    /// For messages Ghaf did not understand: quotes what the user wrote and varies the wording.
    public static func notUnderstood(_ message: String, languageCode: String, avoiding: Set<String> = []) -> String {
        let quoted = String(message.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        let options = languageCode == "ar" ? [
            "ما فهمت «\(quoted)» تماماً. جرّب: «كم صرفت هالشهر؟» أو «٣٥ درهم غداء».",
            "«\(quoted)» خارج اختصاصي شوي. أقدر أعطيك رصيدك، أكثر فئة صرفت فيها، أو الاشتراكات القادمة.",
            "سؤال حلو، بس ما عندي بيانات عن «\(quoted)». اسألني عن مصروفك أو دخلك أو اشتراكاتك.",
            "خلني أركز على فلوسك 😄 بدل «\(quoted)»: تبي مقارنة هالشهر بالشهر الماضي؟"
        ] : [
            "I didn't quite catch \u{201C}\(quoted)\u{201D}. Try \u{201C}How much did I spend this month?\u{201D} or \u{201C}35 AED lunch\u{201D}.",
            "\u{201C}\(quoted)\u{201D} is a bit outside my lane. I can show your balance, top category or upcoming subscriptions.",
            "Good question, but I have no data on \u{201C}\(quoted)\u{201D}. Ask me about spending, income or subscriptions.",
            "Let me stick to your money instead of \u{201C}\(quoted)\u{201D}. Want this month compared with last month?"
        ]
        return pick(options, avoiding: avoiding)
    }

    static func pick(_ options: [String], avoiding: Set<String>) -> String {
        let fresh = options.filter { !avoiding.contains($0) }
        return (fresh.isEmpty ? options : fresh).randomElement() ?? options[0]
    }
}
