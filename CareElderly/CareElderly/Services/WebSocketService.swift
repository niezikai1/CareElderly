// Services/WebSocketService.swift
// WebSocket client (legacy; inactive — kept for ServerMessage struct).
// Handles connection lifecycle, JSON message parsing, heartbeat keep-alive,
// and exponential-backoff auto-reconnection.

import Foundation
import Combine

// MARK: - Incoming JSON message envelope
/// Decodes both vital-sign packets (no "type" field) and alert event packets.
struct ServerMessage: Codable {
    let type: String?             // nil for vital-sign packets; "alert" for alert events

    // vital-sign fields
    let heartRate: Double?        // bpm  (key: "heart_rate_bpm")
    let breathingRate: Double?    // rpm  (key: "respiratory_rate_rpm")
    let bodyTemperature: Double?  // °C   (key: "body_temperature_celsius")
    let timestampMs: Double?      // Unix epoch milliseconds (key: "timestamp_ms")

    // alert fields
    let eventType: String?        // AlertType raw value (e.g. "fall")

    enum CodingKeys: String, CodingKey {
        case type
        case heartRate        = "heart_rate_bpm"
        case breathingRate    = "respiratory_rate_rpm"
        case bodyTemperature  = "body_temperature_celsius"
        case timestampMs      = "timestamp_ms"
        case eventType        = "event_type"
    }
}

// MARK: - WebSocketService
/// Manages a single URLSessionWebSocketTask connection to the backend.
/// Publishes decoded vital-sign data and alert events on the main thread.
class WebSocketService: NSObject, ObservableObject {

    // MARK: Published state
    @Published var connectionStatus: ConnectionStatus = .disconnected

    /// Latest decoded vital sign packet (nil when disconnected)
    @Published var lastVitalSign: VitalSignData?

    /// Set whenever an alert message arrives; consumed and cleared by the caller
    @Published var pendingAlertEvent: AlertEvent?

    // MARK: Private state
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession!
    private var currentURL: URL?

    private var reconnectTask: Task<Void, Never>?
    private var heartbeatTimer: AnyCancellable?

    private var reconnectAttempts  = 0
    private let maxReconnectDelay: TimeInterval = 60   // seconds
    private let baseReconnectDelay: TimeInterval = 3   // seconds
    private let heartbeatInterval:  TimeInterval = 30  // seconds

    /// Whether the service should auto-reconnect on disconnection
    var autoReconnect = true

    // MARK: - Lifecycle
    override init() {
        super.init()
        // Delegate queue is nil → callbacks run on a URLSession internal thread;
        // all Published updates must be dispatched to main.
        urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    // MARK: - Public API

    /// Connect to the specified WebSocket URL (ws:// or wss://)
    func connect(to urlString: String) {
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async { self.connectionStatus = .error(message: "Invalid URL: \(urlString)") }
            return
        }
        disconnect(shouldReconnect: false)
        currentURL  = url
        reconnectAttempts = 0
        openSocket(url: url)
    }

    /// Cleanly close the WebSocket connection and stop reconnection attempts
    func disconnect(shouldReconnect: Bool = false) {
        if !shouldReconnect { autoReconnect = false }
        cancelReconnect()
        stopHeartbeat()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        if !shouldReconnect {
            DispatchQueue.main.async { self.connectionStatus = .disconnected }
        }
    }

    // MARK: - Private: Socket Management

    private func openSocket(url: URL) {
        DispatchQueue.main.async { self.connectionStatus = .connecting }
        let task = urlSession.webSocketTask(with: url)
        webSocketTask = task
        task.resume()
        scheduleNextReceive()
    }

    // MARK: - Private: Message Loop (recursive)

    private func scheduleNextReceive() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                // Check if this was a deliberate cancellation
                let nsErr = error as NSError
                let deliberate = nsErr.domain == NSURLErrorDomain &&
                                 nsErr.code   == NSURLErrorCancelled
                if !deliberate {
                    DispatchQueue.main.async { self.handleDisconnection(error: error) }
                }
            case .success(let msg):
                self.decodeAndDispatch(msg)
                self.scheduleNextReceive()   // Keep listening
            }
        }
    }

    // MARK: - Private: JSON Decoding

    private func decodeAndDispatch(_ msg: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch msg {
        case .string(let s): data = s.data(using: .utf8)
        case .data(let d):   data = d
        @unknown default:    return
        }
        guard let data else { return }

        do {
            let envelope = try JSONDecoder().decode(ServerMessage.self, from: data)
            DispatchQueue.main.async { self.processEnvelope(envelope) }
        } catch {
            print("⚠️ WebSocket decode error: \(error.localizedDescription)")
        }
    }

    private func processEnvelope(_ msg: ServerMessage) {
        switch msg.type {

        case "alert":
            guard let rawType = msg.eventType,
                  let alertType = AlertType(rawValue: rawType) else {
                print("⚠️ Unknown alert event_type: \(msg.eventType ?? "nil")"); return
            }
            let event = AlertEvent(
                type:          alertType,
                heartRate:     msg.heartRate,
                breathingRate: msg.breathingRate
            )
            pendingAlertEvent = event

        case "pong":
            break

        default:
            // nil or "vital_sign" — treat as vital-sign data
            guard let hr = msg.heartRate, let br = msg.breathingRate else {
                print("⚠️ Vital-sign packet missing hr/br"); return
            }
            let ts = msg.timestampMs.map { Date(timeIntervalSince1970: $0 / 1000.0) } ?? Date()
            lastVitalSign = VitalSignData(heartRate: hr, breathingRate: br,
                                          bodyTemperature: msg.bodyTemperature, timestamp: ts)
        }
    }

    // MARK: - Private: Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTimer = Timer.publish(every: heartbeatInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in self?.sendPing() }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    private func sendPing() {
        let pingJSON = #"{"type":"ping"}"#
        webSocketTask?.send(.string(pingJSON)) { error in
            if let error {
                print("⚠️ Ping failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private: Reconnection (exponential back-off)

    private func handleDisconnection(error: Error?) {
        stopHeartbeat()
        webSocketTask = nil

        guard autoReconnect, let url = currentURL, reconnectAttempts < 20 else {
            connectionStatus = .disconnected
            return
        }

        // Exponential backoff: 3 s, 6 s, 12 s … capped at 60 s
        let delay = min(baseReconnectDelay * pow(2.0, Double(reconnectAttempts)), maxReconnectDelay)
        reconnectAttempts += 1
        connectionStatus = .connecting

        print("🔄 WebSocket reconnect in \(Int(delay))s (attempt \(reconnectAttempts))")

        reconnectTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.openSocket(url: url)
        }
    }

    private func cancelReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }
}

// MARK: - URLSessionWebSocketDelegate
extension WebSocketService: URLSessionWebSocketDelegate {

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        DispatchQueue.main.async {
            self.reconnectAttempts = 0
            self.connectionStatus  = .connected(serverURL: self.currentURL?.absoluteString ?? "")
        }
        startHeartbeat()
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        DispatchQueue.main.async { self.handleDisconnection(error: nil) }
    }
}
