#if os(iOS)
import AVFoundation
import SwiftUI
import UIKit

struct LocalBridgeQRScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void
    let onFailure: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCodeScanned: onCodeScanned, onFailure: onFailure)
    }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onCodeScanned: (String) -> Void
        private let onFailure: (String) -> Void
        private var hasScanned = false

        init(onCodeScanned: @escaping (String) -> Void, onFailure: @escaping (String) -> Void) {
            self.onCodeScanned = onCodeScanned
            self.onFailure = onFailure
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !hasScanned,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue else {
                return
            }

            hasScanned = true
            onCodeScanned(value)
        }

        func fail(_ message: String) {
            onFailure(message)
        }
    }
}

final class ScannerViewController: UIViewController {
    var coordinator: LocalBridgeQRScannerView.Coordinator?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureCamera()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            startCapture()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.startCapture()
                    } else {
                        self?.coordinator?.fail("Camera permission denied. Manual pairing remains available.")
                    }
                }
            }
        case .denied, .restricted:
            coordinator?.fail("Camera permission denied or unavailable. Manual pairing remains available.")
        @unknown default:
            coordinator?.fail("Camera is unavailable on this device. Manual pairing remains available.")
        }
    }

    private func startCapture() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            coordinator?.fail("No camera is available. Manual pairing remains available.")
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                coordinator?.fail("Camera input could not be configured.")
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                coordinator?.fail("QR metadata output could not be configured.")
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(coordinator, queue: .main)
            output.metadataObjectTypes = [.qr]

            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.bounds
            view.layer.addSublayer(previewLayer)
            self.previewLayer = previewLayer

            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        } catch {
            coordinator?.fail("Camera setup failed: \(error.localizedDescription)")
        }
    }

    deinit {
        session.stopRunning()
    }
}
#endif
