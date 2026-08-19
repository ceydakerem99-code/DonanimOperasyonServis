import SwiftUI

struct CreateCustomerFormView: View {
    @Bindable var viewModel: NewWorkOrderWizardViewModel
    var onCancel: () -> Void

    var body: some View {
        Form {
            Section("Müşteri Bilgileri") {
                TextField("Firma / Ad Soyad", text: $viewModel.newCustomerName)
                TextField("Yetkili Kişi", text: $viewModel.newCustomerContact)
                TextField("Telefon", text: $viewModel.newCustomerPhone)
                    .keyboardType(.phonePad)
                TextField("E-posta", text: $viewModel.newCustomerEmail)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                TextField("Adres", text: $viewModel.newCustomerAddress, axis: .vertical)
                    .lineLimit(2...4)
                TextField("Şehir", text: $viewModel.newCustomerCity)
                TextField("Not", text: $viewModel.newCustomerNotes, axis: .vertical)
                    .lineLimit(2...4)
            }

            if let message = viewModel.newCustomerError {
                Section {
                    Text(message)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.danger)
                }
            }
        }
        .navigationTitle("Yeni Müşteri")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("İptal", action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Kaydet") {
                    Task { await viewModel.createCustomer() }
                }
                .disabled(viewModel.isCreatingCustomer)
            }
        }
    }
}
