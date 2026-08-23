import AVFoundation
import Foundation
import PamNative
import UIKit

public final class CameraViewFactory: NativeViewFactory, @unchecked Sendable {
    public init() {}

    public func create(context: AnyObject?, emit: @escaping (Data) -> Void) -> UIView {
        CameraPreview(emit: emit)
    }

    public func update(view: UIView, properties: [String: WireValue]) {
        (view as? CameraPreview)?.update(properties)
    }

    public func release(view: UIView) {
        (view as? CameraPreview)?.releaseCamera()
    }
}

private final class CameraPreview: UIView, AVCapturePhotoCaptureDelegate,
    AVCaptureFileOutputRecordingDelegate, AVCaptureVideoDataOutputSampleBufferDelegate,
    AVCaptureMetadataOutputObjectsDelegate, @unchecked Sendable
{
    private let emit: (Data) -> Void
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dev.pam.camera.session", qos: .userInitiated)
    private let frameQueue = DispatchQueue(label: "dev.pam.camera.frames", qos: .userInteractive)
    private lazy var preview = AVCaptureVideoPreviewLayer(session: session)
    private let photos = AVCapturePhotoOutput()
    private let movies = AVCaptureMovieFileOutput()
    private let frames = AVCaptureVideoDataOutput()
    private let metadata = AVCaptureMetadataOutput()

    private var device: AVCaptureDevice?
    private var active = true
    private var mode: Int64 = 1
    private var facing: Int64 = 1
    private var deviceID = ""
    private var formatID = ""
    private var fps: Int64 = 30
    private var zoom = 1.0
    private var exposure = 0.0
    private var torch: Int64 = 1
    private var photoHDR = false
    private var videoHDR = false
    private var lowLightBoost = false
    private var audio = true
    private var mirrorFront = true
    private var pinchToZoom = false
    private var stabilization: Int64 = 4
    private var maxDuration: Int64 = 600_000
    private var photoRevision: Int64 = 0
    private var recordRevision: Int64 = 0
    private var stopRevision: Int64 = 0
    private var focusRevision: Int64 = 0
    private var recordingStartedAt = Date()
    private var codeTypes: Set<Int> = []
    private var processors: [ProcessorConfig] = []
    private var processorLastFrame: [String: Double] = [:]
    private var configured = false

    init(emit: @escaping (Data) -> Void) {
        self.emit = emit
        super.init(frame: .zero)
        preview.videoGravity = .resizeAspectFill
        layer.addSublayer(preview)
        addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
        authorize()
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        preview.frame = bounds
    }

    func update(_ values: [String: WireValue]) {
        let nextActive = values.flag("active", true)
        let nextMode = max(1, min(3, values.integer("mode", 1)))
        let nextFacing = max(1, min(3, values.integer("facing", 1)))
        let nextDevice = values.text("deviceId")
        let nextFormat = values.text("formatId")
        let nextFPS = max(1, min(240, values.integer("fps", 30)))
        let nextPhotoHDR = values.flag("photoHdr", false)
        let nextVideoHDR = values.flag("videoHdr", false)
        let nextLowLight = values.flag("lowLightBoost", false)
        let reconfigure = nextActive != active || nextMode != mode || nextFacing != facing ||
            nextDevice != deviceID || nextFormat != formatID || nextFPS != fps ||
            nextPhotoHDR != photoHDR || nextVideoHDR != videoHDR || nextLowLight != lowLightBoost

        active = nextActive
        mode = nextMode
        facing = nextFacing
        deviceID = nextDevice
        formatID = nextFormat
        fps = nextFPS
        photoHDR = nextPhotoHDR
        videoHDR = nextVideoHDR
        lowLightBoost = nextLowLight
        audio = values.flag("audio", true)
        mirrorFront = values.flag("mirrorFront", true)
        pinchToZoom = values.flag("enablePinchToZoom", false)
        stabilization = max(1, min(4, values.integer("stabilization", 4)))
        maxDuration = max(1_000, min(86_400_000, values.integer("maxDurationMillis", 600_000)))
        zoom = max(1, min(100, values.number("zoom", 1)))
        exposure = max(-16, min(16, values.number("exposure", 0)))
        torch = max(1, min(3, values.integer("torch", 1)))
        codeTypes = Set(decodeIntegers(values.text("codeTypesJson")))
        processors = decodeProcessors(values.text("processorsJson"))

        if reconfigure {
            queue.async { self.configure() }
        } else {
            queue.async { self.applyControls() }
        }

        let nextPhoto = values.integer("photoRevision", 0)
        let nextRecord = values.integer("recordRevision", 0)
        let nextStop = values.integer("stopRevision", 0)
        let nextFocus = values.integer("focusRevision", 0)
        if nextPhoto > photoRevision {
            photoRevision = nextPhoto
            queue.async { self.takePhoto() }
        }
        if nextRecord > recordRevision {
            recordRevision = nextRecord
            queue.async { self.startRecording() }
        }
        if nextStop > stopRevision {
            stopRevision = nextStop
            queue.async { self.stopRecording() }
        }
        if nextFocus > focusRevision {
            focusRevision = nextFocus
            let x = max(0, min(1, values.number("focusX", 0.5)))
            let y = max(0, min(1, values.number("focusY", 0.5)))
            queue.async { self.focus(x: x, y: y) }
        }
    }

    private func authorize() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            queue.async { self.configure() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { self.queue.async { self.configure() } }
                else { self.failure(1, "Camera permission was denied") }
            }
        default:
            failure(1, "Camera permission is required")
        }
    }

    private func configure() {
        guard active else {
            if session.isRunning { session.stopRunning() }
            send(event: 3)
            return
        }
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.sessionPreset = .high
        do {
            let selected = try selectDevice()
            device = selected
            try selectFormat(on: selected)
            let input = try AVCaptureDeviceInput(device: selected)
            guard session.canAddInput(input) else { throw CameraFailure.configuration }
            session.addInput(input)

            if (mode == 2 || mode == 3), audio,
               AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
               let microphone = AVCaptureDevice.default(for: .audio) {
                let audioInput = try AVCaptureDeviceInput(device: microphone)
                if session.canAddInput(audioInput) { session.addInput(audioInput) }
            }
            if mode == 1 || mode == 3 {
                guard session.canAddOutput(photos) else { throw CameraFailure.configuration }
                session.addOutput(photos)
            }
            if mode == 2 || mode == 3 {
                guard session.canAddOutput(movies) else { throw CameraFailure.configuration }
                session.addOutput(movies)
                movies.maxRecordedDuration = CMTime(value: maxDuration, timescale: 1_000)
            }
            if !processors.isEmpty {
                frames.alwaysDiscardsLateVideoFrames = true
                frames.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
                frames.setSampleBufferDelegate(self, queue: frameQueue)
                if session.canAddOutput(frames) { session.addOutput(frames) }
            }
            if !codeTypes.isEmpty, session.canAddOutput(metadata) {
                session.addOutput(metadata)
                metadata.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
                metadata.metadataObjectTypes = metadataTypes().filter { metadata.availableMetadataObjectTypes.contains($0) }
            }
            applyConnectionSettings()
            session.commitConfiguration()
            configured = true
            applyControls()
            if !session.isRunning { session.startRunning() }
            send(event: 1)
            send(event: 2)
        } catch {
            session.commitConfiguration()
            failure(4, String(describing: error))
        }
    }

    private func selectDevice() throws -> AVCaptureDevice {
        if !deviceID.isEmpty {
            let discovery = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInDualCamera, .builtInTripleCamera],
                mediaType: .video,
                position: .unspecified
            )
            if let exact = discovery.devices.first(where: { $0.uniqueID == deviceID }) { return exact }
            throw CameraFailure.unavailable
        }
        let position: AVCaptureDevice.Position = facing == 2 ? .front : .back
        guard let selected = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            throw CameraFailure.unavailable
        }
        return selected
    }

    private func selectFormat(on selected: AVCaptureDevice) throws {
        try selected.lockForConfiguration()
        defer { selected.unlockForConfiguration() }
        if !formatID.isEmpty {
            let parts = formatID.split(separator: ":")
            if let index = Int(parts.last ?? ""), selected.formats.indices.contains(index) {
                selected.activeFormat = selected.formats[index]
            } else {
                throw CameraFailure.format
            }
        }
        let supported = selected.activeFormat.videoSupportedFrameRateRanges.contains { $0.minFrameRate <= Double(fps) && Double(fps) <= $0.maxFrameRate }
        guard supported else { throw CameraFailure.format }
        selected.activeVideoMinFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        selected.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        if selected.activeFormat.isVideoHDRSupported {
            selected.automaticallyAdjustsVideoHDREnabled = false
            selected.isVideoHDREnabled = videoHDR
        }
        if selected.isLowLightBoostSupported {
            selected.automaticallyEnablesLowLightBoostWhenAvailable = lowLightBoost
        }
    }

    private func applyConnectionSettings() {
        for connection in [movies.connection(with: .video), frames.connection(with: .video)] {
            guard let connection else { continue }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = facing == 2 && mirrorFront
            }
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = nativeStabilization()
            }
        }
    }

    private func applyControls() {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = max(device.minAvailableVideoZoomFactor, min(device.maxAvailableVideoZoomFactor, zoom))
            let bias = Float(max(Double(device.minExposureTargetBias), min(Double(device.maxExposureTargetBias), exposure)))
            device.setExposureTargetBias(bias)
            if device.hasTorch {
                device.torchMode = torch == 2 ? .on : .off
            }
            device.unlockForConfiguration()
        } catch {
            failure(4, error.localizedDescription)
        }
    }

    private func focus(x: Double, y: Double) {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            let point = CGPoint(x: x, y: y)
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            failure(4, error.localizedDescription)
        }
    }

    private func takePhoto() {
        guard configured, active, session.outputs.contains(where: { $0 === photos }) else {
            failure(5, "Photo capture is not enabled")
            return
        }
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = .quality
        if photos.supportedFlashModes.contains(torch == 2 ? .on : .off) {
            settings.flashMode = torch == 2 ? .on : .off
        }
        photos.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { failure(5, error.localizedDescription); return }
        guard let data = photo.fileDataRepresentation() else { failure(5, "Photo encoding failed"); return }
        do {
            let url = try captureURL(extensionName: "jpg")
            try data.write(to: url, options: .atomic)
            sendCapture(event: 4, url: url, mime: "image/jpeg", duration: 0)
        } catch {
            failure(5, error.localizedDescription)
        }
    }

    private func startRecording() {
        guard configured, active, !movies.isRecording, session.outputs.contains(where: { $0 === movies }) else {
            failure(6, "Video capture is not enabled")
            return
        }
        do {
            let url = try captureURL(extensionName: "mov")
            recordingStartedAt = Date()
            movies.startRecording(to: url, recordingDelegate: self)
        } catch {
            failure(6, error.localizedDescription)
        }
    }

    private func stopRecording() {
        if movies.isRecording { movies.stopRecording() }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        send(event: 5)
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error { failure(6, error.localizedDescription); return }
        sendCapture(event: 6, url: outputFileURL, mime: "video/quicktime", duration: Int64(Date().timeIntervalSince(recordingStartedAt) * 1_000))
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let now = CMTimeGetSeconds(timestamp)
        processors.forEach { config in
            let previous = processorLastFrame[config.name] ?? -.infinity
            guard now - previous >= 1.0 / Double(config.maximumFPS) else { return }
            processorLastFrame[config.name] = now
            guard let processor = CameraFrameProcessorRegistry.shared.resolve(name: config.name) else { return }
            do {
                if let result = try processor.process(pixelBuffer: pixelBuffer, timestamp: timestamp, options: config.options),
                   JSONSerialization.isValidJSONObject(result) {
                    let data = try JSONSerialization.data(withJSONObject: result)
                    if data.count <= 1_048_576, let json = String(data: data, encoding: .utf8) {
                        send(event: 8, processor: config.name, resultJSON: json)
                    }
                }
            } catch {
                failure(7, error.localizedDescription)
            }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        let rows: [[String: Any]] = metadataObjects.prefix(128).compactMap { object in
            guard let code = object as? AVMetadataMachineReadableCodeObject,
                  let type = codeType(code.type), codeTypes.contains(type), let value = code.stringValue else { return nil }
            return ["type": type, "value": String(value.prefix(4096)), "x": code.bounds.origin.x, "y": code.bounds.origin.y, "width": code.bounds.width, "height": code.bounds.height]
        }
        guard !rows.isEmpty, let data = try? JSONSerialization.data(withJSONObject: rows), data.count <= 1_048_576,
              let json = String(data: data, encoding: .utf8) else { return }
        send(event: 7, codesJSON: json)
    }

    @objc private func pinch(_ gesture: UIPinchGestureRecognizer) {
        guard pinchToZoom, gesture.state == .changed, let device else { return }
        zoom = max(device.minAvailableVideoZoomFactor, min(device.maxAvailableVideoZoomFactor, device.videoZoomFactor * gesture.scale))
        gesture.scale = 1
        queue.async { self.applyControls() }
    }

    private func captureURL(extensionName: String) throws -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("pam-files/camera", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent("pam-camera-\(UUID().uuidString).\(extensionName)")
    }

    private func sendCapture(event: Int64, url: URL, mime: String, duration: Int64) {
        send(event: event, path: "camera/\(url.lastPathComponent)", mimeType: mime, duration: duration)
    }

    private func failure(_ code: Int64, _ message: String) {
        send(event: 11, errorCode: code, message: String(message.prefix(1024)))
    }

    private func send(event: Int64, path: String = "", mimeType: String = "", duration: Int64 = 0,
                      errorCode: Int64 = 0, message: String = "", processor: String = "",
                      resultJSON: String = "", codesJSON: String = "[]") {
        let values: [String: WireValue] = [
            "event": .integer(event), "path": .text(path), "mimeType": .text(mimeType),
            "width": .integer(0), "height": .integer(0), "durationMillis": .integer(duration),
            "orientationDegrees": .integer(0), "mirrored": .flag(facing == 2 && mirrorFront),
            "errorCode": .integer(errorCode), "message": .text(message), "processor": .text(processor),
            "resultJson": .text(String(resultJSON.prefix(1_048_576))), "codesJson": .text(String(codesJSON.prefix(1_048_576)))
        ]
        if let data = try? WireMap.encode(values) { DispatchQueue.main.async { self.emit(data) } }
    }

    func releaseCamera() {
        queue.async {
            if self.movies.isRecording { self.movies.stopRecording() }
            if self.session.isRunning { self.session.stopRunning() }
            self.session.inputs.forEach(self.session.removeInput)
            self.session.outputs.forEach(self.session.removeOutput)
            self.frames.setSampleBufferDelegate(nil, queue: nil)
            self.configured = false
            self.device = nil
        }
    }

    private func nativeStabilization() -> AVCaptureVideoStabilizationMode {
        switch stabilization {
        case 1: return .off
        case 2: return .standard
        case 3: return .cinematic
        default: return .auto
        }
    }

    private func metadataTypes() -> [AVMetadataObject.ObjectType] {
        codeTypes.compactMap {
            switch $0 {
            case 1: return .qr
            case 2: return .ean13
            case 3: return .ean8
            case 4: return .code128
            case 5: return .code39
            case 6: return .ean13
            case 7: return .upce
            case 8: return .pdf417
            case 9: return .aztec
            case 10: return .dataMatrix
            default: return nil
            }
        }
    }

    private func codeType(_ type: AVMetadataObject.ObjectType) -> Int? {
        switch type {
        case .qr: return 1
        case .ean13: return 2
        case .ean8: return 3
        case .code128: return 4
        case .code39: return 5
        case .upce: return 7
        case .pdf417: return 8
        case .aztec: return 9
        case .dataMatrix: return 10
        default: return nil
        }
    }

    private struct ProcessorConfig {
        let name: String
        let options: [String: Any]
        let maximumFPS: Int64
    }

    private func decodeProcessors(_ json: String) -> [ProcessorConfig] {
        guard let data = json.data(using: .utf8), data.count <= 1_048_576,
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows.prefix(16).compactMap { row in
            guard let name = row["name"] as? String,
                  name.range(of: "^[a-z][a-z0-9.-]{0,63}$", options: .regularExpression) != nil else { return nil }
            return ProcessorConfig(name: name, options: row["options"] as? [String: Any] ?? [:], maximumFPS: max(1, min(240, (row["maximumFps"] as? NSNumber)?.int64Value ?? 30)))
        }
    }

    private func decodeIntegers(_ json: String) -> [Int] {
        guard let data = json.data(using: .utf8), data.count <= 4096,
              let values = try? JSONSerialization.jsonObject(with: data) as? [Int] else { return [] }
        return Array(values.prefix(32))
    }
}

private extension Dictionary where Key == String, Value == WireValue {
    func integer(_ key: String, _ fallback: Int64) -> Int64 { if case let .integer(value)? = self[key] { return value }; return fallback }
    func number(_ key: String, _ fallback: Double) -> Double { if case let .decimal(value)? = self[key] { return value }; if case let .integer(value)? = self[key] { return Double(value) }; return fallback }
    func flag(_ key: String, _ fallback: Bool) -> Bool { if case let .flag(value)? = self[key] { return value }; return fallback }
    func text(_ key: String) -> String { if case let .text(value)? = self[key] { return value }; return "" }
}

private enum CameraFailure: Error {
    case unavailable
    case format
    case configuration
}
