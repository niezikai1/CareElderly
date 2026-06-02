// Services/AuthService.swift
// Authentication service: local account validation and registration

import Foundation

class AuthService {

    // MARK: - Built-in demo accounts
    private let demoAccounts: [(username: String, password: String, displayName: String, role: UserRole)] = [
        ("guardian1", "1234",  "Guardian (Demo)", .guardian),
        ("elder1",    "1234",  "Patient (Demo)",  .monitored),
    ]

    // MARK: - Authenticate
    /// Returns a User object on success, nil on failure
    func authenticate(username: String, password: String, role: UserRole) -> User? {

        // 1. Check demo accounts
        for account in demoAccounts {
            if account.username == username,
               account.password == password,
               account.role     == role {
                return User(username: account.username,
                            displayName: account.displayName,
                            role: role)
            }
        }

        // 2. Check registered accounts
        let registered = loadRegisteredAccounts()
        for user in registered where user.username == username && user.role == role {
            let stored = UserDefaults.standard.string(forKey: "pwd_\(username)") ?? ""
            if stored == password {
                return user
            }
        }

        return nil
    }

    // MARK: - Register
    /// Returns true on success, false if username already exists
    @discardableResult
    func register(username: String, password: String, displayName: String, role: UserRole) -> Bool {

        let demoUsernames = demoAccounts.map { $0.username }
        if demoUsernames.contains(username) { return false }

        var accounts = loadRegisteredAccounts()
        if accounts.contains(where: { $0.username.lowercased() == username.lowercased() }) { return false }

        let newUser = User(username: username, displayName: displayName, role: role)
        accounts.append(newUser)

        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: "registeredAccounts")
            UserDefaults.standard.set(password, forKey: "pwd_\(username)")
            return true
        }
        return false
    }

    // MARK: - Delete account
    /// Removes a registered account. Returns false for built-in demo accounts.
    @discardableResult
    func deleteAccount(username: String) -> Bool {
        let demoUsernames = demoAccounts.map { $0.username }
        if demoUsernames.contains(username) { return false }

        var accounts = loadRegisteredAccounts()
        accounts.removeAll { $0.username.lowercased() == username.lowercased() }

        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: "registeredAccounts")
        }
        UserDefaults.standard.removeObject(forKey: "pwd_\(username)")
        return true
    }

    // MARK: - Change password
    func changePassword(username: String, oldPassword: String, newPassword: String) -> Bool {
        let stored = UserDefaults.standard.string(forKey: "pwd_\(username)") ?? ""
        guard stored == oldPassword else { return false }
        UserDefaults.standard.set(newPassword, forKey: "pwd_\(username)")
        return true
    }

    // MARK: - Private helpers
    private func loadRegisteredAccounts() -> [User] {
        guard
            let data = UserDefaults.standard.data(forKey: "registeredAccounts"),
            let accounts = try? JSONDecoder().decode([User].self, from: data)
        else { return [] }
        return accounts
    }
}
