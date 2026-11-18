import Foundation

/// Built-in GCC spending categories with subcategories and the English, Arabic and Gulf-dialect
/// words people use for them. New users start from these; existing users get them as suggestions
/// when none of their own categories fits.
public enum CategoryTaxonomy {

    public struct Subcategory {
        public let name: String
        public let arabic: String
        public let words: [String]
    }

    public struct Category {
        public let name: String
        public let arabic: String
        public let icon: String
        public let color: String
        /// Other names users give this category ("Car" for Car & Transport).
        public let aliases: [String]
        public let subcategories: [Subcategory]
        public let isIncome: Bool
    }

    static func sub(_ name: String, _ arabic: String, _ words: [String]) -> Subcategory {
        Subcategory(name: name, arabic: arabic, words: words)
    }

    public static let all: [Category] = [
        Category(name: "Food & Dining", arabic: "الطعام والمطاعم", icon: "fork.knife", color: "orange",
                 aliases: ["Food", "Dining", "Restaurants", "Eating out"], subcategories: [
            sub("Restaurants", "مطاعم", ["restaurant", "dinner out", "mandi", "biryani", "machboos", "majboos", "sushi", "steak", "مطعم", "مندي", "برياني", "مجبوس", "كبسة"]),
            sub("Cafés & Karak", "مقاهي وكرك", ["cafe", "coffee", "karak", "chai", "latte", "starbucks", "tim hortons", "costa", "caribou", "dunkin", "قهوة", "كرك", "شاي", "كافيه", "كوفي", "مقهى"]),
            sub("Cafeteria", "كافتيريا", ["cafeteria", "sandwich", "shawarma", "falafel", "paratha", "كافتيريا", "شاورما", "فلافل", "ساندويش", "سندويش", "براتا"]),
            sub("Fast food", "وجبات سريعة", ["burger", "pizza", "fries", "mcdonalds", "kfc", "hardees", "burger king", "subway", "popeyes", "شيك شاك", "برجر", "بيتزا", "ماكدونالدز", "هرفي", "البيك", "albaik", "herfy"]),
            sub("Delivery", "توصيل", ["talabat", "deliveroo", "noon food", "careem food", "hungerstation", "jahez", "keeta", "طلبات", "هنقرستيشن", "جاهز", "كيتا", "ديليفرو"]),
            sub("Breakfast", "فطور", ["breakfast", "فطور", "ريوق"]),
            sub("Lunch", "غداء", ["lunch", "غداء", "غدا"]),
            sub("Dinner", "عشاء", ["dinner", "supper", "عشاء", "عشا"]),
            sub("Bakery & Sweets", "مخبز وحلويات", ["bakery", "cake", "dessert", "ice cream", "chocolate", "kunafa", "luqaimat", "dates", "patchi", "bateel", "مخبز", "كيك", "حلويات", "كنافة", "لقيمات", "تمر", "آيس كريم", "بتيل"])
        ], isIncome: false),
        Category(name: "Groceries", arabic: "البقالة", icon: "cart.fill", color: "green",
                 aliases: ["Grocery", "Supermarket", "Groceries"], subcategories: [
            sub("Supermarket", "سوبرماركت", ["supermarket", "hypermarket", "carrefour", "lulu", "spinneys", "waitrose", "nesto", "danube", "panda", "othaim", "tamimi", "union coop", "coop", "geant", "choithrams", "كارفور", "لولو", "الدانوب", "بنده", "العثيم", "التميمي", "جمعية", "سوبرماركت", "هايبر"]),
            sub("Baqala", "بقالة", ["baqala", "grocery", "groceries", "mini mart", "بقالة", "بقاله", "دكان"]),
            sub("Meat & Fish", "لحوم وأسماك", ["butcher", "meat", "chicken", "fish", "seafood", "ملحمة", "لحم", "دجاج", "سمك", "قصاب"]),
            sub("Fruit & Veg", "خضار وفواكه", ["fruit", "vegetables", "veg", "خضار", "فواكه", "خضره"]),
            sub("Water", "مياه", ["water bottles", "water delivery", "mai dubai", "masafi", "al ain water", "nova", "ماي دبي", "مسافي", "مياه العين", "قوارير ماي", "ماء شرب"])
        ], isIncome: false),
        Category(name: "Car & Transport", arabic: "السيارة والمواصلات", icon: "car.fill", color: "blue",
                 aliases: ["Car", "Transport", "Transportation", "Vehicle", "Auto"], subcategories: [
            sub("Fuel", "وقود", ["fuel", "petrol", "gas station", "diesel", "adnoc", "enoc", "eppco", "emarat", "aldrees", "sasco", "naft", "omanoil", "shell", "وقود", "بنزين", "ديزل", "ادنوك", "اينوك", "الدريس", "ساسكو", "محطة"]),
            sub("Parking", "مواقف", ["parking", "mawaqif", "valet", "مواقف", "باركينج", "باركنغ", "فاليه"]),
            sub("Tolls & Salik", "رسوم الطرق", ["salik", "darb", "toll", "سالك", "درب", "بوابة"]),
            sub("Car wash", "غسيل سيارة", ["car wash", "wash", "polish", "غسيل", "تلميع", "مغسلة"]),
            sub("Garage & Service", "صيانة وكراج", ["garage", "service", "oil change", "mechanic", "repair", "battery", "tyres", "tires", "كراج", "قراج", "ورشة", "صيانة", "زيت", "تواير", "كفرات", "بطارية"]),
            sub("Fines", "مخالفات", ["fine", "fines", "traffic fine", "radar", "مخالفة", "مخالفات", "رادار", "ساهر"]),
            sub("Rental", "تأجير", ["rental", "rent a car", "car rent", "hertz", "avis", "ekar", "تأجير", "إيجار سيارة", "ايجار سيارة"]),
            sub("Insurance & Registration", "تأمين وتسجيل", ["car insurance", "registration", "mulkiya", "istimara", "renewal", "تأمين", "تسجيل", "ملكية", "استمارة", "تجديد"]),
            sub("Accident & Repairs", "حادث وإصلاح", ["accident", "body shop", "dent", "حادث", "صدمة", "سمكرة"]),
            sub("Taxi & Rides", "تاكسي", ["taxi", "uber", "careem", "bolt", "yango", "تاكسي", "اوبر", "أوبر", "كريم", "يانغو"]),
            sub("Metro & Bus", "مترو وحافلات", ["metro", "bus", "tram", "nol", "hafilat", "مترو", "باص", "حافلة", "نول", "حافلات"])
        ], isIncome: false),
        Category(name: "Housing", arabic: "السكن", icon: "house.fill", color: "teal",
                 aliases: ["Home", "Rent", "House"], subcategories: [
            sub("Rent", "إيجار", ["rent", "home rent", "ejari", "tawtheeq", "إيجار", "ايجار", "اجار", "ايجار البيت"]),
            sub("Maintenance", "صيانة المنزل", ["plumber", "electrician", "ac service", "ac repair", "handyman", "سباك", "كهربائي", "صيانة مكيف", "تصليح"]),
            sub("Furniture & Home", "أثاث ومنزل", ["furniture", "ikea", "home centre", "home center", "pan emirates", "أثاث", "ايكيا", "هوم سنتر", "مفروشات"]),
            sub("Cleaning & Maid", "تنظيف وعاملة", ["cleaning", "maid", "housekeeping", "justlife", "تنظيف", "خادمة", "شغالة", "عاملة"]),
            sub("Laundry", "مغسلة", ["laundry", "dry clean", "ironing", "مغسلة ملابس", "كوي", "دراي كلين", "لوندري"])
        ], isIncome: false),
        Category(name: "Bills & Utilities", arabic: "الفواتير والخدمات", icon: "lightbulb.fill", color: "yellow",
                 aliases: ["Utilities", "Bills"], subcategories: [
            sub("Electricity & Water", "كهرباء وماء", ["dewa", "sewa", "addc", "aadc", "fewa", "etihad water", "sec", "kahramaa", "mew", "electricity", "water bill", "كهرباء", "فاتورة الماء", "ديوا", "سيوا", "كهرماء"]),
            sub("Mobile", "جوال", ["mobile", "recharge", "du", "etisalat", "e&", "stc", "mobily", "zain", "ooredoo", "batelco", "omantel", "virgin mobile", "جوال", "موبايل", "شحن", "رصيد", "اتصالات", "دو", "زين", "موبايلي"]),
            sub("Internet & TV", "إنترنت وتلفزيون", ["internet", "wifi", "broadband", "tv", "انترنت", "إنترنت", "واي فاي"]),
            sub("Gas & Cooling", "غاز وتبريد", ["gas cylinder", "empower", "district cooling", "chiller", "غاز", "تبريد", "تكييف مركزي"])
        ], isIncome: false),
        Category(name: "Health & Wellness", arabic: "الصحة والعافية", icon: "heart.fill", color: "red",
                 aliases: ["Health", "Medical", "Wellness"], subcategories: [
            sub("Pharmacy & Meds", "صيدلية وأدوية", ["pharmacy", "medicine", "meds", "aster", "boots", "life pharmacy", "nahdi", "al dawaa", "صيدلية", "دواء", "أدوية", "ادوية", "علاج", "النهدي", "الدواء"]),
            sub("Hospital", "مستشفى", ["hospital", "emergency", "er", "مستشفى", "طوارئ"]),
            sub("Clinic & Checkups", "عيادة وفحوصات", ["clinic", "doctor", "checkup", "check up", "consultation", "lab", "blood test", "x ray", "عيادة", "دكتور", "طبيب", "فحص", "تحاليل", "مختبر", "كشفية"]),
            sub("Dental", "أسنان", ["dentist", "dental", "teeth", "braces", "أسنان", "اسنان", "تقويم"]),
            sub("Optical", "بصريات", ["optician", "glasses", "lenses", "eyewear", "نظارات", "عدسات", "نظارة"]),
            sub("Spa & Relaxation", "سبا واسترخاء", ["spa", "massage", "relaxation", "hammam", "sauna", "moroccan bath", "سبا", "مساج", "حمام مغربي", "استرخاء", "ساونا"]),
            sub("Barber & Salon", "حلاق وصالون", ["barber", "haircut", "salon", "nails", "beauty", "حلاق", "حلاقة", "صالون", "مشغل", "أظافر"]),
            sub("Health insurance", "تأمين صحي", ["health insurance", "daman", "bupa", "تأمين صحي", "ضمان"])
        ], isIncome: false),
        Category(name: "Sports & Fitness", arabic: "الرياضة واللياقة", icon: "figure.run", color: "green",
                 aliases: ["Sports", "Fitness", "Gym"], subcategories: [
            sub("Gym", "نادي رياضي", ["gym", "fitness first", "gold's gym", "golds gym", "fitness time", "membership", "جيم", "نادي", "صالة رياضية", "اشتراك نادي"]),
            sub("Fitness classes", "حصص لياقة", ["zumba", "yoga", "pilates", "crossfit", "spinning", "boxing", "kickboxing", "martial arts", "aerobics", "class", "classes", "زومبا", "يوغا", "بيلاتس", "كروس فت", "ملاكمة", "حصة", "كلاس"]),
            sub("Padel & Tennis", "بادل وتنس", ["padel", "paddle", "tennis", "squash", "badminton", "playtomic", "بادل", "تنس", "اسكواش"]),
            sub("Football & Team sports", "كرة قدم", ["football", "soccer", "basketball", "volleyball", "pitch", "كورة", "كرة قدم", "ملعب", "كرة سلة"]),
            sub("Swimming", "سباحة", ["swimming", "pool", "سباحة", "مسبح"]),
            sub("Sports gear", "معدات رياضية", ["decathlon", "sports gear", "sportswear", "nike", "adidas", "ديكاتلون", "ملابس رياضية", "أدوات رياضية"])
        ], isIncome: false),
        Category(name: "Shopping", arabic: "التسوق", icon: "bag.fill", color: "pink",
                 aliases: ["Shopping"], subcategories: [
            sub("Clothes & Shoes", "ملابس وأحذية", ["clothes", "shoes", "zara", "h&m", "shein", "namshi", "max fashion", "centrepoint", "ملابس", "أحذية", "احذية", "جزمة", "نعال", "قميص"]),
            sub("Abaya & Kandura", "عبايات وكنادير", ["abaya", "kandura", "dishdasha", "thobe", "ghutra", "shemagh", "عباية", "عبايات", "كندورة", "كندورة", "دشداشة", "ثوب", "غترة", "شماغ"]),
            sub("Perfume & Oud", "عطور وعود", ["perfume", "oud", "bakhoor", "ajmal", "arabian oud", "rasasi", "عطر", "عطور", "عود", "بخور", "دهن عود", "أجمل", "العربية للعود"]),
            sub("Electronics", "إلكترونيات", ["electronics", "phone", "laptop", "iphone", "apple store", "sharaf dg", "jarir", "extra", "virgin megastore", "إلكترونيات", "الكترونيات", "جوال جديد", "لابتوب", "جرير", "اكسترا", "شرف دي جي"]),
            sub("Online", "تسوق إلكتروني", ["amazon", "noon", "aliexpress", "temu", "trendyol", "online order", "أمازون", "امازون", "نون", "تيمو"]),
            sub("Gold & Jewelry", "ذهب ومجوهرات", ["gold", "jewelry", "jewellery", "malabar", "joyalukkas", "ذهب", "مجوهرات", "خاتم", "سوار"]),
            sub("Gifts", "هدايا", ["gift", "gifts", "present", "flowers", "هدية", "هدايا", "ورد", "زهور"]),
            sub("Installments", "أقساط", ["installment", "tabby", "tamara", "postpay", "cashew", "قسط", "أقساط", "تابي", "تمارا"])
        ], isIncome: false),
        Category(name: "Entertainment", arabic: "الترفيه", icon: "popcorn.fill", color: "purple",
                 aliases: ["Fun", "Leisure"], subcategories: [
            sub("Cinema", "سينما", ["cinema", "movie", "vox", "reel", "novo", "muvi", "سينما", "فلم", "فيلم"]),
            sub("Gaming", "ألعاب", ["game", "gaming", "playstation", "psn", "xbox", "steam", "nintendo", "pubg", "ألعاب", "العاب", "بلايستيشن", "شدات"]),
            sub("Events & Concerts", "فعاليات وحفلات", ["concert", "event", "ticket", "platinumlist", "riyadh season", "حفلة", "فعالية", "تذكرة", "موسم الرياض"]),
            sub("Theme parks", "مدن ملاهي", ["theme park", "ferrari world", "img", "wild wadi", "aquaventure", "ملاهي", "مدينة ألعاب"]),
            sub("Billiards & Bowling", "بلياردو وبولينج", ["billiards", "snooker", "bowling", "بلياردو", "سنوكر", "بولينج"]),
            sub("Hobbies", "هوايات", ["hobby", "camping", "fishing", "desert", "safari", "hookah", "shisha", "هواية", "كشتة", "تخييم", "صيد", "شيشة", "معسل"])
        ], isIncome: false),
        Category(name: "Subscriptions", arabic: "الاشتراكات", icon: "repeat", color: "purple",
                 aliases: ["Subscriptions", "Memberships"], subcategories: [
            sub("Streaming", "بث", ["netflix", "shahid", "osn", "disney", "prime video", "youtube premium", "starzplay", "tod", "نتفلكس", "شاهد"]),
            sub("Music", "موسيقى", ["spotify", "anghami", "apple music", "deezer", "سبوتيفاي", "أنغامي"]),
            sub("Cloud storage", "تخزين سحابي", ["icloud", "google drive", "google one", "dropbox", "آي كلاود"]),
            sub("Software & AI", "برامج وذكاء اصطناعي", ["chatgpt", "chat gpt", "openai", "claude", "adobe", "microsoft", "canva", "notion", "github", "شات جي بي تي"]),
            sub("Memberships", "عضويات", ["careem plus", "noon one", "talabat pro", "amazon prime", "membership fee"])
        ], isIncome: false),
        Category(name: "Travel", arabic: "السفر", icon: "airplane", color: "teal",
                 aliases: ["Travel", "Trips", "Vacation"], subcategories: [
            sub("Flights", "طيران", ["flight", "ticket", "emirates", "flydubai", "etihad", "air arabia", "saudia", "flynas", "qatar airways", "oman air", "gulf air", "kuwait airways", "طيران", "تذكرة طيران", "رحلة", "الخطوط"]),
            sub("Hotels", "فنادق", ["hotel", "booking", "airbnb", "resort", "chalet", "فندق", "شاليه", "منتجع", "حجز"]),
            sub("Umrah & Hajj", "عمرة وحج", ["umrah", "hajj", "عمرة", "حج"]),
            sub("Visa & Travel docs", "تأشيرات سفر", ["travel visa", "schengen", "تأشيرة سفر", "فيزا"])
        ], isIncome: false),
        Category(name: "Education", arabic: "التعليم", icon: "graduationcap.fill", color: "blue",
                 aliases: ["Education", "School"], subcategories: [
            sub("School fees", "رسوم مدرسية", ["school fees", "tuition", "رسوم مدرسة", "رسوم دراسية", "مدرسة"]),
            sub("University", "جامعة", ["university", "college", "جامعة", "كلية"]),
            sub("Courses", "دورات", ["course", "udemy", "coursera", "training", "دورة", "كورس", "تدريب"]),
            sub("Books & Stationery", "كتب وقرطاسية", ["books", "stationery", "kinokuniya", "magrudy", "كتب", "قرطاسية", "مكتبة"])
        ], isIncome: false),
        Category(name: "Family & Kids", arabic: "العائلة والأطفال", icon: "figure.2.and.child.holdinghands", color: "orange",
                 aliases: ["Family", "Kids", "Children"], subcategories: [
            sub("Childcare", "حضانة", ["nursery", "daycare", "babysitter", "nanny", "حضانة", "مربية"]),
            sub("Toys & Kids", "ألعاب أطفال", ["toys", "diapers", "baby", "hamleys", "toys r us", "حفاضات", "بامبرز", "ألعاب أطفال"]),
            sub("Eidiya & Family support", "عيدية ومصروف", ["eidiya", "allowance", "pocket money", "family support", "عيدية", "مصروف", "مساعدة الأهل"])
        ], isIncome: false),
        Category(name: "Charity", arabic: "الصدقات والتبرعات", icon: "hands.and.sparkles.fill", color: "green",
                 aliases: ["Charity", "Donations", "Zakat"], subcategories: [
            sub("Zakat", "زكاة", ["zakat", "زكاة", "زكاه"]),
            sub("Sadaqah & Donations", "صدقة وتبرعات", ["sadaqah", "charity", "donation", "red crescent", "صدقة", "تبرع", "الهلال الأحمر"]),
            sub("Mosque", "مسجد", ["mosque", "masjid", "مسجد"])
        ], isIncome: false),
        Category(name: "Government & Documents", arabic: "الحكومة والمعاملات", icon: "building.columns.fill", color: "gray",
                 aliases: ["Government", "Documents", "Fees"], subcategories: [
            sub("ID & Residency", "هوية وإقامة", ["emirates id", "iqama", "residency", "visa renewal", "civil id", "absher", "icp", "هوية", "إقامة", "اقامة", "أبشر", "بطاقة مدنية"]),
            sub("Licenses & Permits", "رخص وتصاريح", ["license", "licence", "permit", "trade license", "driving license", "رخصة", "تصريح"]),
            sub("Typing & Services", "طباعة ومعاملات", ["typing centre", "typing center", "amer", "tasheel", "attestation", "طباعة", "عامر", "تسهيل", "تصديق"])
        ], isIncome: false),
        Category(name: "Financial", arabic: "المالية", icon: "banknote.fill", color: "gray",
                 aliases: ["Finance", "Banking", "Fees"], subcategories: [
            sub("Bank fees", "رسوم بنكية", ["bank fee", "fee", "charges", "annual fee", "رسوم", "رسوم بنك"]),
            sub("Credit card payment", "سداد بطاقة", ["credit card payment", "card payment", "سداد بطاقة", "تسديد البطاقة"]),
            sub("Loan repayment", "سداد قرض", ["loan", "emi", "قرض", "سداد قرض"]),
            sub("Remittance & Exchange", "حوالات وصرافة", ["remittance", "exchange", "al ansari", "lulu exchange", "western union", "حوالة", "صرافة", "الأنصاري"]),
            sub("Investments & Savings", "استثمار وادخار", ["investment", "stocks", "sarwa", "savings", "استثمار", "أسهم", "ادخار"])
        ], isIncome: false),
        Category(name: "Pets", arabic: "الحيوانات الأليفة", icon: "pawprint.fill", color: "orange",
                 aliases: ["Pets"], subcategories: [
            sub("Pet food", "طعام حيوانات", ["pet food", "cat food", "dog food", "أكل قطط", "أكل كلاب"]),
            sub("Vet", "بيطري", ["vet", "veterinary", "بيطري", "طبيب بيطري"]),
            sub("Grooming", "عناية", ["pet grooming", "grooming", "تجميل حيوانات"])
        ], isIncome: false),
        Category(name: "Salary", arabic: "الراتب", icon: "banknote.fill", color: "green",
                 aliases: ["Salary", "Income"], subcategories: [
            sub("Salary", "راتب", ["salary", "payroll", "راتب", "معاش"]),
            sub("Bonus", "مكافأة", ["bonus", "incentive", "مكافأة", "حوافز"]),
            sub("Allowances", "بدلات", ["housing allowance", "allowance", "بدل", "بدلات"])
        ], isIncome: true),
        Category(name: "Other Income", arabic: "دخل آخر", icon: "arrow.down.circle.fill", color: "green",
                 aliases: ["Other Income", "Income"], subcategories: [
            sub("Freelance & Business", "عمل حر", ["freelance", "client", "business income", "عمل حر", "مشروع"]),
            sub("Refunds", "مسترجعات", ["refund", "cashback", "reimbursement", "استرجاع", "استرداد", "كاش باك"]),
            sub("Profits & Dividends", "أرباح", ["profit", "dividend", "returns", "أرباح", "ارباح"]),
            sub("Rental income", "دخل إيجار", ["rental income", "tenant", "دخل إيجار"]),
            sub("Gifts received", "هدايا مستلمة", ["gift received", "eidiya received", "عيدية مستلمة"])
        ], isIncome: true)
    ]

    /// The category list a brand-new user starts with (plus system ones the app relies on).
    public static var defaultNames: [String] { all.map(\.name) + ["Transfers", "Other"] }

    /// Money moved between the user's own wallets, or a balance correction: changes balances, never spending or income.
    /// Imported ledgers (Expend) can file a transfer as a subcategory "Transfer" under another category, so both are checked.
    public static func isTransferOrAdjustment(category: String, subcategory: String?) -> Bool {
        category == "Transfers" || category == "Adjustment"
            || subcategory.map { ["transfer", "transfers"].contains(CategoryMatcher.normalize($0)) } == true
    }

    public static func category(named name: String) -> Category? {
        let key = CategoryMatcher.normalize(name)
        return all.first { CategoryMatcher.normalize($0.name) == key || $0.aliases.map(CategoryMatcher.normalize).contains(key) }
    }

    public static func arabicName(for name: String) -> String? {
        if let category = all.first(where: { $0.name == name }) { return category.arabic }
        for category in all { if let sub = category.subcategories.first(where: { $0.name == name }) { return sub.arabic } }
        // The user's own names for a category ("Food", "Car" from an Expend import) read as that category in Arabic.
        return category(named: name)?.arabic
    }
}
