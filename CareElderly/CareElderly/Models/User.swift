// Models/User.swift
// User model: defines role enum and user data structure

import Foundation

// MARK: - User Role Enum
/// Distinguishes two user types with different permissions
enum UserRole: String, Codable, CaseIterable {
    case guardian  = "guardian"   // Guardian (family member / caregiver)
    case monitored = "monitored"  // Patient (the elderly person who is monitored)

    // MARK: Display name
    var displayName: String {
        switch self {
        case .guardian:  return "Guardian"
        case .monitored: return "Patient"
        }
    }

    // MARK: SF Symbol icon
    var icon: String {
        switch self {
        case .guardian:  return "person.badge.shield.checkmark.fill"
        case .monitored: return "figure.arms.open"
        }
    }

    // MARK: Role description
    var description: String {
        switch self {
        case .guardian:  return "Receives alerts & push notifications"
        case .monitored: return "View data only, no notifications"
        }
    }

    // MARK: Theme color (hex)
    var colorHex: String {
        switch self {
        case .guardian:  return "1565C0"  // Deep blue
        case .monitored: return "2E7D32"  // Deep green
        }
    }

    // MARK: Background color (hex)
    var backgroundColorHex: String {
        switch self {
        case .guardian:  return "E3F2FD"  // Light blue
        case .monitored: return "E8F5E9"  // Light green
        }
    }

    /// Only guardians receive push notifications and strong alerts
    var receivesNotifications: Bool {
        return self == .guardian
    }
}

// MARK: - User Data Model
struct User: Codable, Identifiable, Equatable {
    let id: UUID
    let username: String
    var displayName: String
    let role: UserRole
    let createdAt: Date

    init(username: String, displayName: String, role: UserRole) {
        self.id          = UUID()
        self.username    = username
        self.displayName = displayName
        self.role        = role
        self.createdAt   = Date()
    }

    static func == (lhs: User, rhs: User) -> Bool {
        lhs.id == rhs.id
    }
}
