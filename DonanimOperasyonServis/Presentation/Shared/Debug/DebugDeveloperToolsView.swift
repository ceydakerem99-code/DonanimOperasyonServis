#if DEBUG
import SwiftUI

/// DEBUG-only developer tools: demo seed/clear, mock GPS, network sim, sync report.
struct DebugDeveloperToolsView: View {

    let currentUser: User?
    var showsDemoDataLoad = true
    var onOpenCustomerSatisfactionSurvey: ((CustomerSatisfactionID) -> Void)? = nil
    @Environment(\.diContainer) private var container
    @State private var locationSource = DebugLocationSettings.source
    @State private var statusMessage: String?
    @State private var lastSeedSucceeded = true
    @State private var isBusy = false
    @State private var demoSurveyId = ""
    /// UI mirror only — authoritative state lives in `DebuggableNetworkReachability`.
    @State private var isOfflineSimulated = false

    init(
        currentUser: User? = nil,
        showsDemoDataLoad: Bool = true,
        onOpenCustomerSatisfactionSurvey: ((CustomerSatisfactionID) -> Void)? = nil
    ) {
        self.currentUser = currentUser
        self.showsDemoDataLoad = showsDemoDataLoad
        self.onOpenCustomerSatisfactionSurvey = onOpenCustomerSatisfactionSurvey
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                Text("DEBUG ortamı — demo veriler ve test araçları.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
                    .padding(.bottom, AppSpacing.xs)

                section("Demo Veriler") {
                    VStack(alignment: .leading, spacing: AppSpacing.s) {
                        if showsDemoDataLoad {
                            PrimaryButton(title: "Demo Verileri Yükle", isLoading: isBusy, isEnabled: !isBusy) {
                                Task {
                                    isBusy = true
                                    let outcome = await DemoDataSeeder.loadDemoData(container: container)
                                    lastSeedSucceeded = outcome.isSuccess
                                    statusMessage = outcome.message
                                    isBusy = false
                                }
                            }
                        }


                        Button("Demo Verilerini Temizle") {
                            Task {
                                isBusy = true
                                lastSeedSucceeded = true
                                statusMessage = await DemoDataSeeder.clearDemoData(container: container)
                                isBusy = false
                            }
                        }
                        .disabled(isBusy)
                        .foregroundStyle(AppColor.danger)
                    }
                }

                section("İş Emri Şablonları") {
                    VStack(alignment: .leading, spacing: AppSpacing.s) {
                        Button("Varsayılan Şablonları Yeniden Oluştur") {
                            guard let currentUser else {
                                statusMessage = "Aktif kullanıcı bulunamadı."
                                lastSeedSucceeded = false
                                return
                            }

                            OperatorWorkOrderTemplateService.resetDefaultsSeed(
                                for: currentUser.id
                            )

                            statusMessage = "Şablon seed sıfırlandı. İş emri şablonlarını tekrar açın."
                            lastSeedSucceeded = true
                        }
                        .disabled(isBusy || currentUser == nil)

                        Text("Varsayılan iş emri şablonlarını yeniden oluşturmak için seed kaydını sıfırlar.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }

                section("Konum Kaynağı") {
                    VStack(alignment: .leading, spacing: AppSpacing.s) {
                        Picker("Konum Kaynağı", selection: $locationSource) {
                            ForEach(DebugLocationSettings.Source.allCases) { source in
                                Text(source.displayName).tag(source)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: locationSource) { _, newValue in
                            DebugLocationSettings.source = newValue
                            statusMessage = "Konum kaynağı: \(newValue.displayName). İş emri detayını yeniden açın."
                            lastSeedSucceeded = true
                        }
                        Text("Simülatörde varsayılan: Test Konumu (Yola Çık için GPS izni gerekmez). Gerçek GPS seçerseniz Simulator → Features → Location ile konum verin; iş emri detayını yeniden açın.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }

                section("Ağ Simülasyonu") {
                    VStack(alignment: .leading, spacing: AppSpacing.s) {
                        Toggle("Offline Modu (İnternetsiz Test)", isOn: $isOfflineSimulated)
                            .onChange(of: isOfflineSimulated) { _, offline in
                                Task {
                                    await applyOfflineSimulation(offline)
                                }
                            }
                        Text("Gerçek ağ monitörünü simüle offline yapar. Sync beklemeye geçer; kapatınca gerçek bağlantı durumuna döner.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }

                section("Realtime Gateway (Shadow)") {
                    let realtime = container.realtimeCoordinator
                    VStack(alignment: .leading, spacing: AppSpacing.s) {
                        Text("\(realtime.connectionState.debugSymbol) \(realtime.connectionState.debugLabel)")
                            .font(AppFont.body)
                        if let failure = realtime.lastFailureMessage {
                            Text(failure)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.danger)
                        }
                        Text("ACK: \(realtime.telemetry.receivedAckCount) · Event: \(realtime.telemetry.receivedEventCount) · Unknown: \(realtime.telemetry.unknownMessageCount)")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                        if let role = realtime.telemetry.lastHelloRole {
                            Text("Rol: \(role)")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                        }
                        if let ack = realtime.telemetry.lastAckStatus {
                            Text("Son ACK: \(ack)")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.secondaryText)
                        }
                        if let smoke = realtime.telemetry.lastSmokeReport {
                            Text(smoke.summary)
                                .font(AppFont.caption)
                                .foregroundStyle(smoke.succeeded ? AppColor.success : AppColor.danger)
                        }
                        HStack(spacing: AppSpacing.m) {
                            Button(realtime.telemetry.lastHelloRole == UserRole.technician.rawValue
                                ? "Smoke Sequence (WO probe + duplicate)"
                                : "Smoke Sequence (customer + WO + duplicate)") {
                                Task { await realtime.runShadowSmokeSequence() }
                            }
                            .disabled(realtime.connectionState != .connected)
                        }
                        Button("Tek Shadow Probe (rol uyumlu)") {
                            Task { await realtime.sendShadowProbe() }
                        }
                        .disabled(realtime.connectionState != .connected)
                        Text("Gerçek gateway smoke: Firebase Auth ID token + in-memory ACK. SwiftData/Firebase/SyncQueue mutate edilmez.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)
                    }
                }

                section("Müşteri Memnuniyeti (Demo / Simülasyon)") {
                    VStack(alignment: .leading, spacing: AppSpacing.s) {
                        NavigationLink {
                            CustomerSatisfactionSMSSimulationView(
                                onOpenSurvey: onOpenCustomerSatisfactionSurvey
                            )
                        } label: {
                            Text("SMS Simülasyonu ve E2E Akış")
                        }

                        Text("Tamamlanan iş emri seç → otomatik SMS önizlemesi → Değerlendirmeye Git → formu doldur.")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.secondaryText)

                        Divider()

                        TextField("Satisfaction ID (manuel)", text: $demoSurveyId)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if let onOpenCustomerSatisfactionSurvey {
                            Button("Değerlendirme Formunu Aç (Manuel ID)") {
                                let trimmed = demoSurveyId.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty else { return }
                                onOpenCustomerSatisfactionSurvey(CustomerSatisfactionID(trimmed))
                            }
                            .disabled(demoSurveyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        } else {
                            NavigationLink {
                                CustomerSatisfactionFormView(
                                    satisfactionId: CustomerSatisfactionID(
                                        demoSurveyId.trimmingCharacters(in: .whitespacesAndNewlines)
                                    )
                                )
                            } label: {
                                Text("Değerlendirme Formunu Aç (Manuel ID)")
                            }
                            .disabled(demoSurveyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                if let statusMessage {
                    Text(statusMessage)
                        .font(AppFont.caption)
                        .foregroundStyle(lastSeedSucceeded ? AppColor.brandPrimary : AppColor.danger)
                        .padding(.top, AppSpacing.xs)
                }
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.vertical, AppSpacing.m)
        }
        .navigationTitle("Geliştirici / Test")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            locationSource = DebugLocationSettings.source
            syncOfflineSimulationFromReachability()
        }
    }

    private func syncOfflineSimulationFromReachability() {
        Task {
            guard let debugReachability =
                container.networkReachability as? DebugNetworkReachabilityControlling else {
                return
            }
            isOfflineSimulated = await debugReachability.isSimulationOffline
        }
    }

    private func applyOfflineSimulation(_ offline: Bool) async {
        guard let debugReachability =
            container.networkReachability as? DebugNetworkReachabilityControlling else {
            statusMessage = "Ağ simülasyonu yalnızca DEBUG live oturumunda kullanılabilir."
            isOfflineSimulated = false
            return
        }

        await debugReachability.setSimulatedOffline(offline)
        if offline {
            statusMessage = "Offline mod aktif — sync duracak."
            lastSeedSucceeded = true
            return
        }

        let reachable = await container.networkReachability.isReachable
        AppLogger.sync.info(
            "SYNC AUTO-DRAIN START source=debugToggleOff isReachable=\(reachable, privacy: .public)"
        )
        await container.syncCoordinator.handleNetworkBecameReachable()
        statusMessage = reachable
            ? "Online mod aktif — otomatik sync tetiklendi."
            : "Simülasyon kapalı ancak gerçek ağ hâlâ çevrimdışı görünüyor."
        lastSeedSucceeded = reachable
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text(title)
                .font(AppFont.subtitle)
                .foregroundStyle(AppColor.primaryText)
            content()
        }
        .padding(AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).strokeBorder(AppColor.divider))
    }
}
#endif
