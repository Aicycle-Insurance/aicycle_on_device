// Ultralytics 🚀 AGPL-3.0 License - https://ultralytics.com/license

package com.aicycle.yolo

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.graphics.RectF
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.Size
import android.view.Surface
import android.widget.FrameLayout
import androidx.camera.core.*
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

/**
 * Runs up to three YOLO models simultaneously on a single camera stream.
 * Each Predictor instance receives raw landscape Bitmaps on a separate executor so all
 * models run concurrently without serialisation.
 */
class YOLOMultiTaskAndroidView(context: Context) : FrameLayout(context) {

    companion object {
        private const val TAG = "YOLOMultiTaskAndroidView"
        private val CLASS_NAMES = listOf("Móp/bẹp", "Vỡ/nứt", "Thủng/rách", "Trầy/xước")
        /** carPart's class name for the license plate (matches the Dart gating logic). */
        private const val LICENSE_PLATE_CLASS = "Biển số xe"
        /**
         * Inset from the viewport band edge (buffer X = preview-vertical). Rejects a
         * plate clipped near the top/bottom bar boundary (only half visible) — the
         * whole plate must sit inside the frame, not just touch it. Kept small: on a
         * panoramic full-car framing the plate sits low in the frame (bumper level),
         * and a larger inset silently prevented OCR from ever running there.
         */
        private const val OCR_VIEWPORT_MARGIN = 0.05f
        /**
         * Inset on the PERPENDICULAR axis (preview-horizontal = buffer Y). The
         * viewport band only gates the buffer X axis, leaving plates flush against the
         * LEFT/RIGHT edge of the screen readable — which produced badly-framed /
         * half-plate captures. Require the plate to sit away from those edges too.
         */
        private const val OCR_EDGE_MARGIN = 0.05f
        private const val REQUEST_CODE_PERMISSIONS = 1001
        private val REQUIRED_PERMISSIONS = arrayOf(Manifest.permission.CAMERA)

        // ── Nhịp chạy model theo bậc nhiệt ───────────────────────────────────
        // Mỗi bảng có 4 cột, index theo ThermalTier.ordinal:
        //   [NORMAL, WARM, HOT, CRITICAL]
        // Giá trị là khoảng cách tối thiểu (ms) giữa 2 lần chạy; 0 = không giới
        // hạn (chạy mỗi frame khi predictor rảnh). Máy càng nóng, nhịp càng thưa
        // → GPU/NPU có thời gian nghỉ giữa các lần inference.
        //
        // Ở bậc NORMAL: classify ~6–7 fps, carPart tối đa ~10 fps khi căn toàn
        // cảnh rồi hạ về ~6–7 fps khi soi tổn thất, carDamage ~12.5 fps, OCR
        // không giới hạn.

        // Context stream (inspection phase background upload)
        private const val STREAM_INTERVAL_MS = 1000L
        private const val STREAM_JPEG_QUALITY = 70

        /**
         * carDamage — model chính, tốn nhiều nhất. Trước đây chạy MỖI FRAME
         * (~30 fps) khi máy mát; nay chặn ở ~12.5 fps ngay từ bậc NORMAL.
         *
         * 12.5 fps là đủ: luồng nghiệp vụ chỉ cần [_damageConfirmFrameCount] = 5
         * frame liên tiếp có tổn thất mới mở xác nhận → 400 ms, người dùng
         * không nhận ra khác biệt. Đổi lại GPU có khoảng nghỉ giữa các lần
         * inference thay vì chạy bão hoà.
         */
        private val DETECT_MIN_INTERVAL_MS = longArrayOf(80L, 150L, 250L, 400L)

        /** carCorner. */
        private val CLASSIFY_MIN_INTERVAL_MS = longArrayOf(150L, 250L, 350L, 500L)

        // carPart phải chạy nhanh hơn _carPartFlickerGrace (600 ms) phía Dart —
        // nếu thưa hơn thì `_seenRecently` không bao giờ đúng và luồng canh
        // khung ảnh toàn cảnh đứng hẳn. Vì vậy trần ở đây là 450 ms, kể cả bậc
        // CRITICAL.
        private val THIRD_PANORAMIC_INTERVAL_MS = longArrayOf(100L, 200L, 300L, 400L)
        private val THIRD_INSPECTION_INTERVAL_MS = longArrayOf(150L, 250L, 350L, 450L)

        // OCR phải chạy nhanh hơn _plateReadFreshDuration (1200 ms) phía Dart,
        // nếu không cờ "đọc được biển" hết hạn trước khi đủ điều kiện chụp.
        private val OCR_MIN_INTERVAL_MS = longArrayOf(0L, 0L, 400L, 700L)

    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val previewView = PreviewView(context)

    // Each predictor gets its own single-thread executor so all run in parallel.
    private val detectExecutor:   ExecutorService = Executors.newSingleThreadExecutor()
    private val classifyExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val thirdExecutor:    ExecutorService = Executors.newSingleThreadExecutor()
    private val cameraExecutor:   ExecutorService = Executors.newSingleThreadExecutor()

    private var detectPredictor:   Predictor? = null
    private var classifyPredictor: Predictor? = null
    private var thirdPredictor:    Predictor? = null
    private var thirdTaskType:     String = "detect"

    // License-plate OCR (gated by the carPart / third detector). Not a YOLO
    // predictor; runs on its own executor so it never blocks inference/camera.
    @Volatile private var ocrModel: LicensePlateOCR? = null
    private val ocrExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val ocrBusy = AtomicBoolean(false)

    // Visible viewport (preview-space vertical band, which maps to the box X axis —
    // see _filterToViewport in the Dart controller). OCR only considers plate boxes
    // fully inside this band so a readable plate is guaranteed to sit inside the
    // saved (viewport-cropped) photo. Defaults to the full frame until set.
    @Volatile private var ocrViewportTop = 0f
    @Volatile private var ocrViewportBottom = 1f

    // Phase-based gating. Defaults match the initial framing phase:
    //   panorama/framing → carDamage OFF, OCR ON
    //   inspection       → carDamage ON,  OCR OFF
    // carCorner (classify) and carPart (third) always run.
    @Volatile private var detectEnabled = false
    @Volatile private var ocrEnabled = true
    /** Stable id for the third predictor's results so consumers can tell two detect models apart. */
    private var thirdModelId:      String = "detect2"

    /** Predictor slot — bookkeeping (busy flags, FPS) keys on this, never on the task name,
     *  so two detect models never clobber each other's state. */
    private enum class Slot { DETECT, CLASSIFY, THIRD }

    // One-frame-deep back-pressure: skip if previous frame is still being processed.
    private val detectBusy   = AtomicBoolean(false)
    private val classifyBusy = AtomicBoolean(false)
    private val thirdBusy    = AtomicBoolean(false)

    // Mốc thời gian lần chạy gần nhất (chỉ truy cập trên cameraExecutor) — dùng
    // để giới hạn nhịp chạy của từng model theo *_MIN_INTERVAL_MS.
    private var lastDetectMs = 0L
    private var lastClassifyMs = 0L
    private var lastThirdMs = 0L

    /** Mốc lần OCR gần nhất — chỉ ghi sau khi giành được [ocrBusy], trên thirdExecutor. */
    @Volatile private var lastOcrMs = 0L

    // ── Hạ nhiệt ──────────────────────────────────────────────────────────────
    // Bậc nhiệt hiện tại, dùng để tra các bảng *_MIN_INTERVAL_MS. Ghi trên main
    // thread (callback của governor), đọc trên cameraExecutor/thirdExecutor.
    @Volatile private var thermalTier = ThermalTier.NORMAL

    private val thermalGovernor = ThermalGovernor(context) { tier ->
        thermalTier = tier
        emitThermalState(tier)
    }

    private var lifecycleOwner: LifecycleOwner? = null
    private var imageCaptureUseCase: ImageCapture? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var camera: Camera? = null

    @Volatile private var isStopped = false
    private var pendingLensFacing: Int? = null

    /** Fired on the main thread for every inference result from any task. */
    var onMultiTaskStream: ((Map<String, Any>) -> Unit)? = null

    // Per-task FPS (calculated from wall-clock interval between results)
    private var detectLastMs:   Long = 0
    private var classifyLastMs: Long = 0
    private var thirdLastMs:    Long = 0
    private var detectFps:   Double = 0.0
    private var classifyFps: Double = 0.0
    private var thirdFps:    Double = 0.0

    // Camera FPS
    private var camFrameCount = 0
    private var camFpsWindowStart = System.currentTimeMillis()
    private var camFps = 0.0

    // Context stream sampling (cameraExecutor only)
    @Volatile private var streamEnabled = false
    @Volatile private var streamDirPath = ""
    @Volatile private var isCapturingAnchor = false
    private var lastStreamSampleMs = 0L

    init {
        // COMPATIBLE forces a TextureView so Stack overlays stay visible inside a Flutter AndroidView.
        previewView.implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        addView(previewView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
        thermalGovernor.start()
    }

    // region Public API

    fun onLifecycleOwnerAvailable(owner: LifecycleOwner) {
        lifecycleOwner = owner
    }

    fun loadModels(
        detectPath: String,
        classifyPath: String,
        thirdModelPath: String? = null,
        thirdModelTask: String = "detect",
        thirdModelId: String = "detect2",
        ocrModelPath: String? = null,
        ocrConfidenceThreshold: Double = 0.85,
        useGpu: Boolean,
        detectConfidenceThreshold: Double,
        detectIouThreshold: Double,
        classifyConfidenceThreshold: Double,
        thirdConfidenceThreshold: Double,
        thirdIouThreshold: Double,
        lensFacing: Int,
        completion: () -> Unit
    ) {
        this.thirdTaskType = thirdModelTask
        this.thirdModelId = thirdModelId
        val totalModels = if (thirdModelPath != null) 3 else 2
        val loadedCount = AtomicInteger(0)

        // OCR is not a YOLO predictor and must not gate camera start — load it on
        // its own executor and attach when ready (frames before that skip OCR).
        if (ocrModelPath != null) {
            ocrExecutor.execute {
                ocrModel = try {
                    // Force CPU (Float32): the GPU delegate runs fp16, whose lower
                    // precision flips argmax on the CCT transformer and misreads
                    // plates (mirrors the iOS ANE issue). OCR runs gated/infrequently
                    // so CPU is fine. Matches the Python pipeline's CPU execution.
                    LicensePlateOCR(context, ocrModelPath, false, ocrConfidenceThreshold).also {
                        Log.d(TAG, "✅ OCR model loaded")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "⚠️ OCR load failed: ${e.message}")
                    null
                }
            }
        }

        fun tryDone() {
            if (loadedCount.incrementAndGet() == totalModels) {
                mainHandler.post {
                    initCamera(lensFacing)
                    completion()
                }
            }
        }

        detectExecutor.execute {
            try {
                val p = ObjectDetector(context, detectPath, emptyList(), useGpu)
                p.setConfidenceThreshold(detectConfidenceThreshold)
                p.setIouThreshold(detectIouThreshold)
                detectPredictor = p
                Log.d(TAG, "✅ detect predictor loaded")
            } catch (e: Exception) {
                Log.e(TAG, "⚠️ detect load failed: ${e.message}")
            }
            tryDone()
        }

        classifyExecutor.execute {
            try {
                val p = Classifier(context, classifyPath, emptyList(), useGpu)
                p.setConfidenceThreshold(classifyConfidenceThreshold)
                classifyPredictor = p
                Log.d(TAG, "✅ classify predictor loaded")
            } catch (e: Exception) {
                Log.e(TAG, "⚠️ classify load failed: ${e.message}")
            }
            tryDone()
        }

        if (thirdModelPath != null) {
            thirdExecutor.execute {
                try {
                    val p = createPredictor(thirdModelTask, thirdModelPath, useGpu)
                    if (p != null) {
                        p.setConfidenceThreshold(thirdConfidenceThreshold)
                        p.setIouThreshold(thirdIouThreshold)
                        thirdPredictor = p
                        Log.d(TAG, "✅ third predictor ($thirdModelTask) loaded")
                    } else {
                        Log.e(TAG, "⚠️ third predictor ($thirdModelTask) is null after load")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "⚠️ third load ($thirdModelTask) failed: ${e.message}")
                }
                tryDone()
            }
        }
    }

    private fun createPredictor(task: String, path: String, useGpu: Boolean): BasePredictor? {
        return when (task.lowercase()) {
            "classify" -> Classifier(context, path, emptyList(), useGpu)
            "segment"  -> Segmenter(context, path, emptyList(), useGpu)
            "pose"     -> PoseEstimator(context, path, emptyList(), useGpu)
            "obb"      -> ObbDetector(context, path, emptyList(), useGpu)
            else       -> ObjectDetector(context, path, emptyList(), useGpu)
        }
    }

    fun stopCamera() {
        isStopped = true
        cameraExecutor.execute { stopContextStreamInternal() }
        if (Looper.myLooper() == Looper.getMainLooper()) {
            stopCameraInternal()
        } else {
            mainHandler.post { stopCameraInternal() }
        }
    }

    private fun stopCameraInternal() {
        camera?.cameraControl?.enableTorch(false)
        cameraProvider?.unbindAll()
        cameraProvider = null
        imageCaptureUseCase = null
        camera = null
    }

    /** Release all resources: camera, executors, and predictors. Safe to call on any thread. */
    fun release() {
        isStopped = true
        onMultiTaskStream = null
        cameraExecutor.execute { stopContextStreamInternal() }
        thermalGovernor.stop()
        // Unbind camera phải chạy trên main thread (yêu cầu của CameraX).
        if (Looper.myLooper() == Looper.getMainLooper()) {
            stopCameraInternal()
        } else {
            mainHandler.post { stopCameraInternal() }
        }

        // Snapshot rồi xoá tham chiếu ngay để onFrame (đã bị chặn bởi isStopped)
        // không còn dùng tới. Việc đóng model nặng làm ở luồng nền bên dưới.
        val executors = listOf(detectExecutor, classifyExecutor, thirdExecutor, cameraExecutor, ocrExecutor)
        val predictors = listOf(detectPredictor, classifyPredictor, thirdPredictor)
        val ocr = ocrModel
        detectPredictor = null
        classifyPredictor = null
        thirdPredictor = null
        ocrModel = null

        // Đóng model/GPU delegate có thể tốn hàng trăm ms; chạy trên main thread sẽ
        // treo UI đúng lúc rời màn camera. Đẩy sang luồng nền: chờ inference đang
        // chạy kết thúc (predict không interrupt được) rồi mới close để tránh
        // dùng model sau khi đã giải phóng.
        Thread {
            executors.forEach { it.shutdownNow() }
            executors.forEach { runCatching { it.awaitTermination(2, TimeUnit.SECONDS) } }
            predictors.forEach { (it as? BasePredictor)?.close() }
            ocr?.close()
        }.apply { isDaemon = true; name = "yolo-release" }.start()
    }

    fun initCamera(lensFacing: Int) {
        if (allPermissionsGranted()) {
            startCamera(lensFacing)
        } else {
            pendingLensFacing = lensFacing
            val activity = context as? Activity ?: run {
                Log.e(TAG, "Context is not an Activity; cannot request camera permission")
                return
            }
            ActivityCompat.requestPermissions(activity, REQUIRED_PERMISSIONS, REQUEST_CODE_PERMISSIONS)
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        if (requestCode == REQUEST_CODE_PERMISSIONS) {
            val facing = pendingLensFacing ?: return
            if (allPermissionsGranted()) {
                pendingLensFacing = null
                startCamera(facing)
            } else {
                Log.w(TAG, "Camera permission denied")
            }
        }
    }

    private fun allPermissionsGranted() = REQUIRED_PERMISSIONS.all {
        ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED
    }

    /** Toggle the flash torch. Returns the requested state, or false if the device has no flash. */
    fun setTorchMode(enable: Boolean): Boolean {
        val cam = camera ?: return false
        if (!cam.cameraInfo.hasFlashUnit()) return false
        cam.cameraControl.enableTorch(enable)
        return enable
    }

    fun capturePhoto(
        crop: android.graphics.RectF? = null,
        jpegQuality: Int = 80,
        callback: (ByteArray?) -> Unit
    ) {
        val ic = imageCaptureUseCase ?: run { callback(null); return }
        // Snapshot preview size on the main thread for the aspect-fill crop mapping.
        val previewW = previewView.width
        val previewH = previewView.height
        ic.takePicture(cameraExecutor, object : ImageCapture.OnImageCapturedCallback() {
            override fun onCaptureSuccess(image: ImageProxy) {
                try {
                    val rotationDegrees = image.imageInfo.rotationDegrees
                    val plane = image.planes[0]
                    val buf = plane.buffer
                    val raw = ByteArray(buf.remaining()).also { buf.get(it) }
                    val jpeg = if (image.format == android.graphics.ImageFormat.JPEG) raw else {
                        val bmp = BitmapFactory.decodeByteArray(raw, 0, raw.size)
                        ByteArrayOutputStream().also { out ->
                            bmp?.compress(Bitmap.CompressFormat.JPEG, jpegQuality, out)
                            bmp?.recycle()
                        }.toByteArray()
                    }
                    callback(processCaptured(jpeg, rotationDegrees, crop, previewW, previewH, jpegQuality))
                } catch (e: Exception) {
                    Log.e(TAG, "capturePhoto processing failed: ${e.message}")
                    callback(null)
                } finally {
                    image.close()
                }
            }

            override fun onError(e: ImageCaptureException) {
                Log.e(TAG, "capturePhoto error: ${e.message}")
                callback(null)
            }
        })
    }

    fun capturePhotoToFile(
        path: String,
        crop: android.graphics.RectF? = null,
        jpegQuality: Int = 80,
        thumbnailPath: String? = null,
        thumbnailMaxSize: Int = 160,
        callback: (String?) -> Unit
    ) {
        capturePhoto(crop, jpegQuality) { bytes ->
            if (bytes == null) {
                callback(null)
                return@capturePhoto
            }
            try {
                val file = File(path)
                file.parentFile?.mkdirs()
                file.writeBytes(bytes)
                if (thumbnailPath != null) {
                    runCatching {
                        writeThumbnail(bytes, thumbnailPath, thumbnailMaxSize)
                    }
                }
                callback(file.absolutePath)
            } catch (e: Exception) {
                Log.e(TAG, "capturePhotoToFile failed: ${e.message}")
                callback(null)
            }
        }
    }

    private fun writeThumbnail(bytes: ByteArray, path: String, maxSize: Int) {
        val source = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return
        try {
            val longest = maxOf(source.width, source.height).coerceAtLeast(1)
            val scale = maxSize.toFloat() / longest.toFloat()
            val width = maxOf(1, (source.width * scale).toInt())
            val height = maxOf(1, (source.height * scale).toInt())
            val thumb = Bitmap.createScaledBitmap(source, width, height, true)
            try {
                val file = File(path)
                file.parentFile?.mkdirs()
                file.outputStream().use { out ->
                    thumb.compress(Bitmap.CompressFormat.JPEG, 65, out)
                }
            } finally {
                if (thumb !== source) thumb.recycle()
            }
        } finally {
            source.recycle()
        }
    }

    // endregion

    // region Camera setup

    private fun startCamera(lensFacing: Int) {
        val owner = lifecycleOwner ?: return
        val future = ProcessCameraProvider.getInstance(context)
        future.addListener({
            if (isStopped) return@addListener
            val provider = runCatching { future.get() }.getOrNull() ?: return@addListener
            cameraProvider = provider

            val selector = CameraSelector.Builder().requireLensFacing(lensFacing).build()

            val preview = Preview.Builder()
                .setTargetAspectRatio(AspectRatio.RATIO_16_9)
                .build()

            // Stream to the models at HD (1280x720) for efficient inference, while still
            // capturing FullHD (1920x1080) stills. CameraX lets each use-case request its
            // own resolution from the camera ISP. Sizes are expressed in the sensor's
            // natural (landscape) orientation.
            val hdSelector = ResolutionSelector.Builder()
                .setResolutionStrategy(
                    ResolutionStrategy(Size(1280, 720), ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER)
                )
                .build()
            val fullHdSelector = ResolutionSelector.Builder()
                .setResolutionStrategy(
                    ResolutionStrategy(Size(1920, 1080), ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER)
                )
                .build()

            val analysis = ImageAnalysis.Builder()
                .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                .setResolutionSelector(hdSelector)
                .setTargetRotation(Surface.ROTATION_0)
                .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                .build()
                .also { it.setAnalyzer(cameraExecutor) { proxy -> onFrame(proxy) } }

            val capture = ImageCapture.Builder()
                .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                .setResolutionSelector(fullHdSelector)
                .setTargetRotation(Surface.ROTATION_90)
                .build()

            provider.unbindAll()
            try {
                camera = provider.bindToLifecycle(owner, selector, preview, analysis, capture)
                imageCaptureUseCase = capture
            } catch (e: Exception) {
                Log.w(TAG, "3-use-case bind failed, retrying without ImageCapture: ${e.message}")
                imageCaptureUseCase = null
                try {
                    camera = provider.bindToLifecycle(owner, selector, preview, analysis)
                } catch (e2: Exception) {
                    Log.e(TAG, "Camera bind failed entirely: ${e2.message}")
                    camera = null
                }
            }
            preview.setSurfaceProvider(previewView.surfaceProvider)
            // Sink phía Flutter đã gắn xong ở thời điểm này — báo bậc nhiệt khởi
            // điểm (máy có thể đã nóng sẵn từ trước khi mở màn camera).
            emitThermalState(thermalTier)
        }, ContextCompat.getMainExecutor(context))
    }

    // endregion

    // region Frame processing

    private fun onFrame(imageProxy: ImageProxy) {
        if (isStopped) { imageProxy.close(); return }

        val now = System.currentTimeMillis()
        camFrameCount++
        val elapsed = now - camFpsWindowStart
        if (elapsed >= 500) {
            camFps = camFrameCount * 1000.0 / elapsed
            camFrameCount = 0
            camFpsWindowStart = now
        }

        val bitmap = ImageUtils.toBitmap(imageProxy) ?: run { imageProxy.close(); return }
        imageProxy.close()

        if (isStopped) { bitmap.recycle(); return }

        maybeSampleContextStream(bitmap, now)

        val w = bitmap.width
        val h = bitmap.height
        val camFpsNow = camFps

        // Phase 1 — claim slots ngay trên cameraExecutor (đơn luồng): áp giới hạn
        // nhịp theo model + back-pressure. Chưa chạy inference ở đây.
        // Snapshot một lần cho cả frame: bậc nhiệt có thể đổi giữa 3 lệnh claim,
        // và ba model nên cùng chạy theo một bậc để nhịp không lệch nhau.
        val tier = thermalTier.ordinal
        val runDetect = claimDetect(now, tier)
        val runClassify = claimClassify(now, tier)
        val runThird = claimThird(now, tier)

        val count = (if (runDetect) 1 else 0) +
            (if (runClassify) 1 else 0) +
            (if (runThird) 1 else 0)
        if (count == 0) { bitmap.recycle(); return }

        // Phase 2 — dùng CHUNG một bitmap (predictor chỉ đọc), giải phóng đúng một
        // lần khi predictor cuối cùng xong. Bỏ hẳn 3 bản copy/ frame trước đây.
        val refCount = AtomicInteger(count)
        val release = Runnable { if (refCount.decrementAndGet() == 0) bitmap.recycle() }

        if (runDetect) {
            launchPredict(detectExecutor, detectPredictor!!, detectBusy, Slot.DETECT, bitmap, w, h, camFpsNow, release)
        }
        if (runClassify) {
            launchPredict(classifyExecutor, classifyPredictor!!, classifyBusy, Slot.CLASSIFY, bitmap, w, h, camFpsNow, release)
        }
        if (runThird) {
            launchPredict(thirdExecutor, thirdPredictor!!, thirdBusy, Slot.THIRD, bitmap, w, h, camFpsNow, release)
        }
    }

    /**
     * carDamage: chạy mỗi frame khi rảnh — trừ pha panorama (input bị chặn) và
     * trừ khi máy đã nóng (bậc nhiệt > NORMAL áp thêm nhịp tối thiểu).
     */
    private fun claimDetect(now: Long, tier: Int): Boolean {
        if (detectPredictor == null || !detectEnabled) return false
        val minInterval = DETECT_MIN_INTERVAL_MS[tier]
        if (minInterval > 0 && now - lastDetectMs < minInterval) return false
        if (!detectBusy.compareAndSet(false, true)) return false
        lastDetectMs = now
        return true
    }

    private fun claimClassify(now: Long, tier: Int): Boolean {
        if (classifyPredictor == null) return false
        if (now - lastClassifyMs < CLASSIFY_MIN_INTERVAL_MS[tier]) return false
        if (!classifyBusy.compareAndSet(false, true)) return false
        lastClassifyMs = now
        return true
    }

    private fun claimThird(now: Long, tier: Int): Boolean {
        if (thirdPredictor == null) return false
        val minInterval = if (ocrEnabled) {
            THIRD_PANORAMIC_INTERVAL_MS[tier]
        } else {
            THIRD_INSPECTION_INTERVAL_MS[tier]
        }
        if (now - lastThirdMs < minInterval) return false
        if (!thirdBusy.compareAndSet(false, true)) return false
        lastThirdMs = now
        return true
    }

    private fun launchPredict(
        executor: ExecutorService,
        predictor: Predictor,
        busy: AtomicBoolean,
        slot: Slot,
        bitmap: Bitmap,
        w: Int,
        h: Int,
        camFpsNow: Double,
        release: Runnable,
    ) {
        executor.execute {
            try {
                val result = predictor.predict(bitmap, w, h, rotateForCamera = false, isLandscape = true)
                val data = buildTaskData(result, slot, camFpsNow)
                mainHandler.post { onMultiTaskStream?.invoke(data) }
                // carPart frame → try to OCR the license plate (gated, off-thread).
                // Done before `release` so the shared bitmap is still alive to crop.
                if (slot == Slot.THIRD) maybeRunOcr(result, bitmap)
            } catch (e: Exception) {
                Log.e(TAG, "$slot predict error: ${e.message}")
            } finally {
                busy.set(false)
                release.run()
            }
        }
    }

    /**
     * If carPart found a license-plate box and OCR is idle, crop that region from
     * the (still-alive) shared bitmap and recognize it on the OCR executor. Emits a
     * separate `type == "ocr"` stream event with `readable` used as the framing
     * signal (a readable plate ⇒ this frame is a good panoramic shot).
     */
    private fun maybeRunOcr(result: YOLOResult, bitmap: Bitmap) {
        val ocr = ocrModel ?: return
        if (!ocrEnabled) return // gated off during inspection
        if (!ocrBusy.compareAndSet(false, true)) return

        // Nhịp tối thiểu theo bậc nhiệt — kiểm tra SAU khi đã giành được cờ bận
        // để chỉ một luồng đọc/ghi lastOcrMs tại một thời điểm.
        val now = System.currentTimeMillis()
        val ocrMinInterval = OCR_MIN_INTERVAL_MS[thermalTier.ordinal]
        if (ocrMinInterval > 0 && now - lastOcrMs < ocrMinInterval) { ocrBusy.set(false); return }

        // Only the highest-confidence plate box that sits FULLY inside the exact
        // aspect-fill crop rect used by capturePhoto. Comparing directly with
        // ocrViewportTop/bottom is not enough because capturePhoto applies
        // aspect-fill offsets before cropping.
        val cropRect = ocrCropRectInFrame(result)
        val loX = cropRect.left + OCR_VIEWPORT_MARGIN
        val hiX = cropRect.right - OCR_VIEWPORT_MARGIN
        val loY = cropRect.top + OCR_EDGE_MARGIN
        val hiY = cropRect.bottom - OCR_EDGE_MARGIN
        if (loX >= hiX || loY >= hiY) { ocrBusy.set(false); return }
        val box = result.boxes
            .filter {
                it.cls == LICENSE_PLATE_CLASS &&
                    it.xywhn.left >= loX && it.xywhn.right <= hiX &&
                    it.xywhn.top >= loY && it.xywhn.bottom <= hiY
            }
            .maxByOrNull { it.conf }
        if (box == null) { ocrBusy.set(false); return }

        val bw = bitmap.width
        val bh = bitmap.height
        val left = (box.xywhn.left.coerceIn(0f, 1f) * bw).toInt()
        val top = (box.xywhn.top.coerceIn(0f, 1f) * bh).toInt()
        val right = (box.xywhn.right.coerceIn(0f, 1f) * bw).toInt()
        val bottom = (box.xywhn.bottom.coerceIn(0f, 1f) * bh).toInt()
        val cw = right - left
        val ch = bottom - top
        if (cw < 1 || ch < 1) { ocrBusy.set(false); return }

        // Copy the plate region into an independent bitmap so it survives the shared
        // bitmap being recycled once all predictors finish this frame.
        val crop = try {
            Bitmap.createBitmap(bitmap, left, top, cw, ch)
        } catch (e: Exception) {
            ocrBusy.set(false)
            return
        }

        lastOcrMs = now
        ocrExecutor.execute {
            try {
                val read = ocr.read(crop)
                val event = mapOf(
                    "type" to "ocr",
                    "modelId" to "ocr",
                    "plate" to (read?.first ?: ""),
                    "score" to (read?.second ?: 0.0),
                    "readable" to (read != null),
                )
                mainHandler.post { onMultiTaskStream?.invoke(event) }
            } finally {
                crop.recycle()
                ocrBusy.set(false)
            }
        }
    }

    private fun ocrCropRectInFrame(result: YOLOResult): RectF {
        val wp = result.origShape.width.toFloat()
        val hp = result.origShape.height.toFloat()
        val wv = previewView.width.toFloat()
        val hv = previewView.height.toFloat()
        if (wp <= 0f || hp <= 0f || wv <= 0f || hv <= 0f) {
            return RectF(0f, 0f, 1f, 1f)
        }

        val left: Float
        val top: Float
        val right: Float
        val bottom: Float
        if ((wp >= hp) != (wv >= hv)) {
            // Same mapping as cropToViewport(): preview vertical band maps to
            // frame/photo horizontal coordinates after the 90° transpose.
            val s = maxOf(wv / hp, hv / wp)
            val offU = (hp * s - wv) / 2f
            val offV = (wp * s - hv) / 2f
            val u0 = offU / s
            val u1 = (wv + offU) / s
            val v0 = (ocrViewportTop * hv + offV) / s
            val v1 = (ocrViewportBottom * hv + offV) / s
            left = v0
            right = v1
            top = hp - u1
            bottom = hp - u0
        } else {
            val s = maxOf(wv / wp, hv / hp)
            val offX = (wp * s - wv) / 2f
            val offY = (hp * s - hv) / 2f
            left = offX / s
            right = (wv + offX) / s
            top = (ocrViewportTop * hv + offY) / s
            bottom = (ocrViewportBottom * hv + offY) / s
        }

        val l = (left / wp).coerceIn(0f, 1f)
        val r = (right / wp).coerceIn(0f, 1f)
        val t = (top / hp).coerceIn(0f, 1f)
        val b = (bottom / hp).coerceIn(0f, 1f)
        return RectF(minOf(l, r), minOf(t, b), maxOf(l, r), maxOf(t, b))
    }

    /** Updates the visible viewport used to gate OCR (preview-space vertical band). */
    fun setOcrViewport(top: Float, bottom: Float) {
        ocrViewportTop = top
        ocrViewportBottom = bottom
    }

    /**
     * Phase-based gating: inspection runs carDamage and stops OCR; framing/panorama
     * runs OCR and stops carDamage. carCorner/carPart always run.
     */
    fun setInspectionActive(active: Boolean) {
        detectEnabled = active
        ocrEnabled = !active
    }

    fun startContextStream(dirPath: String) {
        cameraExecutor.execute {
            streamDirPath = dirPath
            streamEnabled = true
            lastStreamSampleMs = 0L
        }
    }

    fun stopContextStream() {
        cameraExecutor.execute { stopContextStreamInternal() }
    }

    fun setCapturingAnchor(active: Boolean) {
        isCapturingAnchor = active
    }

    private fun stopContextStreamInternal() {
        streamEnabled = false
        streamDirPath = ""
        lastStreamSampleMs = 0L
        isCapturingAnchor = false
    }

    private fun maybeSampleContextStream(bitmap: Bitmap, now: Long) {
        if (!streamEnabled || isCapturingAnchor) return
        if (now - lastStreamSampleMs < STREAM_INTERVAL_MS) return
        val dir = streamDirPath
        if (dir.isEmpty()) return
        lastStreamSampleMs = now

        val jpeg = bitmapToJpeg(bitmap, STREAM_JPEG_QUALITY) ?: return
        val path = "$dir/stream_$now.jpg"
        try {
            val file = File(path)
            file.parentFile?.mkdirs()
            file.writeBytes(jpeg)
            val payload = mapOf("type" to "streamFrame", "filePath" to file.absolutePath)
            mainHandler.post { onMultiTaskStream?.invoke(payload) }
        } catch (e: Exception) {
            Log.e(TAG, "context stream sample failed: ${e.message}")
        }
    }

    private fun bitmapToJpeg(bitmap: Bitmap, quality: Int): ByteArray? {
        return try {
            ByteArrayOutputStream().also { out ->
                bitmap.compress(Bitmap.CompressFormat.JPEG, quality, out)
            }.toByteArray()
        } catch (e: Exception) {
            Log.e(TAG, "bitmapToJpeg failed: ${e.message}")
            null
        }
    }

    // endregion

    // region Stream data builder

    /**
     * Báo bậc nhiệt hiện tại lên Dart (`type == "thermal"`). Bắn khi bậc đổi và
     * một lần lúc camera khởi động, để host biết SDK đang tự hạ nhịp.
     */
    private fun emitThermalState(tier: ThermalTier) {
        val event = mapOf(
            "type" to "thermal",
            "modelId" to "thermal",
            "level" to tier.ordinal,
            "state" to tier.label,
            "throttled" to (tier != ThermalTier.NORMAL),
        )
        mainHandler.post { onMultiTaskStream?.invoke(event) }
    }

    private fun buildTaskData(result: YOLOResult, slot: Slot, camFpsNow: Double): Map<String, Any> {
        val now = System.currentTimeMillis()
        val fps: Double
        val task: String
        val modelId: String
        when (slot) {
            Slot.DETECT -> {
                if (detectLastMs > 0) { val dt = now - detectLastMs; if (dt > 0) detectFps = 1000.0 / dt }
                detectLastMs = now; fps = detectFps
                task = "detect"; modelId = "detect"
            }
            Slot.CLASSIFY -> {
                if (classifyLastMs > 0) { val dt = now - classifyLastMs; if (dt > 0) classifyFps = 1000.0 / dt }
                classifyLastMs = now; fps = classifyFps
                task = "classify"; modelId = "classify"
            }
            Slot.THIRD -> {
                if (thirdLastMs > 0) { val dt = now - thirdLastMs; if (dt > 0) thirdFps = 1000.0 / dt }
                thirdLastMs = now; fps = thirdFps
                task = thirdTaskType; modelId = thirdModelId
            }
        }

        val base = mutableMapOf<String, Any>(
            "type" to task,
            "modelId" to modelId,
            "fps" to fps,
            "cameraFps" to camFpsNow,
            "processingTimeMs" to result.speed
        )

        when (task) {
            "classify" -> {
                val classMap = mutableMapOf<String, Any>(
                    "top1" to (result.probs?.top1Label ?: ""),
                    "top1Confidence" to (result.probs?.top1Conf?.toDouble() ?: 0.0)
                )
                result.probs?.let { probs ->
                    classMap["top5"] = (0 until minOf(probs.top5Labels.size, probs.top5Confs.size)).map { i ->
                        mapOf("name" to probs.top5Labels[i], "confidence" to probs.top5Confs[i].toDouble())
                    }
                }
                base["classification"] = classMap
            }
            else -> {
                // detect, segment, pose, obb — all have boxes.
                // The custom Vietnamese damage labels only apply to the primary detect model; any
                // other detect model reports its own class names via box.cls.
                val useCustomNames = modelId == "detect"
                val detections: List<Map<String, Any>> = result.boxes.take(50).map { box ->
                    val name = if (useCustomNames && box.index < CLASS_NAMES.size) CLASS_NAMES[box.index] else box.cls
                    mapOf(
                        "className" to name,
                        "confidence" to box.conf.toDouble(),
                        "normalizedBox" to mapOf(
                            "left"   to box.xywhn.left.toDouble(),
                            "top"    to box.xywhn.top.toDouble(),
                            "right"  to box.xywhn.right.toDouble(),
                            "bottom" to box.xywhn.bottom.toDouble()
                        )
                    )
                }
                base["detections"] = detections
            }
        }

        return base
    }

    // endregion

    // region Photo normalization

    /** Rotate JPEG bytes so pixel data is upright. Flutter's Image.memory() ignores EXIF. */
    /// Bakes the capture rotation upright and, when [crop] is given, crops the
    /// still to the visible viewport (normalized [0,1] rect in preview space)
    /// under aspect-fill — so the saved photo matches what the user saw.
    private fun processCaptured(
        bytes: ByteArray,
        rotationDegrees: Int,
        crop: android.graphics.RectF?,
        previewW: Int,
        previewH: Int,
        jpegQuality: Int,
    ): ByteArray {
        if (rotationDegrees == 0 && crop == null) return bytes
        var bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return bytes
        if (rotationDegrees != 0) {
            val matrix = Matrix().apply { postRotate(rotationDegrees.toFloat()) }
            val rotated = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, matrix, true)
            if (rotated !== bmp) { bmp.recycle(); bmp = rotated }
        }
        if (crop != null && previewW > 0 && previewH > 0) {
            val cropped = cropToViewport(bmp, crop, previewW, previewH)
            if (cropped !== bmp) { bmp.recycle(); bmp = cropped }
        }
        return ByteArrayOutputStream().also { out ->
            bmp.compress(Bitmap.CompressFormat.JPEG, jpegQuality, out)
            bmp.recycle()
        }.toByteArray()
    }

    private fun cropToViewport(
        bmp: Bitmap,
        crop: android.graphics.RectF,
        previewW: Int,
        previewH: Int,
    ): Bitmap {
        val wp = bmp.width.toFloat()
        val hp = bmp.height.toFloat()
        val wv = previewW.toFloat()
        val hv = previewH.toFloat()

        val left: Float; val top: Float; val right: Float; val bottom: Float
        if ((wp >= hp) != (wv >= hv)) {
            // Preview is portrait but the still is landscape (ImageCapture targets
            // ROTATION_90 = the preview rotated 90° clockwise). The preview's
            // vertical axis (top/bottom bars) maps to the photo's horizontal axis,
            // so the crop must be transposed.
            val s = maxOf(wv / hp, hv / wp)
            val offU = (hp * s - wv) / 2f  // preview-width overflow  → photo height
            val offV = (wp * s - hv) / 2f  // preview-height overflow → photo width
            val u0 = (crop.left * wv + offU) / s
            val u1 = (crop.right * wv + offU) / s
            val v0 = (crop.top * hv + offV) / s
            val v1 = (crop.bottom * hv + offV) / s
            left = v0
            right = v1
            top = hp - u1
            bottom = hp - u0
        } else {
            val s = maxOf(wv / wp, hv / hp)
            val offX = (wp * s - wv) / 2f
            val offY = (hp * s - hv) / 2f
            left = (crop.left * wv + offX) / s
            top = (crop.top * hv + offY) / s
            right = (crop.right * wv + offX) / s
            bottom = (crop.bottom * hv + offY) / s
        }

        val x = left.coerceIn(0f, wp).toInt()
        val y = top.coerceIn(0f, hp).toInt()
        val w = (right.coerceIn(0f, wp).toInt() - x).coerceIn(1, bmp.width - x)
        val h = (bottom.coerceIn(0f, hp).toInt() - y).coerceIn(1, bmp.height - y)
        return Bitmap.createBitmap(bmp, x, y, w, h)
    }

    // endregion

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        release()
    }
}
