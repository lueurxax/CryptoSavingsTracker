import Foundation
import MultipeerConnectivity
#if canImport(UIKit)
import UIKit
#endif
import Combine

final class LocalBridgeTransportCoordinator: NSObject, ObservableObject {
    enum NearbyState: Equatable {
        case idle
        case advertising
        case browsing
        case connecting(String)
        case connected(String)
        case transferring(String, Double)
        case failed(String)

        var displayTitle: String {
            switch self {
            case .idle:
                return "Idle"
            case .advertising:
                return "Advertising"
            case .browsing:
                return "Browsing"
            case let .connecting(peer):
                return "Connecting to \(peer)"
            case let .connected(peer):
                return "Connected to \(peer)"
            case let .transferring(label, progress):
                return "\(label) \(Int((progress * 100).rounded()))%"
            case let .failed(message):
                return "Failed: \(message)"
            }
        }
    }

    private enum Message: Codable {
        case bootstrapToken(String)
    }

    @Published private(set) var state: NearbyState = .idle
    @Published private(set) var discoveredPeers: [String] = []
    @Published private(set) var lastReceivedBootstrapToken: String?
    @Published private(set) var lastReceivedArtifactURL: URL?
    @Published private(set) var lastTransferSummary: String?
    @Published private(set) var transferDiagnostics: String?
    @Published private(set) var resumableOutgoingArtifactURL: URL?

    private let serviceType = "cstbridge"
    private lazy var localPeerID = MCPeerID(displayName: Self.localPeerName)
    private lazy var session: MCSession = {
        let session = MCSession(peer: localPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        return session
    }()

    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var outgoingProgressObservation: NSKeyValueObservation?
    private var incomingProgressObservation: NSKeyValueObservation?
    private var outgoingTransferResourceName: String?

    func startAdvertising() {
        stop()
        let advertiser = MCNearbyServiceAdvertiser(peer: localPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        self.advertiser = advertiser
        state = .advertising
        transferDiagnostics = "Advertising for a nearby bridge peer."
    }

    func startBrowsing() {
        stop()
        let browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        self.browser = browser
        discoveredPeers = []
        state = .browsing
        transferDiagnostics = "Browsing for a nearby bridge peer."
    }

    func stop() {
        outgoingProgressObservation = nil
        incomingProgressObservation = nil
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        browser?.stopBrowsingForPeers()
        browser = nil
        if !session.connectedPeers.isEmpty {
            session.disconnect()
        }
        discoveredPeers = []
        if case .failed = state {
            return
        }
        state = .idle
    }

    func sendBootstrapToken(_ token: String) {
        guard !session.connectedPeers.isEmpty else {
            state = .failed("No nearby peer connected.")
            transferDiagnostics = "Nearby token send requires an active foreground peer connection."
            return
        }

        do {
            let data = try JSONEncoder().encode(Message.bootstrapToken(token))
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            transferDiagnostics = "Bootstrap token sent to the connected nearby peer."
        } catch {
            state = .failed(error.localizedDescription)
            transferDiagnostics = "Nearby token send failed. Reconnect and try again."
        }
    }

    func sendArtifact(at fileURL: URL) {
        guard let peer = session.connectedPeers.first else {
            state = .failed("No nearby peer connected.")
            resumableOutgoingArtifactURL = fileURL
            outgoingTransferResourceName = fileURL.lastPathComponent
            transferDiagnostics = "Nearby transfer is staged but no connected peer is available. Reconnect and resume in the foreground."
            return
        }

        let resourceName = fileURL.lastPathComponent
        outgoingProgressObservation = nil
        resumableOutgoingArtifactURL = fileURL
        outgoingTransferResourceName = resourceName
        let progress = session.sendResource(at: fileURL, withName: resourceName, toPeer: peer) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                self.outgoingProgressObservation = nil
                if let error {
                    self.state = .failed(error.localizedDescription)
                    self.lastTransferSummary = "Nearby transfer failed for \(resourceName)."
                    self.transferDiagnostics = "Nearby transfer was interrupted. Keep both devices in the foreground, reconnect, and tap Resume Nearby Transfer."
                } else {
                    self.state = .connected(peer.displayName)
                    self.lastTransferSummary = "Nearby transfer completed for \(resourceName)."
                    self.transferDiagnostics = "Nearby transfer completed and the artifact is ready on the receiving device."
                    self.resumableOutgoingArtifactURL = nil
                    self.outgoingTransferResourceName = nil
                }
            }
        }
        guard let progress else {
            state = .connected(peer.displayName)
            lastTransferSummary = "Started nearby transfer for \(resourceName)."
            transferDiagnostics = "Nearby transfer started."
            return
        }
        observeOutgoingTransfer(progress, resourceName: resourceName, peerName: peer.displayName)
    }

