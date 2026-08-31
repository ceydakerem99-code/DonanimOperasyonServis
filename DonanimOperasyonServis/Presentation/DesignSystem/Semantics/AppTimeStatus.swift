import SwiftUI

/// Visual styling for `WorkOrderTimeStatus` badges.
///
/// Uses dedicated `AppColor.time*` tokens — never shares priority
/// accent colors or `AppSemanticRole` KPI tokens.
extension WorkOrderTimeStatus {
    var accentColor: Color {
        switch self {
        case .today: return AppColor.timeToday
        case .approaching: return AppColor.timeApproaching
        case .delayed: return AppColor.timeDelayed
        case .windowPassed: return AppColor.timeWindowPassed
        case .scheduled: return AppColor.timeScheduled
        }
    }
}
