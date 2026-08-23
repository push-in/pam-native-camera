import AVFoundation
import Foundation
import PamNative

public final class CameraModule: NativeModule, @unchecked Sendable {
    public init() {}

    public func invoke(method: String, payload: Data, completion: @escaping ModuleCompletion) {
        switch method {
        case "permission":
            completePermission(completion)
        case "requestPermission":
            AVCaptureDevice.requestAccess(for: .video) { _ in
                self.completePermission(completion)
            }
        case "devices":
            do {
                completion(.success, try WireMap.encode(["json": .text(try devices())]))
            } catch {
                completion(.failure, Data(String(describing: error).utf8))
            }
        default:
            completion(.failure, Data("Unknown camera method: \(method)".utf8))
        }
    }

    private func completePermission(_ completion: @escaping ModuleCompletion) {
        let value: Int64
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined: value = 1
        case .denied: value = 2
        case .authorized: value = 3
        case .restricted: value = 4
        @unknown default: value = 4
        }
        do {
            completion(.success, try WireMap.encode(["permission": .integer(value)]))
        } catch {
            completion(.failure, Data(String(describing: error).utf8))
        }
    }

    private func devices() throws -> String {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInDualCamera, .builtInTripleCamera],
            mediaType: .video,
            position: .unspecified
        )
        let rows: [[String: Any]] = discovery.devices.prefix(32).map { device in
            let formats: [[String: Any]] = device.formats.prefix(128).enumerated().map { index, format in
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let ranges = format.videoSupportedFrameRateRanges
                return [
                    "id": "\(device.uniqueID):\(index)",
                    "width": Int(dimensions.width),
                    "height": Int(dimensions.height),
                    "minFps": Int(ranges.map(\.minFrameRate).min() ?? 0),
                    "maxFps": Int(ranges.map(\.maxFrameRate).max() ?? 0),
                    "hdr": format.isVideoHDRSupported,
                    "photoHdr": format.isVideoHDRSupported,
                    "maxZoom": Int(device.maxAvailableVideoZoomFactor)
                ]
            }
            return [
                "id": device.uniqueID,
                "name": device.localizedName,
                "facing": facing(device.position),
                "hasFlash": device.hasFlash,
                "hasTorch": device.hasTorch,
                "minZoom": device.minAvailableVideoZoomFactor,
                "neutralZoom": device.virtualDeviceSwitchOverVideoZoomFactors.first?.doubleValue ?? 1.0,
                "maxZoom": device.maxAvailableVideoZoomFactor,
                "formats": formats
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: rows)
        guard data.count <= 1_048_576, let json = String(data: data, encoding: .utf8) else {
            throw CameraModuleError.deviceCatalogTooLarge
        }
        return json
    }

    private func facing(_ position: AVCaptureDevice.Position) -> Int {
        switch position {
        case .back: return 1
        case .front: return 2
        default: return 3
        }
    }
}

private enum CameraModuleError: Error {
    case deviceCatalogTooLarge
}