    func resumeLastOutgoingTransfer() {
        guard let artifactURL = resumableOutgoingArtifactURL else {
            transferDiagnostics = "No interrupted outgoing transfer is available to resume."
            return
        }
        sendArtifact(at: artifactURL)
    }

    func consumeReceivedBootstrapToken() -> String? {
        let token = lastReceivedBootstrapToken
        lastReceivedBootstrapToken = nil
        return token
    }

    func consumeReceivedArtifactURL() -> URL? {
        let url = lastReceivedArtifactURL
        lastReceivedArtifactURL = nil
        return url
    }

    private func observeOutgoingTransfer(_ progress: Progress, resourceName: String, peerName: String) {
        state = .transferring("Sending \(resourceName) to \(peerName)", progress.fractionCompleted)
        transferDiagnostics = "Foreground nearby transfer is in progress. Keep both devices awake and connected."
        outgoingProgressObservation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            Task { @MainActor in
                self?.state = .transferring("Sending \(resourceName) to \(peerName)", progress.fractionCompleted)
            }
        }
    }

    private func observeIncomingTransfer(_ progress: Progress, resourceName: String, peerName: String) {
        state = .transferring("Receiving \(resourceName) from \(peerName)", progress.fractionCompleted)
        transferDiagnostics = "Receiving a nearby bridge artifact in the foreground."
        incomingProgressObservation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            Task { @MainActor in
                self?.state = .transferring("Receiving \(resourceName) from \(peerName)", progress.fractionCompleted)
            }
        }
    }

    private static var localPeerName: String {
#if canImport(UIKit)
        UIDevice.current.name
#else
        ProcessInfo.processInfo.hostName
#endif
    }
}

extension LocalBridgeTransportCoordinator: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        Task { @MainActor in
            invitationHandler(true, self.session)
            self.state = .connecting(peerID.displayName)
        }
    }

    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        Task { @MainActor in
            self.state = .failed(error.localizedDescription)
        }
    }
}

extension LocalBridgeTransportCoordinator: MCNearbyServiceBrowserDelegate {
    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        Task { @MainActor in
            if !self.discoveredPeers.contains(peerID.displayName) {
                self.discoveredPeers.append(peerID.displayName)
            }
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 15)
            self.state = .connecting(peerID.displayName)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.discoveredPeers.removeAll { $0 == peerID.displayName }
        }
    }

    func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error
    ) {
        Task { @MainActor in
            self.state = .failed(error.localizedDescription)
        }
    }
}

extension LocalBridgeTransportCoordinator: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .notConnected:
                if let resourceName = self.outgoingTransferResourceName {
                    self.state = .failed("Connection ended before \(resourceName) finished transferring.")
                    self.transferDiagnostics = "Nearby transfer paused. Reconnect the same peer while both devices stay in the foreground, then tap Resume Nearby Transfer."
                } else {
                    self.state = .idle
                }
            case .connecting:
                self.state = .connecting(peerID.displayName)
            case .connected:
                self.state = .connected(peerID.displayName)
                if self.resumableOutgoingArtifactURL != nil {
                    self.transferDiagnostics = "Connected to \(peerID.displayName). Resume Nearby Transfer is available."
                }
            @unknown default:
                self.state = .failed("Unknown nearby session state.")
            }
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            guard let message = try? JSONDecoder().decode(Message.self, from: data) else {
                return
            }
            switch message {
            case let .bootstrapToken(token):
                self.lastReceivedBootstrapToken = token
                self.state = .connected(peerID.displayName)
            }
        }
    }

    func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {
        Task { @MainActor in
            self.observeIncomingTransfer(progress, resourceName: resourceName, peerName: peerID.displayName)
        }
    }

    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: Error?
    ) {
        Task { @MainActor in
            self.incomingProgressObservation = nil
            if let error {
                self.state = .failed(error.localizedDescription)
                self.lastTransferSummary = "Nearby receive failed for \(resourceName)."
                self.transferDiagnostics = "Receiving the nearby artifact failed. Ask the sender to retry while both devices remain in the foreground."
                return
            }
            self.lastReceivedArtifactURL = localURL
            self.state = .connected(peerID.displayName)
            self.lastTransferSummary = "Received \(resourceName) from \(peerID.displayName)."
            self.transferDiagnostics = "Nearby artifact received. Review or import it while the authoritative CloudKit runtime remains unchanged until approval."
        }
    }
}
