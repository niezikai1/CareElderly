// Views/Components/EmergencyCallButton.swift
// Emergency call button: available to both roles, shows confirmation before dialing

import SwiftUI
import UIKit

struct EmergencyCallButton: View {
    @State private var showConfirm = false
    @State private var isPressed   = false

    var body: some View {
        Button { showConfirm = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "phone.fill")
                    .font(.system(size: 18, weight: .bold))
                Text("Call Emergency Services · 911")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                LinearGradient(colors: [Color(hex: "C62828"), Color(hex: "D32F2F")],
                               startPoint: .leading, endPoint: .trailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: Color(hex: "D32F2F").opacity(0.4), radius: 8, y: 4)
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in withAnimation(.easeIn(duration: 0.1))  { isPressed = true  } }
                .onEnded   { _ in withAnimation(.easeOut(duration: 0.15)) { isPressed = false } }
        )
        .confirmationDialog("Call Emergency Services?", isPresented: $showConfirm, titleVisibility: .visible) {
            Button("Call 911", role: .destructive) { call("911") }
            Button("Call 120 (China)",   role: .destructive) { call("120") }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Please confirm the patient needs emergency assistance.")
        }
    }

    private func call(_ number: String) {
        guard let url = URL(string: "tel://\(number)"),
              UIApplication.shared.canOpenURL(url) else { return }
        UIApplication.shared.open(url)
    }
}

#Preview {
    EmergencyCallButton().padding(.horizontal, 24)
}
