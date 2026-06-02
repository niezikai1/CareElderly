// Views/Auth/LoginView.swift
// Login screen: role selection + username/password authentication

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    @EnvironmentObject var appState: AppState

    @State private var username      = ""
    @State private var password      = ""
    @State private var selectedRole: UserRole = .guardian
    @State private var showPassword  = false
    @State private var showRegister  = false

    @State private var focusedField: LoginField?
    @State private var focusRequestID = 0
    enum LoginField { case username, password }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "EFF6FF"), Color(hex: "FFFFFF"), Color(hex: "F0FDF4")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    headerSection
                    roleSection.padding(.top, 32).padding(.horizontal, 24)
                    formSection.padding(.top, 24).padding(.horizontal, 24)
                    actionSection.padding(.top, 28).padding(.horizontal, 24).padding(.bottom, 48)
                }
            }
        }
        .onChange(of: authViewModel.isLoggedIn) { _, loggedIn in
            if loggedIn, let user = authViewModel.currentUser {
                appState.configure(for: user.role)
            }
        }
        .sheet(isPresented: $showRegister) {
            RegisterView().environmentObject(authViewModel)
        }
    }

    // MARK: - Header
    var headerSection: some View {
        VStack(spacing: 14) {
            Spacer().frame(height: 56)
            ZStack {
                Circle().fill(Color(hex: "DBEAFE")).frame(width: 96, height: 96)
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 46)).foregroundColor(Color(hex: "1976D2"))
            }
            Text("Vital Sign Monitor")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "0D47A1"))
            Text("Select your role and sign in")
                .font(.subheadline).foregroundColor(.secondary)
            Spacer().frame(height: 4)
        }
    }

    // MARK: - Role Selection
    var roleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Select Role", systemImage: "person.2.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            HStack(spacing: 14) {
                ForEach(UserRole.allCases, id: \.self) { role in
                    RoleCard(role: role, isSelected: selectedRole == role)
                        .onTapGesture { withAnimation { selectedRole = role } }
                }
            }
        }
    }

    // MARK: - Login Form
    var formSection: some View {
        VStack(spacing: 16) {
            inputField(title: "Username", placeholder: "Enter username",
                       text: $username, icon: "person.fill", field: .username)

            VStack(alignment: .leading, spacing: 6) {
                Text("Password")
                    .font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill").foregroundColor(Color(hex: "1976D2")).frame(width: 20)
                    Group {
                        AuthInputField(
                            placeholder: "Enter password",
                            text: $password,
                            isSecure: !showPassword,
                            isFirstResponder: focusedField == .password,
                            focusRequestID: focusRequestID,
                            keyboardType: .asciiCapable,
                            autocapitalizationType: .none,
                            returnKeyType: .go,
                            onEditingChanged: { isEditing in
                                focusedField = isEditing ? .password : nil
                            },
                            onSubmit: attemptLogin
                        )
                    }
                    Button { showPassword.toggle() } label: {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.secondary).frame(width: 24, height: 24)
                    }
                }
                .padding(14).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(focusedField == .password ? Color(hex: "1976D2") : Color.gray.opacity(0.22), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
            }

            if let error = authViewModel.loginError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                    Text(error).font(.system(size: 13)).foregroundColor(.red)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Actions
    var actionSection: some View {
        VStack(spacing: 20) {
            Button(action: attemptLogin) {
                HStack(spacing: 10) {
                    if authViewModel.isLoading {
                        ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)).scaleEffect(0.85)
                    } else {
                        Image(systemName: selectedRole.icon).font(.system(size: 16, weight: .semibold))
                        Text("Sign in as \(selectedRole.displayName)").font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 54)
                .background(LinearGradient(colors: [Color(hex: selectedRole.colorHex), Color(hex: selectedRole.colorHex).opacity(0.85)],
                                           startPoint: .leading, endPoint: .trailing))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .shadow(color: Color(hex: selectedRole.colorHex).opacity(0.4), radius: 10, y: 5)
                .opacity(canLogin ? 1.0 : 0.6)
            }
            .disabled(!canLogin)

            VStack(spacing: 8) {
                Text("Demo Accounts").font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
                HStack(spacing: 12) {
                    demoHint(label: "Guardian", user: "guardian1", pwd: "1234", role: .guardian)
                    demoHint(label: "Patient",  user: "elder1",    pwd: "1234", role: .monitored)
                }
            }

            Divider()

            Button { showRegister = true } label: {
                HStack(spacing: 4) {
                    Text("Don't have an account?").foregroundColor(.secondary)
                    Text("Register").foregroundColor(Color(hex: "1976D2")).fontWeight(.semibold)
                }
                .font(.system(size: 15))
            }
        }
    }

    // MARK: - Helpers
    private func inputField(title: String, placeholder: String, text: Binding<String>,
                            icon: String, field: LoginField) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundColor(Color(hex: "1976D2")).frame(width: 20)
                AuthInputField(
                    placeholder: placeholder,
                    text: text,
                    isFirstResponder: focusedField == field,
                    focusRequestID: focusRequestID,
                    keyboardType: .asciiCapable,
                    autocapitalizationType: .none,
                    returnKeyType: .next,
                    onEditingChanged: { isEditing in
                        focusedField = isEditing ? field : nil
                    },
                    onSubmit: {
                        requestFocus(.password)
                    }
                )
            }
            .padding(14).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(focusedField == field ? Color(hex: "1976D2") : Color.gray.opacity(0.22), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
        }
    }

    private func demoHint(label: String, user: String, pwd: String, role: UserRole) -> some View {
        Button {
            username = user; password = pwd; selectedRole = role
        } label: {
            VStack(spacing: 3) {
                Text(label).font(.system(size: 11)).foregroundColor(.secondary)
                Text("\(user) / \(pwd)").font(.system(size: 11, design: .monospaced)).foregroundColor(Color(hex: role.colorHex))
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color(hex: role.backgroundColorHex)).clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var canLogin: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty && !authViewModel.isLoading
    }

    private func requestFocus(_ field: LoginField?) {
        focusedField = field
        focusRequestID += 1
    }

    private func attemptLogin() {
        requestFocus(nil)
        dismissTextInput()
        guard canLogin else { return }
        authViewModel.login(username: username, password: password, role: selectedRole)
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
        .environmentObject(AppState())
}
