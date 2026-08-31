import SwiftUI

/// Admin panel for managing pause reasons (built-in + custom).
struct AdminPauseReasonsView: View {
    @State private var customItems: [CustomConfigItem] = CustomConfigStore.loadPauseReasons()
    @State private var showAddSheet = false
    @State private var editingItem: CustomConfigItem?
    @State private var newName = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: AppSpacing.m) {
                Text("Yerleşik bekleme nedenleri sabittir ve silinemez. Özel bekleme nedenleri ekleyebilir, düzenleyebilir veya kaldırabilirsiniz.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)

                ForEach(PauseReason.allCases, id: \.self) { reason in
                    configRow(
                        name: reason.displayName,
                        subtitle: reason.rawValue,
                        icon: "pause.circle",
                        isBuiltIn: true
                    )
                }

                ForEach(customItems) { item in
                    configRow(
                        name: item.name,
                        subtitle: "Özel",
                        icon: "pause.circle",
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
                                CustomConfigStore.savePauseReasons(customItems)
                            }
                        } label: {
                            Label("Sil", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            withAnimation {
                                customItems.removeAll { $0.id == item.id }
                                CustomConfigStore.savePauseReasons(customItems)
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
        .navigationTitle("Bekleme Nedenleri")
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
        .alert("Yeni Bekleme Nedeni", isPresented: $showAddSheet) {
            TextField("Bekleme nedeni", text: $newName)
            Button("Ekle") {
                let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let item = CustomConfigItem(name: trimmed)
                customItems.append(item)
                CustomConfigStore.savePauseReasons(customItems)
            }
            Button("İptal", role: .cancel) {}
        }
        .alert("Bekleme Nedenini Düzenle", isPresented: Binding(
            get: { editingItem != nil },
            set: { if !$0 { editingItem = nil } }
        )) {
            TextField("Bekleme nedeni", text: $newName)
            Button("Kaydet") {
                guard let item = editingItem else { return }
                let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if let idx = customItems.firstIndex(where: { $0.id == item.id }) {
                    customItems[idx].name = trimmed
                    CustomConfigStore.savePauseReasons(customItems)
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
#Preview("Pause Reasons") {
    NavigationStack {
        AdminPauseReasonsView()
    }
}
#endif
