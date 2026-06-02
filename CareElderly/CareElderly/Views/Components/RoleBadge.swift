// Views/Components/RoleBadge.swift
// Role indicator badge - always visible in top-right corner

import SwiftUI

struct RoleBadge: View {
    let user: User

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: user.role.icon)
                .font(.system(size: 11, weight: .semibold))
            Text(user.role.displayName)
                .font(.system(size: 11, weight: .bold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(hex: user.role.colorHex))
                .shadow(color: Color(hex: user.role.colorHex).opacity(0.35), radius: 6, y: 3)
        )
    }
}

#Preview {
    VStack(spacing: 12) {
        RoleBadge(user: User(username: "g1", displayName: "Family", role: .guardian))
        RoleBadge(user: User(username: "e1", displayName: "Grandma", role: .monitored))
    }
    .padding()
}
