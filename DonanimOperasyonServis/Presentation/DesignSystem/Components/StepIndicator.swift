import SwiftUI

/// Horizontal step indicator for multi-step flows such as the
/// New Work Order wizard.
///
/// Renders one dot per step connected by lines. Completed steps are
/// filled, the active step is highlighted, and future steps appear muted.
struct StepIndicator: View {
    /// 1-based index of the currently active step.
    let currentStep: Int
    let totalSteps: Int
    /// Optional short labels shown under each dot (e.g. "İş Türü").
    var titles: [String]?

    var body: some View {
        VStack(spacing: AppSpacing.xs) {
            HStack(spacing: 0) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    let stepNumber = index + 1
                    dot(for: stepNumber)
                    if index < totalSteps - 1 {
                        connector(after: stepNumber)
                    }
                }
            }

            if let titles, titles.count == totalSteps {
                HStack(spacing: 0) {
                    ForEach(0..<totalSteps, id: \.self) { index in
                        Text(titles[index])
                            .font(AppFont.label)
                            .foregroundStyle(labelColor(for: index + 1))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Adım \(currentStep) / \(totalSteps)"))
    }

    private func dot(for stepNumber: Int) -> some View {
        let state = state(for: stepNumber)
        return ZStack {
            Circle()
                .fill(state.fill)
            Circle()
                .strokeBorder(state.stroke, lineWidth: state == .upcoming ? 1 : 0)
            if state == .completed {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColor.onPrimary)
            } else {
                Text("\(stepNumber)")
                    .font(AppFont.label)
                    .foregroundStyle(state == .upcoming ? AppColor.secondaryText : AppColor.onPrimary)
            }
        }
        .frame(width: 26, height: 26)
    }

    private func connector(after stepNumber: Int) -> some View {
        Rectangle()
            .fill(stepNumber < currentStep ? AppColor.brandPrimary : AppColor.divider)
            .frame(height: 2)
            .frame(maxWidth: .infinity)
    }

    private func labelColor(for stepNumber: Int) -> Color {
        switch state(for: stepNumber) {
        case .completed, .active: return AppColor.primaryText
        case .upcoming:           return AppColor.secondaryText
        }
    }

    private enum StepState { case completed, active, upcoming
        @MainActor var fill: Color {
            switch self {
            case .completed: return AppColor.brandPrimary
            case .active:    return AppColor.brandPrimary
            case .upcoming:  return AppColor.brandSurface
            }
        }
        @MainActor var stroke: Color {
            switch self {
            case .upcoming: return AppColor.divider
            default:        return .clear
            }
        }
    }

    private func state(for stepNumber: Int) -> StepState {
        if stepNumber < currentStep { return .completed }
        if stepNumber == currentStep { return .active }
        return .upcoming
    }
}

#if DEBUG
#Preview("StepIndicator") {
    let titles = ["İş Türü", "Müşteri", "Cihaz", "Öncelik", "Teknisyen", "Özet"]
    return VStack(spacing: AppSpacing.xl) {
        StepIndicator(currentStep: 1, totalSteps: 6, titles: titles)
        StepIndicator(currentStep: 3, totalSteps: 6, titles: titles)
        StepIndicator(currentStep: 6, totalSteps: 6, titles: titles)
        StepIndicator(currentStep: 2, totalSteps: 6)
    }
    .padding(AppSpacing.l)
    .background(AppColor.neutralBackground)
}
#endif
