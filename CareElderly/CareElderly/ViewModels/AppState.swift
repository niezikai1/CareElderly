// ViewModels/AppState.swift
// Global app state: tab navigation, notification permissions, role-aware alerts

import SwiftUI
import UIKit
import Combine
import UserNotifications
import AudioToolbox

class AppState: ObservableObject {

    // MARK: - Published Properties
    @Published var selectedTab: Int        = 0
    @Published var notificationsEnabled: Bool = false
    @Published var unreadAlertCount: Int   = 0

    // Whether a guardian alert popup is currently active
    @Published var activeAlertEvent: AlertEvent? = nil
    @Published var showAlertPopup: Bool    = false

    @Published var connectionStatus: ConnectionStatus = .disconnected

    // MARK: - Private Properties
    private var alertRepeatTimer: Timer?
    private var foregroundAlertLoopTimer: Timer?
    private let foregroundAlertSoundID: SystemSoundID = 1005
    private var scenePhase: ScenePhase = .active

    // MARK: - Configure App Behavior Based on Role
    /// Called after a successful login to request notification permission if applicable
    func configure(for role: UserRole) {
        selectedTab = 0   // reset on every login so patient never lands on a guardian-only tab
        clearBadgeState()
        if role.receivesNotifications {
            requestNotificationPermission()
        } else {
            notificationsEnabled = false
        }
    }

    // MARK: - Request Notification Permission
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound, .badge, .criticalAlert]
        ) { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.notificationsEnabled = granted
                if let error {
                    print("❌ Notification permission request failed: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Guardian-Only: Trigger Strong Alert (only when role == .guardian)
    /// Called when an abnormal event is received — triggers popup + vibration + sound + push notification
    func triggerGuardianAlert(event: AlertEvent) {
        // Persist to Core Data so AlertsView can display it
        let ctx = PersistenceController.shared.context
        AlertRecord.insert(from: event, in: ctx)
        PersistenceController.shared.save()

        // Set the active alert event
        activeAlertEvent = event
        showAlertPopup   = true

        // Increment unread count
        unreadAlertCount += 1

        // Haptic vibration
        triggerVibration(isCritical: event.type.isCritical)
        playAlertSound(isCritical: event.type.isCritical)

        // Background push notification (delivered even when app is in background)
        if notificationsEnabled {
            scheduleLocalNotification(for: event)
        }

        // Critical events: repeat alert every 30 seconds until acknowledged
        if event.type.isCritical {
            startRepeatAlert(event: event)
            startForegroundAlertLoopIfNeeded()
        }
    }

    /// Acknowledge alert (stops repeat alerts)
    func acknowledgeAlert() {
        showAlertPopup   = false
        activeAlertEvent = nil
        stopRepeatAlert()
        stopForegroundAlertLoop()
        // Decrement unread count
        if unreadAlertCount > 0 { unreadAlertCount -= 1 }
        clearBadgeState()
    }

    func handleScenePhaseChange(_ newPhase: ScenePhase) {
        scenePhase = newPhase
        if newPhase == .active {
            // Opening the app counts as acknowledging the audible reminder.
            stopForegroundAlertLoop()
            clearBadgeState()
        } else if showAlertPopup, activeAlertEvent?.type.isCritical == true {
            startForegroundAlertLoopIfNeeded()
        }
    }

    // MARK: - Haptic Vibration
    private func triggerVibration(isCritical: Bool) {
        if isCritical {
            // Critical: strong error feedback
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        } else {
            // Warning: medium feedback
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    private func playAlertSound(isCritical: Bool) {
        if isCritical {
            AudioServicesPlayAlertSound(foregroundAlertSoundID)
        } else {
            AudioServicesPlaySystemSound(1007)
        }
    }

    private func startForegroundAlertLoopIfNeeded() {
        guard scenePhase == .active,
              showAlertPopup,
              activeAlertEvent?.type.isCritical == true,
              foregroundAlertLoopTimer == nil else { return }

        foregroundAlertLoopTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { [weak self] _ in
            guard let self,
                  self.scenePhase == .active,
                  self.showAlertPopup,
                  self.activeAlertEvent?.type.isCritical == true else {
                self?.stopForegroundAlertLoop()
                return
            }

            self.playAlertSound(isCritical: true)
        }
    }

    private func stopForegroundAlertLoop() {
        foregroundAlertLoopTimer?.invalidate()
        foregroundAlertLoopTimer = nil
    }

    // MARK: - Local Push Notification
    private func scheduleLocalNotification(for event: AlertEvent) {
        let content = UNMutableNotificationContent()
        content.title            = "⚠️ \(event.type.displayName)"
        content.body             = event.type.advice
        content.sound            = event.type.isCritical
                                   ? UNNotificationSound.defaultCriticalSound(withAudioVolume: 1.0)
                                   : UNNotificationSound.default
        content.interruptionLevel = event.type.isCritical ? .critical : .timeSensitive
        content.badge            = (unreadAlertCount) as NSNumber

        let request = UNNotificationRequest(
            identifier: event.id.uuidString,
            content: content,
            trigger: nil  // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("❌ Notification delivery failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Repeat Alert (for Critical Events)
    private func startRepeatAlert(event: AlertEvent) {
        stopRepeatAlert()
        alertRepeatTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            guard let self, self.showAlertPopup else {
                self?.stopRepeatAlert()
                return
            }
            if self.scenePhase != .active {
                self.triggerVibration(isCritical: true)
                self.playAlertSound(isCritical: true)
            }
            if self.notificationsEnabled {
                self.scheduleLocalNotification(for: event)
            }
        }
    }

    private func stopRepeatAlert() {
        alertRepeatTimer?.invalidate()
        alertRepeatTimer = nil
    }

    private func clearBadgeState() {
        unreadAlertCount = 0
        let center = UNUserNotificationCenter.current()
        center.setBadgeCount(0)
        center.removeAllDeliveredNotifications()
    }

    // MARK: - Navigate to Alerts Tab
    func navigateToAlerts() {
        selectedTab = 3  // Tab index 3: Alert Center (index shifted by Insights tab at 2)
    }
}

// MARK: - Connection Status
enum ConnectionStatus {
    case connected(serverURL: String)
    case connecting
    case disconnected
    case error(message: String)

    var displayText: String {
        switch self {
        case .connected(let url): return "Connected: \(url)"
        case .connecting:         return "Connecting…"
        case .disconnected:       return "Not Connected"
        case .error(let msg):     return "Connection Error: \(msg)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var colorHex: String {
        switch self {
        case .connected:    return "2E7D32"
        case .connecting:   return "F57C00"
        case .disconnected: return "9E9E9E"
        case .error:        return "D32F2F"
        }
    }
}
