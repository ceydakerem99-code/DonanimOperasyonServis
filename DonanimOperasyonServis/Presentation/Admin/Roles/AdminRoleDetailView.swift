import SwiftUI

struct AdminRoleDetailView: View {
    let role: UserRole

    private var granted: Set<DomainAction> {
        RoleAccessPolicyAdminUI.grantedActions(for: role)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.l) {
                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                    Text(role.displayName)
                        .font(AppFont.title)
                    Text(RoleAccessPolicyAdminUI.roleDescription(for: role))
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.secondaryText)
                }
                .padding(.top, AppSpacing.s)

                SectionHeader(title: "Yetki Matrisi (Salt Okunur)")

                VStack(spacing: 0) {
                    ForEach(RoleAccessPolicyAdminUI.allActions, id: \.self) { action in
                        permissionRow(action)
                        if action != RoleAccessPolicyAdminUI.allActions.last {
                            Divider()
                        }
                    }
                }
                .padding(AppSpacing.m)
                .background(RoundedRectangle(cornerRadius: AppRadius.card).fill(AppColor.elevatedSurface))
                .overlay(RoundedRectangle(cornerRadius: AppRadius.card).strokeBorder(AppColor.divider))

                Text("Rol yetkileri kod tabanlıdır ve çalışma zamanında değiştirilemez.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.secondaryText)
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.bottom, AppSpacing.xl)
        }
        .navigationTitle("Rol Detayı")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func permissionRow(_ action: DomainAction) -> some View {
        let allowed = granted.contains(action)
        return HStack(spacing: AppSpacing.s) {
            Image(systemName: allowed ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(allowed ? AppColor.success : AppColor.secondaryText)
            Text(action.adminDisplayName)
                .font(AppFont.body)
                .foregroundStyle(allowed ? AppColor.primaryText : AppColor.secondaryText)
            Spacer()
        }
        .frame(minHeight: AppSpacing.minimumTouchTarget)
        .accessibilityLabel("\(action.adminDisplayName), \(allowed ? "izinli" : "izinsiz")")
    }
}

#if DEBUG
#Preview("Role Detail — Admin") {
    NavigationStack {
        AdminRoleDetailView(role: .admin)
    }
}

#Preview("Role Detail — Operator") {
    NavigationStack {
        AdminRoleDetailView(role: .operator)
    }
}
#endif
