package dev.pam.camera

import androidx.camera.core.ImageProxy
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap

/**
 * A synchronous zero-copy frame processor. Implementations must not retain
 * [image] after this method returns and must never close it.
 */
fun interface CameraFrameProcessor {
    fun process(image: ImageProxy, options: JSONObject): JSONObject?
}

object CameraFrameProcessorRegistry {
    private val processors = ConcurrentHashMap<String, CameraFrameProcessor>()

    fun register(name: String, processor: CameraFrameProcessor) {
        require(name.matches(Regex("^[a-z][a-z0-9.-]{0,63}$"))) { "Invalid frame processor name" }
        check(processors.putIfAbsent(name, processor) == null) { "Frame processor already registered: $name" }
    }

    fun unregister(name: String) {
        processors.remove(name)
    }

    internal fun resolve(name: String): CameraFrameProcessor? = processors[name]
}
