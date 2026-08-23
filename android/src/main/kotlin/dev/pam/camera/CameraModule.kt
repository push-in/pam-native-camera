package dev.pam.camera

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import dev.pam.nativeapp.modules.ModuleCompletion
import dev.pam.nativeapp.modules.ModuleResultStatus
import dev.pam.nativeapp.modules.NativeModule
import dev.pam.nativeapp.protocol.WireMap
import dev.pam.nativeapp.protocol.WireValue
import org.json.JSONArray
import org.json.JSONObject

class CameraModule(private val context: Context) : NativeModule {
    override fun invoke(method: String, payload: ByteArray, completion: ModuleCompletion) {
        when (method) {
            "permission" -> completion.success(permissionPayload())
            "requestPermission" -> requestPermission(WireMap.decode(payload), completion)
            "devices" -> devices(completion)
            else -> completion.failure(IllegalArgumentException("Unknown camera method: $method"))
        }
    }

    private fun requestPermission(values: Map<String, WireValue>, completion: ModuleCompletion) {
        if (permission() == 3L) {
            completion.success(permissionPayload())
            return
        }
        val activity = context as? Activity
        if (activity == null) {
            completion.failure(IllegalStateException("Camera permission requests require an active Activity"))
            return
        }
        val microphone = (values["microphone"] as? WireValue.Flag)?.value ?: false
        val permissions = buildList {
            add(Manifest.permission.CAMERA)
            if (microphone) add(Manifest.permission.RECORD_AUDIO)
        }.toTypedArray()
        ActivityCompat.requestPermissions(activity, permissions, PERMISSION_REQUEST)
        completion.success(mapOf("permission" to WireValue.Integer(permission())))
    }

    private fun devices(completion: ModuleCompletion) {
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            runCatching {
                val rows = JSONArray()
                future.get().availableCameraInfos.take(MAX_DEVICES).forEach { info ->
                    val camera2 = Camera2CameraInfo.from(info)
                    val facing = when (info.lensFacing) {
                        0 -> 2
                        1 -> 1
                        else -> 3
                    }
                    rows.put(
                        JSONObject()
                            .put("id", camera2.cameraId)
                            .put("name", "Camera ${camera2.cameraId}")
                            .put("facing", facing)
                            .put("hasFlash", info.hasFlashUnit())
                            .put("hasTorch", info.hasFlashUnit())
                            .put("minZoom", info.zoomState.value?.minZoomRatio ?: 1f)
                            .put("neutralZoom", 1f)
                            .put("maxZoom", info.zoomState.value?.maxZoomRatio ?: 1f)
                            .put("formats", JSONArray())
                    )
                }
                completion.success(mapOf("json" to WireValue.Text(rows.toString())))
            }.onFailure(completion::failure)
        }, ContextCompat.getMainExecutor(context))
    }

    private fun permissionPayload(): Map<String, WireValue> =
        mapOf("permission" to WireValue.Integer(permission()))

    private fun permission(): Long = when {
        ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED -> 3
        context is Activity && ActivityCompat.shouldShowRequestPermissionRationale(context, Manifest.permission.CAMERA) -> 2
        else -> 1
    }

    private fun ModuleCompletion.success(values: Map<String, WireValue>) =
        complete(ModuleResultStatus.SUCCESS, WireMap.encode(values))

    private fun ModuleCompletion.failure(error: Throwable) =
        complete(ModuleResultStatus.FAILURE, (error.message ?: "Camera failure").toByteArray())

    private companion object {
        const val PERMISSION_REQUEST = 0x5041
        const val MAX_DEVICES = 32
    }
}
