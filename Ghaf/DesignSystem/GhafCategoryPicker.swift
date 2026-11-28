import SwiftUI
import SwiftData

/// Most-used category pills with a searchable-by-group sheet for the rest.
struct GhafCategoryPicker: View {
    @Environment(\.modelContext) private var context
    @Environment(\.colorScheme) private var colorScheme
    @Query private var settingsList: [GhafSettings]
    @Query private var transactions: [GhafTransaction]
    @Binding var category: String
    @Binding var subcategory: String?
    let languageCode: String
    var tint: Color = .accentColor
    var onManualSelection: (() -> Void)? = nil

    @State private var showingMore = false
    @State private var expandedCategory: String?
    @State private var creating = false
    @State private var newName = ""
    @State private var newSub = ""

    private var ar: Bool { languageCode.lowercased().hasPrefix("ar") }
    private var settings: GhafSettings? { settingsList.first }
    private var theme: GhafTheme {
        GhafTheme.resolve(name: settings?.themeName ?? "Graphite", appearanceMode: settings?.appearanceMode ?? "System", systemIsDark: colorScheme == .dark)
    }
    private var categories: [String] { settings?.categories ?? GhafDefaults.defaultCategories }
    private var popularCategories: [String] {
        let counts = Dictionary(grouping: transactions, by: \.category).mapValues(\.count)
        return categories.enumerated().sorted {
            let left = counts[$0.element, default: 0], right = counts[$1.element, default: 0]
            return left == right ? $0.offset < $1.offset : left > right
        }.prefix(6).map(\.element)
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(popularCategories, id: \.self) { name in
                    pill(label(name), color: GhafCategoryIcon.chartColor(name, dark: theme.isDark), selected: category == name && subcategory == nil) {
                        select(name, nil)
                    }
                }
                pill(ar ? "المزيد" : "More", color: tint, selected: false) {
                    expandedCategory = categories.first(where: { $0 == category }) ?? categories.first
                    showingMore = true
                }
            }
            .padding(.vertical, 2)
        }
        .sheet(isPresented: $showingMore) {
            categorySheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .ghafDirection(languageCode)
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

    private var categorySheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], spacing: 8) {
                        ForEach(categories, id: \.self) { name in
                            pill(label(name), color: GhafCategoryIcon.chartColor(name, dark: theme.isDark), selected: expandedCategory == name) {
                                let subs = settings?.subcategories(of: name) ?? []
                                if subs.isEmpty { select(name, nil); showingMore = false }
                                else { expandedCategory = expandedCategory == name ? nil : name }
                            }
                        }
                    }
                    if let name = expandedCategory {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(label(name)).font(GhafTypography.body(14, languageCode: languageCode, weight: .semibold)).foregroundStyle(theme.secondaryText)
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], spacing: 8) {
                                pill(ar ? "عام" : "General", color: GhafCategoryIcon.chartColor(name, dark: theme.isDark), selected: category == name && subcategory == nil) {
                                    select(name, nil); showingMore = false
                                }
                                ForEach(settings?.subcategories(of: name) ?? [], id: \.self) { sub in
                                    pill(label(sub), color: GhafCategoryIcon.chartColor(name, dark: theme.isDark), selected: category == name && subcategory == sub) {
                                        select(name, sub); showingMore = false
                                    }
                                }
                            }
                        }
                    }
                    Button {
                        newName = ""; newSub = ""; creating = true
                    } label: {
                        Label(ar ? "فئة جديدة…" : "New category…", systemImage: "plus")
                            .font(GhafTypography.body(15, languageCode: languageCode, weight: .semibold))
                            .foregroundStyle(tint).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
            .background(theme.background)
            .navigationTitle(ar ? "الفئات" : "Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(ar ? "تم" : "Done") { showingMore = false }.foregroundStyle(tint)
                }
            }
        }
    }

    private func pill(_ title: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(title).font(GhafTypography.body(14, languageCode: languageCode, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(selected ? theme.accentContrast : theme.primaryText)
            .padding(.horizontal, 14).frame(height: 40)
            .background(selected ? theme.accent : theme.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.outline.opacity(selected ? 0 : 0.55), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func label(_ name: String) -> String { GhafLocalization.category(name, languageCode: languageCode) }

    private func select(_ name: String, _ sub: String?) {
        category = name
        subcategory = sub
        onManualSelection?()
    }

    private func create() {
        guard !newName.trimmingCharacters(in: .whitespaces).isEmpty, let settings else { return }
        let saved = settings.addCategory(newName, subcategory: newSub)
        try? context.save()
        select(saved.category, saved.subcategory)
        showingMore = false
    }
}
