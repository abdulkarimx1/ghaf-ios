import SwiftUI
import SwiftData

/// Category + subcategory menu with "New category…", shared by the transaction editor and Ghaf AI.
struct GhafCategoryPicker: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [GhafSettings]
    @Binding var category: String
    @Binding var subcategory: String?
    let languageCode: String
    var tint: Color = .accentColor

    @State private var creating = false
    @State private var newName = ""
    @State private var newSub = ""

    private var ar: Bool { languageCode == "ar" }
    private var settings: GhafSettings? { settingsList.first }

    var body: some View {
        Menu {
            ForEach(settings?.categories ?? GhafDefaults.defaultCategories, id: \.self) { name in
                let subs = settings?.subcategories(of: name) ?? []
                if subs.isEmpty {
                    Button(label(name)) { select(name, nil) }
                } else {
                    Menu(label(name)) {
                        Button(ar ? "عام" : "General") { select(name, nil) }
                        ForEach(subs, id: \.self) { sub in Button(sub) { select(name, sub) } }
                    }
                }
            }
            Divider()
            Button {
                newName = ""
                newSub = ""
                creating = true
            } label: {
                Label(ar ? "فئة جديدة…" : "New category…", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 4) {
                Text(subcategory.map { "\(label(category)) · \($0)" } ?? label(category))
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(tint)
        }
        .alert(ar ? "فئة جديدة" : "New category", isPresented: $creating) {
            TextField(ar ? "اسم الفئة" : "Category name", text: $newName)
            TextField(ar ? "فئة فرعية (اختياري)" : "Subcategory (optional)", text: $newSub)
            Button(ar ? "إلغاء" : "Cancel", role: .cancel) {}
            Button(ar ? "حفظ" : "Save") { create() }
        } message: {
            Text(ar ? "تُضاف إلى فئاتك ويتذكرها غاف." : "It's added to your categories and Ghaf will remember it.")
        }
    }

    private func label(_ name: String) -> String { GhafLocalization.category(name, languageCode: languageCode) }

    private func select(_ name: String, _ sub: String?) {
        category = name
        subcategory = sub
    }

    private func create() {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty, let settings else { return }
        let saved = settings.addCategory(newName, subcategory: newSub)
        try? context.save()
        select(saved.category, saved.subcategory)
    }
}
