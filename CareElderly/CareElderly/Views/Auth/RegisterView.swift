// Views/Auth/RegisterView.swift
// Registration screen: create a new Guardian or Patient account

import SwiftUI
import UIKit

struct RegisterView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authViewModel: AuthViewModel

    private let authService = AuthService()

    @State private var selectedRole:   UserRole = .guardian
    @State private var displayName     = ""
    @State private var username        = ""
    @State private var password        = ""
    @State private var confirmPassword = ""
    @State private var showPassword    = false

    @State private var isLoading       = false
    @State private var errorMessage:   String? = nil
    @State private var showSuccess     = false

    @State private var focusedField: Field?
    @State private var focusRequestID = 0
    enum Field { case displayName, username, password, confirmPassword }

    private var passwordsMatch: Bool { password == confirmPassword && !password.isEmpty }
    private var formValid: Bool { !displayName.isEmpty && !username.isEmpty && password.count >= 6 && passwordsMatch }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    roleSection
                    formSection
                    if let error = errorMessage {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red)
                            Text(error).font(.system(size: 13)).foregroundColor(.red)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    registerButton
                }
                .padding(24)
            }
            .navigationTitle("Create Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(Color(hex: "1976D2"))
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
        }
        .alert("Registration Successful!", isPresented: $showSuccess) {
            Button("Sign In") { dismiss() }
        } message: {
            Text("Your account has been created. Please sign in with \"\(username)\" as a \(selectedRole.displayName).")
        }
    }

    var roleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Select Role", systemImage: "person.2.fill")
                .font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
            HStack(spacing: 14) {
                ForEach(UserRole.allCases, id: \.self) { role in
                    RoleCard(role: role, isSelected: selectedRole == role)
                        .onTapGesture { withAnimation { selectedRole = role } }
                }
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle.fill").font(.system(size: 13)).foregroundColor(Color(hex: selectedRole.colorHex))
                Text(roleNote).font(.system(size: 12)).foregroundColor(.secondary)
            }
            .padding(12).background(Color(hex: selectedRole.backgroundColorHex)).clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private var roleNote: String {
        switch selectedRole {
        case .guardian:  return "Guardians receive real-time alert notifications including vibration, sound, and push notifications."
        case .monitored: return "Patients can view their own vital signs and history. No alert notifications will be sent."
        }
    }

    var formSection: some View {
        VStack(spacing: 16) {
            field(title: "Full Name", placeholder: "Enter your name", text: $displayName,
                  icon: "person.text.rectangle.fill", fieldCase: .displayName, autoCapitalize: .words)
            field(title: "Username", placeholder: "Set a login username (letters/numbers)",
                  text: $username, icon: "at", fieldCase: .username, autoCapitalize: .none)

            VStack(alignment: .leading, spacing: 6) {
                Text("Password").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill").foregroundColor(Color(hex: "1976D2")).frame(width: 20)
                    Group {
                        AuthInputField(
                            placeholder: "At least 6 characters",
                            text: $password,
                            isSecure: !showPassword,
                            isFirstResponder: focusedField == .password,
                            focusRequestID: focusRequestID,
                            keyboardType: .asciiCapable,
                            autocapitalizationType: .none,
                            returnKeyType: .next,
                            onEditingChanged: { isEditing in
                                focusedField = isEditing ? .password : nil
                            },
                            onSubmit: {
                                requestFocus(.confirmPassword)
                            }
                        )
                    }
                    Button { showPassword.toggle() } label: {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .foregroundColor(.secondary).frame(width: 24)
                    }
                }
                .formFieldStyle(isFocused: focusedField == .password)
                if !password.isEmpty && password.count < 6 {
                    Text("Password must be at least 6 characters").font(.caption).foregroundColor(.red)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Confirm Password").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill").foregroundColor(Color(hex: "1976D2")).frame(width: 20)
                    AuthInputField(
                        placeholder: "Re-enter password",
                        text: $confirmPassword,
                        isSecure: true,
                        isFirstResponder: focusedField == .confirmPassword,
                        focusRequestID: focusRequestID,
                        keyboardType: .asciiCapable,
                        autocapitalizationType: .none,
                        returnKeyType: .done,
                        onEditingChanged: { isEditing in
                            focusedField = isEditing ? .confirmPassword : nil
                        },
                        onSubmit: register
                    )
                }
                .formFieldStyle(isFocused: focusedField == .confirmPassword,
                                isError: !confirmPassword.isEmpty && !passwordsMatch)
                if !confirmPassword.isEmpty && !passwordsMatch {
                    Text("Passwords do not match").font(.caption).foregroundColor(.red)
                }
            }
        }
    }

    var registerButton: some View {
        Button(action: register) {
            Group {
                if isLoading { ProgressView().progressViewStyle(CircularProgressViewStyle(tint: .white)) }
                else         { Text("Create Account").font(.system(size: 17, weight: .semibold)) }
            }
            .foregroundColor(.white).frame(maxWidth: .infinity).frame(height: 54)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: selectedRole.colorHex)).opacity(formValid ? 1.0 : 0.55))
        }
        .disabled(!formValid || isLoading)
    }

    private func field(title: String, placeholder: String, text: Binding<String>,
                       icon: String, fieldCase: Field,
                       autoCapitalize: UITextAutocapitalizationType = .none) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
            HStack(spacing: 10) {
                Image(systemName: icon).foregroundColor(Color(hex: "1976D2")).frame(width: 20)
                AuthInputField(
                    placeholder: placeholder,
                    text: text,
                    isFirstResponder: focusedField == fieldCase,
                    focusRequestID: focusRequestID,
                    keyboardType: fieldCase == .displayName ? .default : .asciiCapable,
                    autocapitalizationType: autoCapitalize,
                    returnKeyType: .next,
                    onEditingChanged: { isEditing in
                        focusedField = isEditing ? fieldCase : nil
                    },
                    onSubmit: {
                        switch fieldCase {
                        case .displayName:
                            requestFocus(.username)
                        case .username:
                            requestFocus(.password)
                        case .password:
                            requestFocus(.confirmPassword)
                        case .confirmPassword:
                            register()
                        }
                    }
                )
            }
            .formFieldStyle(isFocused: focusedField == fieldCase)
        }
    }

    private func register() {
        requestFocus(nil)
        dismissTextInput()
        errorMessage = nil
        isLoading = true
        let trimmedUsername = username.trimmingCharacters(in: .whitespaces).lowercased()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let success = authService.register(username: trimmedUsername, password: password,
                                               displayName: displayName.trimmingCharacters(in: .whitespaces),
                                               role: selectedRole)
            isLoading = false
            if success { showSuccess = true }
            else { errorMessage = "Username \"\(trimmedUsername)\" is already taken. Please choose another." }
        }
    }

    private func requestFocus(_ field: Field?) {
        focusedField = field
        focusRequestID += 1
    }
}

