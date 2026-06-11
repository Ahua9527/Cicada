import AVFoundation
import Foundation

enum CameraSessionControllerError: Error {
    case unavailableDevice
    case failedToAddOutput
}

final class CameraSessionController: NSObject {
    private typealias RecordingCompletion = (URL, Error?) -> Void

    private struct PendingRecordingStart {
        let deviceID: String?
        let outputURL: URL
        let completion: RecordingCompletion
    }

    let captureSession = AVCaptureSession()

    private let captureQueue = DispatchQueue(label: "wiki.qaq.Sentry.camera-session")
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var recordingCompletion: RecordingCompletion?
    private var pendingRecordingStart: PendingRecordingStart?
    private var isStoppingRecording = false

    func startPreview(device: AVCaptureDevice?) {
        guard let device else {
            stop()
            return
        }

        enqueueOnCaptureQueue {
            guard self.configureSession(for: device, includeMovieOutput: false) else { return }
            self.startSessionIfNeeded()
        }
    }

    func startRecording(
        deviceID: String?,
        outputURL: URL,
        completion: @escaping (URL, Error?) -> Void
    ) {
        enqueueOnCaptureQueue {
            let start = PendingRecordingStart(deviceID: deviceID, outputURL: outputURL, completion: completion)

            guard self.canStartRecordingImmediately else {
                self.pendingRecordingStart = start
                self.requestRecordingStop(clearPendingStart: false)
                return
            }

            self.startRecordingNow(start)
        }
    }

    func stop() {
        enqueueOnCaptureQueue {
            self.requestRecordingStop(clearPendingStart: true)
        }
    }

    private func configureSession(for device: AVCaptureDevice, includeMovieOutput: Bool) -> Bool {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        if captureSession.canSetSessionPreset(.medium) {
            captureSession.sessionPreset = .medium
        }

        if videoDeviceInput?.device.uniqueID != device.uniqueID {
            if let videoDeviceInput {
                captureSession.removeInput(videoDeviceInput)
                self.videoDeviceInput = nil
            }

            guard let newInput = try? AVCaptureDeviceInput(device: device),
                  captureSession.canAddInput(newInput)
            else {
                return false
            }

            captureSession.addInput(newInput)
            videoDeviceInput = newInput
        }

        if includeMovieOutput {
            guard ensureMovieFileOutput() else { return false }
        } else if let movieFileOutput {
            captureSession.removeOutput(movieFileOutput)
            self.movieFileOutput = nil
        }

        return true
    }

    private func ensureMovieFileOutput() -> Bool {
        if movieFileOutput != nil {
            return true
        }

        let movieFileOutput = AVCaptureMovieFileOutput()
        guard captureSession.canAddOutput(movieFileOutput) else {
            return false
        }

        captureSession.addOutput(movieFileOutput)
        self.movieFileOutput = movieFileOutput
        return true
    }

    private func startRecordingNow(_ start: PendingRecordingStart) {
        guard let device = Self.loadDevice(for: start.deviceID) else {
            failRecordingStart(start, error: CameraSessionControllerError.unavailableDevice)
            return
        }

        guard configureSession(for: device, includeMovieOutput: true) else {
            failRecordingStart(start, error: CameraSessionControllerError.failedToAddOutput)
            return
        }

        startSessionIfNeeded()

        guard let movieFileOutput else {
            failRecordingStart(start, error: CameraSessionControllerError.failedToAddOutput)
            return
        }

        recordingCompletion = start.completion
        movieFileOutput.startRecording(to: start.outputURL, recordingDelegate: self)
    }

    private func requestRecordingStop(clearPendingStart: Bool) {
        if clearPendingStart {
            pendingRecordingStart = nil
        }

        guard let movieFileOutput else {
            clearRecordingState()
            stopSessionIfNeeded()
            return
        }

        guard movieFileOutput.isRecording else {
            stopSessionIfIdle()
            return
        }

        guard !isStoppingRecording else { return }
        isStoppingRecording = true
        movieFileOutput.stopRecording()
    }

    private func enqueueOnCaptureQueue(_ action: @escaping () -> Void) {
        captureQueue.async(execute: action)
    }

    private func failRecordingStart(_ start: PendingRecordingStart, error: Error) {
        completeOnMain(start.completion, outputURL: start.outputURL, error: error)
    }

    private func completeOnMain(
        _ completion: @escaping (URL, Error?) -> Void,
        outputURL: URL,
        error: Error?
    ) {
        DispatchQueue.main.async {
            completion(outputURL, error)
        }
    }

    private func clearRecordingState() {
        recordingCompletion = nil
        isStoppingRecording = false
    }

    private func stopSessionIfIdle() {
        guard recordingCompletion == nil else { return }
        isStoppingRecording = false
        stopSessionIfNeeded()
    }

    private var canStartRecordingImmediately: Bool {
        !isStoppingRecording
            && recordingCompletion == nil
            && movieFileOutput?.isRecording != true
    }

    private func takePendingRecordingStart() -> PendingRecordingStart? {
        let pendingStart = pendingRecordingStart
        pendingRecordingStart = nil
        return pendingStart
    }

    private func handleRecordingFinished(outputFileURL: URL, error: Error?) {
        let completion = recordingCompletion
        clearRecordingState()

        if let pendingStart = takePendingRecordingStart() {
            startRecordingNow(pendingStart)
        } else {
            stopSessionIfNeeded()
        }

        if let completion {
            completeOnMain(completion, outputURL: outputFileURL, error: error)
        }
    }

    private func startSessionIfNeeded() {
        guard !captureSession.isRunning else { return }
        captureSession.startRunning()
    }

    private func stopSessionIfNeeded() {
        guard captureSession.isRunning else { return }
        captureSession.stopRunning()
    }

    private static func loadDevice(for deviceID: String?) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )

        return discovery.devices.first(where: { $0.uniqueID == deviceID })
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? discovery.devices.first
    }

    deinit {
        let captureSession = captureSession
        let movieFileOutput = movieFileOutput
        enqueueOnCaptureQueue {
            if movieFileOutput?.isRecording == true {
                movieFileOutput?.stopRecording()
            }
            if captureSession.isRunning {
                captureSession.stopRunning()
            }
        }
    }
}

extension CameraSessionController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(
        _: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from _: [AVCaptureConnection],
        error: Error?
    ) {
        enqueueOnCaptureQueue {
            self.handleRecordingFinished(outputFileURL: outputFileURL, error: error)
        }
    }
}
