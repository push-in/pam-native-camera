import CoreMedia
import Foundation

public protocol CameraFrameProcessor: Sendable {
    /** The pixel buffer is borrowed and cannot be retained after this call. */
    func process(pixelBuffer: CVPixelBuffer, timestamp: CMTime, options: [String: Any]) throws -> [String: Any]?
}

public final class CameraFrameProcessorRegistry: @unchecked Sendable {
    public static let shared = CameraFrameProcessorRegistry()

    private let lock = NSLock()
    private var processors: [String: any CameraFrameProcessor] = [:]

    private init() {}

    public func register(name: String, processor: any CameraFrameProcessor) throws {
        guard name.range(of: "^[a-z][a-z0-9.-]{0,63}$", options: .regularExpression) != nil else {
            throw CameraFrameProcessorError.invalidName
        }
        lock.lock()
        defer { lock.unlock() }
        guard processors[name] == nil else { throw CameraFrameProcessorError.duplicate }
        processors[name] = processor
    }

    public func unregister(name: String) {
        lock.lock()
        processors.removeValue(forKey: name)
        lock.unlock()
    }

    func resolve(name: String) -> (any CameraFrameProcessor)? {
        lock.lock()
        defer { lock.unlock() }
        return processors[name]
    }
}

public enum CameraFrameProcessorError: Error {
    case invalidName
    case duplicate
}
