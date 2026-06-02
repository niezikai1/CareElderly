// Views/Components/RoleCard.swift
// Role selection card component (reused in LoginView and RegisterView)

import SwiftUI

struct RoleCard: View {
    let role: UserRole
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.white.opacity(0.2) : Color(hex: role.colorHex).opacity(0.12))
                    .frame(width: 52, height: 52)
                Image(systemName: role.icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? .white : Color(hex: role.colorHex))
            }

            Text(role.displayName)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(isSelected ? .white : Color(hex: role.colorHex))

            Text(role.description)
                .font(.system(size: 11))
                .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 8)
        .background(
            Group {
                if isSelected {
                    LinearGradient(colors: [Color(hex: role.colorHex), Color(hex: role.colorHex).opacity(0.8)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                } else {
                    LinearGradient(colors: [Color.white, Color.white], startPoint: .top, endPoint: .bottom)
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.clear : Color(hex: role.colorHex).opacity(0.3), lineWidth: 1.5)
        )
        .shadow(color: isSelected ? Color(hex: role.colorHex).opacity(0.35) : Color.black.opacity(0.05),
                radius: isSelected ? 10 : 4, y: isSelected ? 5 : 2)
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: isSelected)
    }
}

#Preview {
    HStack(spacing: 16) {
        RoleCard(role: .guardian,  isSelected: true)
        RoleCard(role: .monitored, isSelected: false)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
