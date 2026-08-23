package dev.pam.camera

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.View
import android.widget.FrameLayout
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.core.Camera
import androidx.camera.core.CameraInfo
import androidx.camera.core.CameraSelector
import androidx.camera.core.FocusMeteringAction
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.PendingRecording
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import dev.pam.nativeapp.protocol.WireMap
import dev.pam.nativeapp.protocol.WireValue
import dev.pam.nativeapp.views.NativeViewFactory
import com.google.mlkit.vision.barcode.BarcodeScanner
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.roundToInt

class CameraViewFactory(@Suppress("UNUSED_PARAMETER") context: Context) : NativeViewFactory {
    override fun create(context: Context, emit: (ByteArray) -> Unit): View =
        CameraHost(context, emit)

    override fun update(view: View, properties: Map<String, WireValue>) {
        (view as CameraHost).update(properties)
    }

    override fun release(view: View) {
        (view as CameraHost).release()
    }
}

private class CameraHost(
    context: Context,
    private val emit: (ByteArray) -> Unit,
) : FrameLayout(context) {
    private val previewView = PreviewView(context).apply {
        implementationMode = PreviewView.ImplementationMode.PERFORMANCE
        scaleType = PreviewView.ScaleType.FILL_CENTER
    }
    private val analysisExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val captureExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val analyzing = AtomicBoolean(false)
    private val barcodeScanner: BarcodeScanner = BarcodeScanning.getClient()
    private val scaleGesture = ScaleGestureDetector(context, ZoomGesture())

    private var provider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var photo: ImageCapture? = null
    private var video: VideoCapture<Recorder>? = null
    private var analysis: ImageAnalysis? = null
    private var recording: Recording? = null
    private var recordingStartedAt = 0L
    private var active = true
    private var mode = 1L
    private var facing = 1L
    private var deviceId = ""
    private var formatId = ""
    private var fps = 30L
    private var zoom = 1.0
    private var exposure = 0.0
    private var torch = 1L
    private var photoHdr = false
    private var videoHdr = false
    private var lowLightBoost = false
    private var audio = true
    private var mirrorFront = true
    private var pinchToZoom = false
    private var stabilization = 4L
    private var maximumDurationMillis = 600_000L
    private var photoRevision = 0L
    private var recordRevision = 0L
    private var stopRevision = 0L
    private var focusRevision = 0L
    private var focusX = 0.5
    private var focusY = 0.5
    private var codeTypes = emptySet<Int>()
    private var processors = emptyList<ProcessorConfig>()
    private val processorLastFrame = HashMap<String, Long>()

    init {
        addView(previewView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        post(::bind)
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean =
        if (pinchToZoom) scaleGesture.onTouchEvent(event) else false

    fun update(values: Map<String, WireValue>) {
        val nextActive = values.flag("active", true)
        val nextMode = values.integer("mode", 1).coerceIn(1, 3)
        val nextFacing = values.integer("facing", 1).coerceIn(1, 3)
        val nextDevice = values.text("deviceId")
        val nextFormat = values.text("formatId")
        val nextFps = values.integer("fps", 30).coerceIn(1, 240)
        val needsRebind = nextActive != active || nextMode != mode || nextFacing != facing ||
            nextDevice != deviceId || nextFormat != formatId || nextFps != fps ||
            values.flag("photoHdr", false) != photoHdr || values.flag("videoHdr", false) != videoHdr ||
            values.flag("lowLightBoost", false) != lowLightBoost

        active = nextActive
        mode = nextMode
        facing = nextFacing
        deviceId = nextDevice
        formatId = nextFormat
        fps = nextFps
        photoHdr = values.flag("photoHdr", false)
        videoHdr = values.flag("videoHdr", false)
        lowLightBoost = values.flag("lowLightBoost", false)
        audio = values.flag("audio", true)
        mirrorFront = values.flag("mirrorFront", true)
        pinchToZoom = values.flag("enablePinchToZoom", false)
        stabilization = values.integer("stabilization", 4).coerceIn(1, 4)
        maximumDurationMillis = values.integer("maxDurationMillis", 600_000).coerceIn(1_000, 86_400_000)
        zoom = values.number("zoom", 1.0).coerceIn(1.0, 100.0)
        exposure = values.number("exposure", 0.0).coerceIn(-16.0, 16.0)
        torch = values.integer("torch", 1).coerceIn(1, 3)
        codeTypes = decodeIntegers(values.text("codeTypesJson")).toSet()
        processors = decodeProcessors(values.text("processorsJson"))

        if (needsRebind) bind() else applyControls()

        val nextPhoto = values.integer("photoRevision", 0)
        val nextRecord = values.integer("recordRevision", 0)
        val nextStop = values.integer("stopRevision", 0)
        val nextFocus = values.integer("focusRevision", 0)
        if (nextPhoto > photoRevision) {
            photoRevision = nextPhoto
            takePhoto()
        }
        if (nextRecord > recordRevision) {
            recordRevision = nextRecord
            startRecording()
        }
        if (nextStop > stopRevision) {
            stopRevision = nextStop
            stopRecording()
        }
        if (nextFocus > focusRevision) {
            focusRevision = nextFocus
            focusX = values.number("focusX", 0.5).coerceIn(0.0, 1.0)
            focusY = values.number("focusY", 0.5).coerceIn(0.0, 1.0)
            focus()
        }
    }

    private fun bind() {
        if (!active) {
            provider?.unbindAll()
            camera = null
            send(3)
            return
        }
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            failure(1, "Camera permission is required")
            return
        }
        val owner = context as? LifecycleOwner ?: run {
            failure(4, "Camera host has no lifecycle owner")
            return
        }
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            runCatching {
                val nextProvider = future.get()
                provider = nextProvider
                recording?.stop()
                recording = null
                nextProvider.unbindAll()

                val preview = Preview.Builder().build().also { it.surfaceProvider = previewView.surfaceProvider }
                photo = if (mode == 1L || mode == 3L) ImageCapture.Builder().build() else null
                video = if (mode == 2L || mode == 3L) {
                    val selector = QualitySelector.from(Quality.FHD, FallbackStrategy.lowerQualityOrHigherThan(Quality.FHD))
                    VideoCapture.withOutput(Recorder.Builder().setQualitySelector(selector).build())
                } else null
                analysis = if (codeTypes.isNotEmpty() || processors.isNotEmpty()) {
                    ImageAnalysis.Builder()
                        .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                        .build()
                        .also { it.setAnalyzer(analysisExecutor, ::analyze) }
                } else null

                val useCases = listOfNotNull(preview, photo, video, analysis).toTypedArray()
                camera = nextProvider.bindToLifecycle(owner, selector(nextProvider), *useCases)
                previewView.scaleX = if (facing == 2L && mirrorFront) -1f else 1f
                applyControls()
                send(1)
                send(2)
            }.onFailure { failure(4, it.message ?: "Camera configuration failed") }
        }, ContextCompat.getMainExecutor(context))
    }

    private fun selector(nextProvider: ProcessCameraProvider): CameraSelector {
        if (deviceId.isNotEmpty()) {
            val selected = nextProvider.availableCameraInfos.firstOrNull {
                runCatching { Camera2CameraInfo.from(it).cameraId == deviceId }.getOrDefault(false)
            } ?: error("Camera device is unavailable: $deviceId")
            return CameraSelector.Builder().addCameraFilter { infos -> infos.filter { it === selected } }.build()
        }
        return when (facing) {
            2L -> CameraSelector.DEFAULT_FRONT_CAMERA
            else -> CameraSelector.DEFAULT_BACK_CAMERA
        }
    }

    private fun applyControls() {
        val current = camera ?: return
        val state = current.cameraInfo.zoomState.value
        current.cameraControl.setZoomRatio(zoom.toFloat().coerceIn(state?.minZoomRatio ?: 1f, state?.maxZoomRatio ?: 1f))
        val range = current.cameraInfo.exposureState.exposureCompensationRange
        current.cameraControl.setExposureCompensationIndex(exposure.roundToInt().coerceIn(range.lower, range.upper))
        current.cameraControl.enableTorch(torch == 2L)
    }

    private fun focus() {
        val point = previewView.meteringPointFactory.createPoint(
            (previewView.width * focusX).toFloat(),
            (previewView.height * focusY).toFloat(),
        )
        camera?.cameraControl?.startFocusAndMetering(
            FocusMeteringAction.Builder(point).setAutoCancelDuration(3, TimeUnit.SECONDS).build(),
        )
    }

    private fun takePhoto() {
        val capture = photo ?: run {
            failure(5, "Photo capture is not enabled")
            return
        }
        val output = captureFile("jpg")
        capture.takePicture(
            ImageCapture.OutputFileOptions.Builder(output).build(),
            captureExecutor,
            object : ImageCapture.OnImageSavedCallback {
                override fun onImageSaved(result: ImageCapture.OutputFileResults) {
                    sendCapture(4, output, "image/jpeg", 0)
                }

                override fun onError(error: ImageCaptureException) {
                    failure(5, error.message ?: "Photo capture failed")
                }
            },
        )
    }

    private fun startRecording() {
        if (recording != null) return
        val output = video?.output ?: run {
            failure(6, "Video capture is not enabled")
            return
        }
        val file = captureFile("mp4")
        var pending: PendingRecording = output.prepareRecording(context, FileOutputOptions.Builder(file).build())
        if (audio && ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            pending = pending.withAudioEnabled()
        }
        recordingStartedAt = System.currentTimeMillis()
        recording = pending.start(ContextCompat.getMainExecutor(context)) { event ->
            when (event) {
                is VideoRecordEvent.Start -> send(5)
                is VideoRecordEvent.Finalize -> {
                    recording = null
                    if (event.hasError()) failure(6, event.cause?.message ?: "Recording failed")
                    else sendCapture(6, file, "video/mp4", System.currentTimeMillis() - recordingStartedAt)
                }
            }
        }
        postDelayed({ stopRecording() }, maximumDurationMillis)
    }

    private fun stopRecording() {
        recording?.stop()
    }

    private fun analyze(image: ImageProxy) {
        if (!analyzing.compareAndSet(false, true)) {
            image.close()
            return
        }
        var asynchronousScan = false
        try {
            val now = System.nanoTime()
            processors.forEach { config ->
                val interval = 1_000_000_000L / config.maximumFps
                val previous = processorLastFrame[config.name] ?: 0L
                if (now - previous >= interval) {
                    processorLastFrame[config.name] = now
                    runCatching {
                        CameraFrameProcessorRegistry.resolve(config.name)?.process(image, config.options)
                    }.onSuccess { result ->
                        if (result != null) send(8, processor = config.name, resultJson = result.toString())
                    }.onFailure { failure(7, it.message ?: "Frame processor failed") }
                }
            }
            if (codeTypes.isNotEmpty()) {
                val mediaImage = image.image
                if (mediaImage != null) {
                    asynchronousScan = true
                    barcodeScanner.process(InputImage.fromMediaImage(mediaImage, image.imageInfo.rotationDegrees))
                        .addOnSuccessListener(::sendCodes)
                        .addOnFailureListener { failure(7, it.message ?: "Code scanner failed") }
                        .addOnCompleteListener {
                            analyzing.set(false)
                            image.close()
                        }
                    return
                }
            }
        } catch (error: Throwable) {
            failure(7, error.message ?: "Frame analysis failed")
        } finally {
            if (!asynchronousScan) {
                analyzing.set(false)
                image.close()
            }
        }
    }

    private fun sendCodes(barcodes: List<Barcode>) {
        val rows = JSONArray()
        barcodes.take(128).forEach { barcode ->
            val type = codeType(barcode.format) ?: return@forEach
            if (type !in codeTypes) return@forEach
            val bounds = barcode.boundingBox
            rows.put(
                JSONObject()
                    .put("type", type)
                    .put("value", barcode.rawValue.orEmpty().take(4096))
                    .put("x", bounds?.left ?: 0)
                    .put("y", bounds?.top ?: 0)
                    .put("width", bounds?.width() ?: 0)
                    .put("height", bounds?.height() ?: 0),
            )
        }
        if (rows.length() > 0) send(7, codesJson = rows.toString())
    }

    private fun codeType(format: Int): Int? = when (format) {
        Barcode.FORMAT_QR_CODE -> 1
        Barcode.FORMAT_EAN_13 -> 2
        Barcode.FORMAT_EAN_8 -> 3
        Barcode.FORMAT_CODE_128 -> 4
        Barcode.FORMAT_CODE_39 -> 5
        Barcode.FORMAT_UPC_A -> 6
        Barcode.FORMAT_UPC_E -> 7
        Barcode.FORMAT_PDF417 -> 8
        Barcode.FORMAT_AZTEC -> 9
        Barcode.FORMAT_DATA_MATRIX -> 10
        else -> null
    }

    private fun captureFile(extension: String): File {
        val directory = File(context.filesDir, "pam-files/camera").apply { mkdirs() }
        return File(directory, "pam-camera-${System.currentTimeMillis()}.$extension")
    }

    private fun sendCapture(event: Long, file: File, mime: String, duration: Long) {
        send(event, path = "camera/${file.name}", mimeType = mime, durationMillis = duration)
    }

    private fun failure(code: Long, message: String) {
        send(11, errorCode = code, message = message.take(1024))
    }

    private fun send(
        event: Long,
        path: String = "",
        mimeType: String = "",
        durationMillis: Long = 0,
        errorCode: Long = 0,
        message: String = "",
        processor: String = "",
        resultJson: String = "",
        codesJson: String = "[]",
    ) = post {
        emit(
            WireMap.encode(
                mapOf(
                    "event" to WireValue.Integer(event),
                    "path" to WireValue.Text(path),
                    "mimeType" to WireValue.Text(mimeType),
                    "width" to WireValue.Integer(0),
                    "height" to WireValue.Integer(0),
                    "durationMillis" to WireValue.Integer(durationMillis),
                    "orientationDegrees" to WireValue.Integer(0),
                    "mirrored" to WireValue.Flag(facing == 2L && mirrorFront),
                    "errorCode" to WireValue.Integer(errorCode),
                    "message" to WireValue.Text(message),
                    "processor" to WireValue.Text(processor),
                    "resultJson" to WireValue.Text(resultJson.take(MAX_RESULT_BYTES)),
                    "codesJson" to WireValue.Text(codesJson.take(MAX_RESULT_BYTES)),
                ),
            ),
        )
    }

    fun release() {
        recording?.close()
        recording = null
        provider?.unbindAll()
        provider = null
        camera = null
        barcodeScanner.close()
        analysisExecutor.shutdownNow()
        captureExecutor.shutdownNow()
    }

    private inner class ZoomGesture : ScaleGestureDetector.SimpleOnScaleGestureListener() {
        override fun onScale(detector: ScaleGestureDetector): Boolean {
            val current = camera?.cameraInfo?.zoomState?.value?.zoomRatio ?: return false
            zoom = (current * detector.scaleFactor).toDouble()
            applyControls()
            return true
        }
    }

    private data class ProcessorConfig(val name: String, val options: JSONObject, val maximumFps: Long)

    private fun decodeProcessors(json: String): List<ProcessorConfig> = runCatching {
        val rows = JSONArray(json)
        buildList {
            repeat(minOf(rows.length(), 16)) { index ->
                val row = rows.optJSONObject(index) ?: return@repeat
                val name = row.optString("name")
                if (name.matches(Regex("^[a-z][a-z0-9.-]{0,63}$"))) {
                    add(ProcessorConfig(name, row.optJSONObject("options") ?: JSONObject(), row.optLong("maximumFps", 30).coerceIn(1, 240)))
                }
            }
        }
    }.getOrDefault(emptyList())

    private fun decodeIntegers(json: String): List<Int> = runCatching {
        val rows = JSONArray(json)
        List(minOf(rows.length(), 32)) { rows.optInt(it) }
    }.getOrDefault(emptyList())

    private fun Map<String, WireValue>.integer(key: String, fallback: Long): Long =
        (get(key) as? WireValue.Integer)?.value ?: fallback

    private fun Map<String, WireValue>.number(key: String, fallback: Double): Double =
        when (val value = get(key)) {
            is WireValue.Decimal -> value.value
            is WireValue.Integer -> value.value.toDouble()
            else -> fallback
        }

    private fun Map<String, WireValue>.flag(key: String, fallback: Boolean): Boolean =
        (get(key) as? WireValue.Flag)?.value ?: fallback

    private fun Map<String, WireValue>.text(key: String): String =
        (get(key) as? WireValue.Text)?.value ?: ""

    private companion object {
        const val MAX_RESULT_BYTES = 1_048_576
    }
}
