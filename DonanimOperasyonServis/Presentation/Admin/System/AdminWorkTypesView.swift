import SwiftUI

/// Admin panel for managing work types (built-in + custom).
struct AdminWorkTypesView: View {
    @State private var customItems: [CustomConfigItem] = CustomConfigStore.loadWorkTypes()
    @State private var showAddSheet = false
    @State private var editingItem: CustomConfigItem?
    @State private var newName = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.m) {
                Text("Yerleşik iş türleri sabittir ve silinemez. Özel iş türleri ekleyebilir, düzenleyebilir veya kaldırabilirsiniz.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)

                ForEach(WorkType.allCases, id: \.self) { type in
                    configRow(
                        name: type.displayName,
                        subtitle: type.rawValue,
                        icon: "wrench.and.screwdriver",
                        isBuiltIn: true
                    )
                }

                ForEach(customItems) { item in
                    configRow(
                        name: item.name,
                        subtitle: "Özel",
                        icon: "wrench.and.screwdriver",
                        isBuiltIn: false
                    )
                    .contextMenu {
                        Button {
                            editingItem = item
                            newName = item.name
                        } label: {
                            Label("Düzenle", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            withAnimation {
                                customItems.removeAll { $0.id == item.id }
                                CustomConfigStore.saveWorkTypes(customItems)
                            }
                        } label: {
                            Label("Sil", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            withAnimation {
                                customItems.removeAll { $0.id == item.id }
                                CustomConfigStore.saveWorkTypes(customItems)
                            }
                        } label: {
                            Label("Sil", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .navigationTitle("İş Türleri Yönetimi")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newName = ""
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("Yeni İş Türü", isPresented: $showAddSheet) {
            TextField("İş türü adı", text: $newName)
            Button("Ekle") {
                let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let item = CustomConfigItem(name: trimmed)
                customItems.append(item)
                CustomConfigStore.saveWorkTypes(customItems)
            }
            Button("İptal", role: .cancel) {}
        }
        .alert("İş Türünü Düzenle", isPresented: Binding(
            get: { editingItem != nil },
            set: { if !$0 { editingItem = nil } }
        )) {
            TextField("İş türü adı", text: $newName)
            Button("Kaydet") {
                guard let item = editingItem else { return }
                let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if let idx = customItems.firstIndex(where: { $0.id == item.id }) {
                    customItems[idx].name = trimmed
                    CustomConfigStore.saveWorkTypes(customItems)
                }
                editingItem = nil
            }
            Button("İptal", role: .cancel) { editingItem = nil }
        }
    }

    private func configRow(name: String, subtitle: String, icon: String, isBuiltIn: Bool) -> some View {
        HStack(spacing: AppSpacing.m) {
            Image(systemName: icon)
                .foregroundStyle(AppColor.brandPrimary)
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(name).font(AppFont.subtitle)
                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }
            Spacer()
            Text(isBuiltIn ? "Sabit" : "Özel")
                .font(AppFont.label)
                .foregroundStyle(isBuiltIn ? AppColor.secondaryText : AppColor.brandPrimary)
        }
        .padding(AppSpacing.m)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).strokeBorder(AppColor.divider))
    }
}

#if DEBUG
#Preview("Work Types") {
    NavigationStack {
        AdminWorkTypesView()
    }
}
#endif
