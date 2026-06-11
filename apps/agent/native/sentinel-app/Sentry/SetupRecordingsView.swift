//
//  SetupRecordingsView.swift
//  Sentry
//
//  Created by 秋星桥 on 5/24/25.
//

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

struct SetupRecordingsView: View {
    @StateObject var vm = SentryConfigurationManager.shared
    @StateObject private var cameraManager = CameraManager()

    var body: some View {
        FormView(title: "Setup Recordings", leftBottom: {
            Button("Open Saved Clips", action: openSavedClips)
        }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("You can enable camera recording when Sentry is activated.")
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Toggle(isOn: $vm.cfg.sentryRecordingEnabled) {
                    Text("Enable Camera Recording")
                }
                cameraContent
                Text("Please remember to respect the privacy of others.")
                    .underline()
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { cameraManager.requestPermission() }
    }

    @ViewBuilder
    private var cameraContent: some View {
        if cameraManager.isAuthorized {
            authorizedCameraContent
        } else {
            unauthorizedCameraContent
        }
    }

    private var selectedCameraBinding: Binding<AVCaptureDevice?> {
        Binding(
            get: { cameraManager.selectedCamera },
            set: { newCamera in
                guard let newCamera else { return }
                cameraManager.switchCamera(to: newCamera)
            }
        )
    }

    private var cameraAccessStatusText: String {
        cameraManager.authorizationStatus == .denied ? "Camera Access Denied" : "Requesting Camera Access..."
    }

    private var authorizedCameraContent: some View {
        Group {
            CameraPreviewView(captureSession: cameraManager.captureSession)
                .background(.black)
                .frame(height: 150)
                .cornerRadius(8)

            if cameraManager.availableCameras.count > 1 {
                Picker("Camera", selection: selectedCameraBinding) {
                    ForEach(cameraManager.availableCameras, id: \.uniqueID) { camera in
                        Text(camera.localizedName).tag(camera as AVCaptureDevice?)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }

    private var unauthorizedCameraContent: some View {
        Rectangle()
            .foregroundStyle(.black)
            .frame(height: 150)
            .overlay {
                VStack {
                    Image(systemName: "camera.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.white)
                    Text(cameraAccessStatusText)
                        .foregroundStyle(.white)
                        .font(.caption)
                }
            }
            .cornerRadius(8)
    }

    private func openSavedClips() {
        try? FileManager.default.createDirectory(
            atPath: videoClipDir.path,
            withIntermediateDirectories: true
        )
        NSWorkspace.shared.selectFile(
            nil,
            inFileViewerRootedAtPath: videoClipDir.path
        )
    }
}

#Preview {
    SetupRecordingsView()
}
