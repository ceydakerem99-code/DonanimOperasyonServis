import SwiftUI

struct AdminRootPlaceholder: View {
    let user: User
    let onLogout: () -> Void

    var body: some View {
        RoleRootPlaceholder(
            title: "Admin",
            subtitle: user.fullName,
            systemImage: "person.crop.circle.badge.checkmark",
            onLogout: onLogout
        )
    }
}

struct OperatorRootPlaceholder: View {
    let user: User
    let onLogout: () -> Void

    var body: some View {
        RoleRootPlaceholder(
            title: UserRole.operator.displayName,
            subtitle: user.fullName,
            systemImage: "person.2.fill",
            onLogout: onLogout
        )
    }
}

struct TechnicianRootPlaceholder: View {
    let user: User
    let onLogout: () -> Void

    var body: some View {
        RoleRootPlaceholder(
            title: UserRole.technician.displayName,
            subtitle: user.fullName,
            systemImage: "wrench.and.screwdriver.fill",
            onLogout: onLogout
        )
    }
}

private struct RoleRootPlaceholder: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let onLogout: () -> Void

    var body: some View {
        VStack(spacing: AppSpacing.l) {
            Image(systemName: systemImage)
                .font(.system(size: 48, weight: .semibold))
                .foregroundStyle(AppColor.brandPrimary)

            Text(title)
                .font(AppFont.title)
                .foregroundStyle(AppColor.primaryText)

            Text(subtitle)
                .font(AppFont.body)
                .foregroundStyle(AppColor.secondaryText)

            Text("Faz 6 — Rol yönlendirmesi doğrulandı.")
                .font(AppFont.caption)
                .foregroundStyle(AppColor.secondaryText)
                .multilineTextAlignment(.center)

            SecondaryButton(title: "Çıkış Yap", systemImage: "rectangle.portrait.and.arrow.right") {
                onLogout()
            }
            .padding(.top, AppSpacing.m)
        }
        .padding(AppSpacing.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.neutralBackground)
    }
}

#if DEBUG
#Preview("Role placeholders") {
    let user = User(
        id: UserID("preview-user"),
        email: "preview@example.com",
        fullName: "Önizleme Kullanıcı",
        role: .admin,
        createdAt: Date(),
        updatedAt: Date()
    )
    TabView {
        AdminRootPlaceholder(user: user, onLogout: {})
        OperatorRootPlaceholder(user: user, onLogout: {})
        TechnicianRootPlaceholder(user: user, onLogout: {})
    }
}
#endif
