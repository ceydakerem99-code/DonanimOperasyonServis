#if DEBUG
import SwiftUI

/// Catalog screen that exercises every Design System component with
/// sample data. Intentionally excluded from Release builds and never
/// wired into the app's real navigation. Reach it via Xcode Previews
/// or (later) a DEBUG-only shortcut inside developer tooling.
struct DesignSystemPreviewScreen: View {
    @State private var operatorTab: String = "dashboard"
    @State private var technicianTab: String = "home"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xxl) {
                    typographySection
                    paletteSection
                    buttonsSection
                    chipsSection
                    infoRowSection
                    sectionHeaderSection
                    stepIndicatorSection
                    workOrderCardSection
                    timelineSection
                    photosSection
                    signatureSection
                    stateSection
                    conflictSection
                    tabBarSection
                }
                .padding(AppSpacing.l)
            }
            .background(AppColor.neutralBackground)
            .navigationTitle("Design System")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Sections

    private var typographySection: some View {
        section(title: "Typography") {
            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Text("Display Title").font(AppFont.displayTitle).foregroundStyle(AppColor.primaryText)
                Text("Title").font(AppFont.title).foregroundStyle(AppColor.primaryText)
                Text("Subtitle").font(AppFont.subtitle).foregroundStyle(AppColor.primaryText)
                Text("Body — Kurulum, bakım, arıza ve teslim akışları.").font(AppFont.body).foregroundStyle(AppColor.primaryText)
                Text("Caption — İş emri #WO-1024").font(AppFont.caption).foregroundStyle(AppColor.secondaryText)
                Text("Label — Etiket").font(AppFont.label).foregroundStyle(AppColor.secondaryText)
                Text("11:20 - 12:10").font(AppFont.monoDigits).foregroundStyle(AppColor.primaryText)
            }
        }
    }

    private var paletteSection: some View {
        section(title: "Renkler") {
            let brandSwatches: [(String, Color)] = [
                ("brandPrimary", AppColor.brandPrimary),
                ("brandSurface", AppColor.brandSurface),
                ("neutralBackground", AppColor.neutralBackground),
                ("elevatedSurface", AppColor.elevatedSurface),
                ("onPrimary", AppColor.onPrimary),
                ("primaryText", AppColor.primaryText),
                ("secondaryText", AppColor.secondaryText),
                ("divider", AppColor.divider)
            ]
            let semanticSwatches: [(String, Color)] = [
                ("success", AppColor.success),
                ("warning", AppColor.warning),
                ("danger", AppColor.danger),
                ("info", AppColor.info)
            ]
            return VStack(alignment: .leading, spacing: AppSpacing.m) {
                swatchGrid(title: "Marka & Nötr", swatches: brandSwatches)
                swatchGrid(title: "Semantik", swatches: semanticSwatches)
            }
        }
    }

    private var buttonsSection: some View {
        section(title: "Butonlar") {
            VStack(spacing: AppSpacing.m) {
                PrimaryButton(title: "İşi Tamamla", systemImage: "checkmark.seal.fill") {}
                PrimaryButton(title: "Kaydediliyor", isLoading: true) {}
                PrimaryButton(title: "Devre Dışı", isEnabled: false) {}
                SecondaryButton(title: "Geri", systemImage: "chevron.left") {}
                DestructiveButton(title: "Reddet", systemImage: "xmark.circle") {}
            }
        }
    }

    private var chipsSection: some View {
        section(title: "Durum & Öncelik") {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                wrappedChips {
                    ForEach(AppStatus.allCases, id: \.self) { StatusChip(status: $0) }
                }
                wrappedChips {
                    ForEach(AppPriority.allCases, id: \.self) { PriorityBadge(priority: $0) }
                }
            }
        }
    }

    private var infoRowSection: some View {
        section(title: "InfoRow") {
            VStack(spacing: 0) {
                InfoRow(title: "Müşteri", value: "ABC Market", systemImage: "building.2")
                InfoRow(title: "Yetkili", value: "Mehmet Kaya", systemImage: "person")
                InfoRow(title: "Telefon", value: "0505 123 45 67", systemImage: "phone")
                InfoRow(title: "Cihaz", value: "POS Ingenico DX8000", systemImage: "creditcard")
                InfoRow(title: "Öncelik", value: "Acil",
                        systemImage: "exclamationmark.triangle.fill",
                        valueColor: AppColor.danger)
            }
            .padding(AppSpacing.m)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(AppColor.elevatedSurface)
            )
        }
    }

    private var sectionHeaderSection: some View {
        section(title: "SectionHeader") {
            VStack(spacing: AppSpacing.m) {
                SectionHeader(title: "Bugünkü İşler",
                              subtitle: "18 Ağustos 2026, Pazartesi")
                SectionHeader(title: "Acil İşler") {
                    Text("Tümü")
                        .font(AppFont.label)
                        .foregroundStyle(AppColor.brandPrimary)
                }
            }
        }
    }

    private var stepIndicatorSection: some View {
        section(title: "Wizard Adımları") {
            let titles = ["İş Türü", "Müşteri", "Cihaz", "Öncelik", "Teknisyen", "Özet"]
            return VStack(spacing: AppSpacing.xl) {
                StepIndicator(currentStep: 1, totalSteps: 6, titles: titles)
                StepIndicator(currentStep: 3, totalSteps: 6, titles: titles)
                StepIndicator(currentStep: 6, totalSteps: 6, titles: titles)
            }
        }
    }

    private var workOrderCardSection: some View {
        section(title: "İş Emri Kartları") {
            VStack(spacing: AppSpacing.m) {
                WorkOrderCard(
                    data: WorkOrderCardData(
                        id: "1",
                        workOrderNumber: "WO-1024",
                        customerName: "ABC Market - POS Arızası",
                        workTypeLabel: "Arıza",
                        deviceLabel: "POS",
                        status: .assigned,
                        priority: .urgent,
                        plannedDateLabel: "18.08.2026",
                        plannedTimeLabel: "10:30",
                        technicianName: "Ahmet Yılmaz"
                    ),
                    onTap: {}
                )
                WorkOrderCard(
                    data: WorkOrderCardData(
                        id: "2",
                        workOrderNumber: "WO-1025",
                        customerName: "XYZ Mağaza - Yazıcı Kurulumu",
                        workTypeLabel: "Kurulum",
                        deviceLabel: "Yazıcı",
                        status: .inProgress,
                        priority: .high,
                        plannedDateLabel: "18.08.2026",
                        plannedTimeLabel: "13:00-14:30",
                        technicianName: "Mehmet Kaya"
                    ),
                    onTap: {}
                )
                WorkOrderCard(
                    data: WorkOrderCardData(
                        id: "3",
                        workOrderNumber: "WO-1017",
                        customerName: "LMN Cafe - POS Bakım",
                        workTypeLabel: "Bakım",
                        deviceLabel: nil,
                        status: .completed,
                        priority: .normal,
                        plannedDateLabel: "17.08.2026",
                        plannedTimeLabel: nil,
                        technicianName: "Ali Demir"
                    )
                )
            }
        }
    }

    private var timelineSection: some View {
        section(title: "Timeline") {
            VStack(alignment: .leading, spacing: 0) {
                TimelineItem(
                    time: "10:42",
                    title: "İş kabul edildi.",
                    author: "Ahmet Yılmaz",
                    accentColor: AppStatus.accepted.accentColor,
                    systemImage: AppStatus.accepted.symbolName
                )
                TimelineItem(
                    time: "10:47",
                    title: "Yola çıkıldı.",
                    subtitle: "41.5440, 34.5615",
                    author: "Ahmet Yılmaz",
                    accentColor: AppStatus.enRoute.accentColor,
                    systemImage: AppStatus.enRoute.symbolName
                )
                TimelineItem(
                    time: "11:20",
                    title: "Müşteriye varıldı.",
                    subtitle: "41.5340, 34.5810",
                    author: "Ahmet Yılmaz",
                    accentColor: AppStatus.arrived.accentColor,
                    systemImage: AppStatus.arrived.symbolName
                )
                TimelineItem(
                    time: "11:22",
                    title: "İşleme başlandı.",
                    author: "Ahmet Yılmaz",
                    accentColor: AppStatus.inProgress.accentColor,
                    systemImage: AppStatus.inProgress.symbolName
                )
                TimelineItem(
                    time: "12:05",
                    title: "Adaptör değiştirildi, servis tamamlandı.",
                    author: "Ahmet Yılmaz",
                    accentColor: AppStatus.completed.accentColor,
                    systemImage: AppStatus.completed.symbolName,
                    showsConnector: false
                )
            }
            .padding(AppSpacing.m)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                    .fill(AppColor.elevatedSurface)
            )
        }
    }

    private var photosSection: some View {
        section(title: "Fotoğraflar") {
            let columns = [
                GridItem(.flexible(), spacing: AppSpacing.s),
                GridItem(.flexible(), spacing: AppSpacing.s),
                GridItem(.flexible(), spacing: AppSpacing.s)
            ]
            return LazyVGrid(columns: columns, spacing: AppSpacing.s) {
                PhotoGridCell(image: nil, categoryLabel: "Öncesi")
                PhotoGridCell(image: nil, categoryLabel: "Sonrası", isUploading: true)
                PhotoGridCell(image: nil, categoryLabel: "Kanıt")
                PhotoGridCell(image: nil, categoryLabel: "Seri No")
                PhotoGridCell(image: nil)
            }
        }
    }

    private var signatureSection: some View {
        section(title: "İmza") {
            VStack(spacing: AppSpacing.xl) {
                SignatureCanvas(title: "Teknisyen İmzası", subtitle: "Ahmet Yılmaz")
                SignatureCanvas(title: "Müşteri İmzası", subtitle: "Mehmet Kaya (ABC Market)")
            }
        }
    }

    private var stateSection: some View {
        section(title: "Durum Görünümleri") {
            VStack(spacing: AppSpacing.xl) {
                EmptyState(
                    systemImage: "tray",
                    title: "Bugün atanmış iş yok",
                    message: "Size yeni bir iş atandığında burada listelenecektir."
                )

                LoadingView(message: "İş emirleri yükleniyor...")
                    .frame(height: 120)

                ErrorBanner(
                    title: "Servis raporu alınamadı",
                    message: "Sunucuya erişilemiyor. Bağlantınızı kontrol edin.",
                    onRetry: {}
                )
            }
        }
    }

    private var conflictSection: some View {
        section(title: "Çakışma") {
            ConflictSheet(
                field: "Planlanan Saat",
                server: .init(
                    title: "10:00 – 11:30",
                    subtitle: "Sunucudaki güncel plan",
                    updatedByLabel: "Mehmet Kaya",
                    timestampLabel: "18.08.2026 10:15"
                ),
                local: .init(
                    title: "11:00 – 12:00",
                    subtitle: "Cihazda offline yapılmış değişiklik",
                    updatedByLabel: "Ahmet Yılmaz",
                    timestampLabel: "18.08.2026 10:12"
                ),
                onUseServer: {},
                onUseLocal: {},
                onDismiss: {}
            )
        }
    }

    private var tabBarSection: some View {
        section(title: "Tab Bar") {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                Text("Operasyon Yetkilisi")
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.secondaryText)
                CustomTabBar<String>(
                    items: [
                        .init(tab: "dashboard", title: "Dashboard", systemImage: "square.grid.2x2"),
                        .init(tab: "orders", title: "İş Emirleri", systemImage: "list.bullet.rectangle"),
                        .init(tab: "notifications", title: "Bildirimler", systemImage: "bell"),
                        .init(tab: "profile", title: "Profil", systemImage: "person.crop.circle")
                    ],
                    selection: $operatorTab,
                    centerAction: .init(
                        systemImage: "plus",
                        accessibilityLabel: "Yeni İş Emri",
                        action: {}
                    )
                )
                .background(AppColor.brandSurface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))

                Text("Teknisyen")
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.secondaryText)
                CustomTabBar<String>(
                    items: [
                        .init(tab: "home", title: "Ana Sayfa", systemImage: "house"),
                        .init(tab: "orders", title: "İş Emirleri", systemImage: "list.bullet.rectangle"),
                        .init(tab: "notifications", title: "Bildirimler", systemImage: "bell"),
                        .init(tab: "profile", title: "Profil", systemImage: "person.crop.circle")
                    ],
                    selection: $technicianTab
                )
                .background(AppColor.brandSurface)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
            }
        }
    }

    // MARK: - Layout helpers

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            SectionHeader(title: title)
            content()
        }
    }

    private func swatchGrid(title: String, swatches: [(String, Color)]) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text(title)
                .font(AppFont.label)
                .foregroundStyle(AppColor.secondaryText)
            let columns = [
                GridItem(.flexible(), spacing: AppSpacing.s),
                GridItem(.flexible(), spacing: AppSpacing.s)
            ]
            LazyVGrid(columns: columns, spacing: AppSpacing.s) {
                ForEach(swatches, id: \.0) { name, color in
                    HStack(spacing: AppSpacing.s) {
                        RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                            .fill(color)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                                    .strokeBorder(AppColor.divider, lineWidth: 0.5)
                            )
                            .frame(width: 32, height: 32)
                        Text(name)
                            .font(AppFont.label)
                            .foregroundStyle(AppColor.primaryText)
                        Spacer()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func wrappedChips<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.s) {
                content()
            }
        }
    }
}

#Preview("Design System") {
    DesignSystemPreviewScreen()
}
#endif
