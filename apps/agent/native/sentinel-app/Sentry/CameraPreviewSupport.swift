import AppKit
import AVFoundation
import SwiftUI

@MainActor
final class CameraManager: NSObject, ObservableObject {
    private let vm = SentryConfigurationManager.shared
    private let cameraController = CameraSessionController()

    @Published var isAuthorized = false
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var selectedCamera: AVCaptureDevice?

    var captureSession: AVCaptureSession {
        cameraController.captureSession
    }

    override init() {
        super.init()
        refreshAuthorizationState()
        discoverCameras()
    }

    private func discoverCameras() {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )
        availableCameras = discoverySession.devices
        selectedCamera = preferredCamera(from: availableCameras)
    }

    private func refreshAuthorizationState() {
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        isAuthorized = authorizationStatus == .authorized

        if isAuthorized { setupCamera() }
    }

    func requestPermission() {
        guard authorizationStatus == .notDetermined else {
            return
        }

        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.applyAuthorization(granted: granted)
            }
        }
    }

    private func setupCamera() {
        guard let videoDevice = selectedCamera else { return }
        cameraController.startPreview(device: videoDevice)
    }

    func switchCamera(to device: AVCaptureDevice) {
        selectedCamera = device
        vm.cfg.sentryRecordingDevice = device.uniqueID
        guard isAuthorized else { return }
        setupCamera()
    }

    private func preferredCamera(from cameras: [AVCaptureDevice]) -> AVCaptureDevice? {
        let persistedID = vm.cfg.sentryRecordingDevice
        if let persisted = cameras.first(where: { $0.uniqueID == persistedID }) {
            return persisted
        }
        if let frontCamera = cameras.first(where: { $0.position == .front }) {
            return frontCamera
        }
        return cameras.first
    }

    private func applyAuthorization(granted: Bool) {
        authorizationStatus = granted ? .authorized : .denied
        isAuthorized = granted
        if granted { setupCamera() }
    }

    deinit {
        cameraController.stop()
    }
}

struct CameraPreviewView: NSViewRepresentable {
    let captureSession: AVCaptureSession

    func makeNSView(context _: Context) -> NSView {
        let view = NSView()

        let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill

        view.layer = previewLayer
        view.wantsLayer = true

        return view
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        if let layer = nsView.layer as? AVCaptureVideoPreviewLayer {
            layer.session = captureSession
        }
    }
}
