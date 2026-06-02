// ViewModels/AuthViewModel.swift
// Authentication state management: login, logout, session persistence

import SwiftUI
import Combine

class AuthViewModel: ObservableObject {

    // MARK: - Published properties (drive UI updates)
    @Published var isLoggedIn: Bool    = false
    @Published var currentUser: User?  = nil
    @Published var loginError: String? = nil
    @Published var isLoading: Bool     = false

    private let authService = AuthService()

    init() {
        loadSavedSession()  // Restore last login session on launch
    }

    // MARK: - Computed properties
    /// Whether the current user is a Guardian
    var isGuardian: Bool {
        currentUser?.role == .guardian
    }

    /// Current user role (defaults to .monitored if not logged in)
    var currentRole: UserRole {
        currentUser?.role ?? .monitored
    }

    // MARK: - Login
    /// Authenticate with username, password, and selected role
    func login(username: String, password: String, role: UserRole) {
        guard !username.isEmpty, !password.isEmpty else {
            loginError = "Username and password cannot be empty"
            return
        }

        isLoading  = true
        loginError = nil

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }

            if let user = self.authService.authenticate(
                username: username.trimmingCharacters(in: .whitespaces).lowercased(),
                password: password,
                role: role
            ) {
                self.currentUser = user
                self.isLoggedIn  = true
                self.saveSession(user: user)
                self.loginError  = nil
            } else {
                self.loginError = "Incorrect username or password. Please try again."
            }
            self.isLoading = false
        }
    }

    // MARK: - Delete Account
    /// Deletes the current account and signs out. Returns false for demo accounts.
    @discardableResult
    func deleteAccount() -> Bool {
        guard let user = currentUser else { return false }
        let success = authService.deleteAccount(username: user.username)
        logout()
        return success
    }

    // MARK: - Logout
    func logout() {
        isLoggedIn   = false
        currentUser  = nil
        loginError   = nil
        clearSession()
    }

    // MARK: - Session persistence (UserDefaults; production: use Keychain)
    private func saveSession(user: User) {
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: "session_currentUser")
        }
    }

    private func loadSavedSession() {
        guard
            let data = UserDefaults.standard.data(forKey: "session_currentUser"),
            let user = try? JSONDecoder().decode(User.self, from: data)
        else { return }

        self.currentUser = user
        self.isLoggedIn  = true
    }

    private func clearSession() {
        UserDefaults.standard.removeObject(forKey: "session_currentUser")
    }
}
