import SwiftUI

struct OperatorCustomerEditView: View {
    @Bindable var viewModel: OperatorCustomerEditViewModel
    var onSaved: () -> Void
    var onCancel: () -> Void

    var body: some View {
        Group {
            AsyncLoadContainerView(
                isLoading: viewModel.isLoading,
                showsLoadingIndicator: viewModel.isLoading,
                hasCachedContent: !viewModel.name.isEmpty,
                errorMessage: viewModel.loadError,
                isEmpty: false,
                loadingMessage: "Bilgiler yükleniyor...",
                errorTitle: "Yüklenemedi",
                onRetry: { Task { await viewModel.load() } }
            ) {
                editForm
            }
        }
        .navigationTitle("Müşteri Düzenle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("İptal", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Kaydet") {
                    Task { await viewModel.save() }
                }
                .disabled(viewModel.isSaving)
            }
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.didSave) { _, saved in
            if saved { onSaved() }
        }
    }

    private var editForm: some View {
        Form {
            Section("Müşteri Bilgileri") {
                TextField("Firma / Ad Soyad", text: $viewModel.name)
                TextField("Yetkili Kişi", text: $viewModel.contactPersonName)
                TextField("Telefon", text: $viewModel.phone)
                    .keyboardType(.phonePad)
                TextField("E-posta", text: $viewModel.email)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                TextField("Adres", text: $viewModel.address, axis: .vertical)
                    .lineLimit(2...4)
                TextField("Şehir", text: $viewModel.city)
                TextField("Not", text: $viewModel.notes, axis: .vertical)
                    .lineLimit(2...4)
            }

            if let message = viewModel.saveError {
                Section {
                    Text(message)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.danger)
                }
            }
        }
    }
}