struct AuthInputField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var isFirstResponder: Bool = false
    var focusRequestID: Int = 0
    var keyboardType: UIKeyboardType = .default
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var returnKeyType: UIReturnKeyType = .done
    var onEditingChanged: (Bool) -> Void = { _ in }
    var onSubmit: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onEditingChanged: onEditingChanged, onSubmit: onSubmit)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.placeholder = placeholder
        textField.text = text
        textField.keyboardType = keyboardType
        textField.autocorrectionType = .no
        textField.autocapitalizationType = autocapitalizationType
        textField.returnKeyType = returnKeyType
        textField.isSecureTextEntry = isSecure
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.clearButtonMode = .never
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // Disable the keyboard shortcut/accessory assistant bar. This avoids the
        // UIKit keyboard placeholder/accessory constraint conflict seen on auth screens.
        let assistant = textField.inputAssistantItem
        assistant.leadingBarButtonGroups = []
        assistant.trailingBarButtonGroups = []

        textField.addTarget(context.coordinator,
                            action: #selector(Coordinator.textDidChange(_:)),
                            for: .editingChanged)
        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        uiView.placeholder = placeholder
        uiView.keyboardType = keyboardType
        uiView.autocapitalizationType = autocapitalizationType
        uiView.returnKeyType = returnKeyType

        if isFirstResponder,
           context.coordinator.lastAppliedFocusRequestID != focusRequestID,
           !uiView.isFirstResponder {
            context.coordinator.lastAppliedFocusRequestID = focusRequestID
            uiView.becomeFirstResponder()
        } else if !isFirstResponder, uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }

        if uiView.isSecureTextEntry != isSecure {
            let existingText = uiView.text
            let wasFirstResponder = uiView.isFirstResponder
            uiView.isSecureTextEntry = isSecure
            uiView.text = existingText
            if wasFirstResponder {
                uiView.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String
        private let onEditingChanged: (Bool) -> Void
        private let onSubmit: () -> Void
        var lastAppliedFocusRequestID = 0

        init(text: Binding<String>, onEditingChanged: @escaping (Bool) -> Void, onSubmit: @escaping () -> Void) {
            _text = text
            self.onEditingChanged = onEditingChanged
            self.onSubmit = onSubmit
        }

        @objc func textDidChange(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            onEditingChanged(true)
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            onEditingChanged(false)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onSubmit()
            return true
        }
    }
}

func dismissTextInput() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                    to: nil,
                                    from: nil,
                                    for: nil)
}

private extension View {
    func formFieldStyle(isFocused: Bool, isError: Bool = false) -> some View {
        self.padding(14).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12)
                .stroke(isError ? Color.red.opacity(0.7) : (isFocused ? Color(hex: "1976D2") : Color.gray.opacity(0.22)), lineWidth: 1.5))
            .shadow(color: .black.opacity(0.04), radius: 4, y: 2)
    }
}

#Preview {
    RegisterView().environmentObject(AuthViewModel())
}
