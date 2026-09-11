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
        private const val REQUEST_CODE_PERMISSIONS = 1001
        private val REQUIRED_PERMISSIONS = arrayOf(Manifest.permission.CAMERA)

        // ── Nhịp chạy model theo bậc nhiệt ───────────────────────────────────
        // Mỗi bảng có 4 cột, index theo ThermalTier.ordinal:
        //   [NORMAL, WARM, HOT, CRITICAL]
        // Giá trị là khoảng cách tối thiểu (ms) giữa 2 lần chạy.
        // Máy càng nóng, nhịp càng thưa → GPU/NPU có thời gian nghỉ giữa các lần inference.
        // Ở bậc NORMAL: classify ~3.0 fps (330ms), carPart 5.0 fps (200ms) khi căn toàn
        // cảnh rồi hạ về ~3.3 fps (300ms) khi soi tổn thất, carDamage ~6.7 fps (150ms).

        // Context stream (inspection phase background upload)
        private const val STREAM_INTERVAL_MS = 2000L
        private const val STREAM_JPEG_QUALITY = 70

        /**
         * carDamage — model chính, tốn nhiều nhất.
         * Giới hạn nhịp chạy theo bậc nhiệt để GPU/NPU nghỉ ngơi, tránh quá nhiệt.
         */
        private val DETECT_MIN_INTERVAL_MS = longArrayOf(150L, 200L, 300L, 500L)

        /** carCorner. */
        private val CLASSIFY_MIN_INTERVAL_MS = longArrayOf(330L, 400L, 500L, 650L)

        // carPart phải chạy nhanh hơn _carPartFlickerGrace (600 ms) phía Dart —
        // nếu thưa hơn thì `_seenRecently` không bao giờ đúng và luồng canh
        // khung ảnh toàn cảnh đứng hẳn.
        private val THIRD_PANORAMIC_INTERVAL_MS = longArrayOf(200L, 250L, 350L, 450L)
        private val THIRD_INSPECTION_INTERVAL_MS = longArrayOf(300L, 400L, 500L, 650L)

    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val previewView = PreviewView(context)

    // Single shared inference executor so all YOLO models execute sequentially,
    // eliminating resource contention and thermal/current spikes on GPU/NPU.
    private val inferenceExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val cameraExecutor:    ExecutorService = Executors.newSingleThreadExecutor()

    // Chuẩn hoá ảnh still (decode → xoay → crop → encode → ghi file) tốn hàng
    // trăm ms. Phải nằm ngoài [cameraExecutor]: đó là analyzer của ImageAnalysis,
    // chạy ở đây thì vừa treo luồng frame vừa phải chờ frame đang xử lý xong mới
    // tới lượt — đúng lúc user đang chờ ảnh "dừng hình" hiện ra.
    private val captureExecutor:  ExecutorService = Executors.newSingleThreadExecutor()

    private var detectPredictor:   Predictor? = null
    private var classifyPredictor: Predictor? = null
    private var thirdPredictor:    Predictor? = null
    private var thirdTaskType:     String = "detect"

    // Phase-based gating. Defaults match the initial framing phase:
    //   panorama/framing → carDamage OFF, isPanoramicPhase ON
    //   inspection       → carDamage ON,  isPanoramicPhase OFF
    // carCorner (classify) and carPart (third) always run.
    @Volatile private var detectEnabled = false
    @Volatile private var isPanoramicPhase = true
    /** Stable id for the third predictor's results so consumers can tell two detect models apart. */
    private var thirdModelId:      String = "detect2"

    /** Predictor slot — bookkeeping (busy flags, FPS) keys on this, never on the task name,
     *  so two detect models never clobber each other's state. */
    private enum class Slot { DETECT, CLASSIFY, THIRD }

    // One-frame-deep back-pressure: skip frame if previous inference is still running.
    private val isInferring = AtomicBoolean(false)

    // Round-robin scheduling ring: 2 DETECT : 1 THIRD : 1 CLASSIFY.
    // In panoramic phase (detectEnabled = false), DETECT candidates are skipped
    // and execution naturally interleaves between THIRD and CLASSIFY.
    private val rrCandidates = arrayOf(Slot.DETECT, Slot.THIRD, Slot.DETECT, Slot.CLASSIFY)
    private var rrCursor = 0

    // Mốc thời gian lần chạy gần nhất (chỉ truy cập trên cameraExecutor) — dùng
    // để giới hạn nhịp chạy của từng model theo *_MIN_INTERVAL_MS.
    private var lastDetectMs = 0L
    private var lastClassifyMs = 0L
    private var lastThirdMs = 0L

    // ── Hạ nhiệt ──────────────────────────────────────────────────────────────
    // Bậc nhiệt hiện tại, dùng để tra các bảng *_MIN_INTERVAL_MS. Ghi trên main
    // thread (callback của governor), đọc trên cameraExecutor/inferenceExecutor.
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

        fun tryDone() {
            if (loadedCount.incrementAndGet() == totalModels) {
                mainHandler.post {
                    initCamera(lensFacing)
                    completion()
                }
            }
        }

        inferenceExecutor.execute {
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

        inferenceExecutor.execute {
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
            inferenceExecutor.execute {
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
        val executors = listOf(
            inferenceExecutor, cameraExecutor, captureExecutor
        )
        val predictors = listOf(detectPredictor, classifyPredictor, thirdPredictor)
        detectPredictor = null
        classifyPredictor = null
        thirdPredictor = null

        // Đóng model/GPU delegate có thể tốn hàng trăm ms; chạy trên main thread sẽ
        // treo UI đúng lúc rời màn camera. Đẩy sang luồng nền: chờ inference đang
        // chạy kết thúc (predict không interrupt được) rồi mới close để tránh
        // dùng model sau khi đã giải phóng.
        Thread {
            executors.forEach { it.shutdownNow() }
            executors.forEach { runCatching { it.awaitTermination(2, TimeUnit.SECONDS) } }
            predictors.forEach { (it as? BasePredictor)?.close() }
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

    /**
     * Ảnh still đã chuẩn hoá. [bitmap] là bản upright + đã crop, chỉ có khi
     * đường xử lý đã phải decode — giữ lại để tạo thumbnail mà không decode lại
     * JPEG FullHD lần nữa. Bên nhận sở hữu [bitmap] và phải recycle.
     */
    private class CapturedStill(val jpeg: ByteArray, val bitmap: Bitmap?)

    fun capturePhoto(
        crop: android.graphics.RectF? = null,
        jpegQuality: Int = 80,
        callback: (ByteArray?) -> Unit
    ) {
        captureStill(crop, jpegQuality) { still ->
            still?.bitmap?.recycle()
            callback(still?.jpeg)
        }
    }

    private fun captureStill(
        crop: android.graphics.RectF?,
        jpegQuality: Int,
        callback: (CapturedStill?) -> Unit
    ) {
        val ic = imageCaptureUseCase ?: run { callback(null); return }
        // Snapshot preview size on the main thread for the aspect-fill crop mapping.
        val previewW = previewView.width
        val previewH = previewView.height
        ic.takePicture(captureExecutor, object : ImageCapture.OnImageCapturedCallback() {
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
        captureStill(crop, jpegQuality) { still ->
            if (still == null) {
                callback(null)
                return@captureStill
            }
            try {
                val file = File(path)
                file.parentFile?.mkdirs()
                file.writeBytes(still.jpeg)
                if (thumbnailPath != null) {
                    runCatching {
                        writeThumbnail(still.jpeg, still.bitmap, thumbnailPath, thumbnailMaxSize)
                    }
                }
                callback(file.absolutePath)
            } catch (e: Exception) {
                Log.e(TAG, "capturePhotoToFile failed: ${e.message}")
                callback(null)
            } finally {
                still.bitmap?.recycle()
            }
        }
    }

    /**
     * Ghi thumbnail [maxSize]px. Ưu tiên [source] (bitmap upright đã có sẵn từ
     * bước crop) — decode lại [jpeg] FullHD chỉ để thu nhỏ là tốn thêm một lần
     * decode toàn khung. Khi buộc phải decode (ảnh không qua bước crop) thì
     * decode ở mức lấy mẫu thấp nhất còn đủ kích thước.
     */
    private fun writeThumbnail(jpeg: ByteArray, source: Bitmap?, path: String, maxSize: Int) {
        val decoded = if (source != null) null else decodeSampled(jpeg, maxSize)
        val base = source ?: decoded ?: return
        try {
            val longest = maxOf(base.width, base.height).coerceAtLeast(1)
            val scale = maxSize.toFloat() / longest.toFloat()
            val width = maxOf(1, (base.width * scale).toInt())
            val height = maxOf(1, (base.height * scale).toInt())
            val thumb = Bitmap.createScaledBitmap(base, width, height, true)
            try {
                val file = File(path)
                file.parentFile?.mkdirs()
                file.outputStream().use { out ->
                    thumb.compress(Bitmap.CompressFormat.JPEG, 65, out)
                }
            } finally {
                if (thumb !== base) thumb.recycle()
            }
        } finally {
            decoded?.recycle()
        }
    }

    private fun decodeSampled(jpeg: ByteArray, maxSize: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, bounds)
        val longest = maxOf(bounds.outWidth, bounds.outHeight)
        var sample = 1
        while (longest / (sample * 2) >= maxSize) sample *= 2
        val options = BitmapFactory.Options().apply { inSampleSize = sample }
        return BitmapFactory.decodeByteArray(jpeg, 0, jpeg.size, options)
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

        // Phase 1: Back-pressure check. Nếu inferenceExecutor đang bận chạy model
        // trước đó, bỏ qua frame hiện tại ngay lập tức để không sinh hàng đợi (zero lag).
        if (isInferring.get()) {
            bitmap.recycle()
            return
        }

        // Phase 2: Lập lịch xoay vòng (Round-Robin). Tìm candidate kế tiếp đủ điều kiện
        // (đã load, đúng phase, đủ khoảng cách minInterval theo bậc nhiệt).
        val tier = thermalTier.ordinal
        val slot = nextEligibleSlot(now, tier) ?: run {
            bitmap.recycle()
            return
        }

        if (!isInferring.compareAndSet(false, true)) {
            bitmap.recycle()
            return
        }

        when (slot) {
            Slot.DETECT -> lastDetectMs = now
            Slot.CLASSIFY -> lastClassifyMs = now
            Slot.THIRD -> lastThirdMs = now
        }

        val predictor = when (slot) {
            Slot.DETECT -> detectPredictor
            Slot.CLASSIFY -> classifyPredictor
            Slot.THIRD -> thirdPredictor
        } ?: run {
            isInferring.set(false)
            bitmap.recycle()
            return
        }

        // Phase 3: Thực thi inference đơn luồng trên inferenceExecutor.
        // Chỉ duy nhất 1 model chạy trên GPU/NPU tại bất kỳ thời điểm nào.
        // Bitmap được tái chế an toàn trong khối finally.
        inferenceExecutor.execute {
            try {
                val result = predictor.predict(bitmap, w, h, rotateForCamera = false, isLandscape = true)
                val data = buildTaskData(result, slot, camFpsNow)
                mainHandler.post { onMultiTaskStream?.invoke(data) }
            } catch (e: Exception) {
                Log.e(TAG, "$slot predict error: ${e.message}")
            } finally {
                isInferring.set(false)
                bitmap.recycle()
            }
        }
    }

    private fun isEligible(slot: Slot, now: Long, tier: Int): Boolean {
        return when (slot) {
            Slot.DETECT -> {
                if (detectPredictor == null || !detectEnabled) return false
                val minInterval = DETECT_MIN_INTERVAL_MS[tier]
                now - lastDetectMs >= minInterval
            }
            Slot.CLASSIFY -> {
                if (classifyPredictor == null) return false
                now - lastClassifyMs >= CLASSIFY_MIN_INTERVAL_MS[tier]
            }
            Slot.THIRD -> {
                if (thirdPredictor == null) return false
                val minInterval = if (isPanoramicPhase) {
                    THIRD_PANORAMIC_INTERVAL_MS[tier]
                } else {
                    THIRD_INSPECTION_INTERVAL_MS[tier]
                }
                now - lastThirdMs >= minInterval
            }
        }
    }

    private fun nextEligibleSlot(now: Long, tier: Int): Slot? {
        val size = rrCandidates.size
        for (step in 0 until size) {
            val index = (rrCursor + step) % size
            val slot = rrCandidates[index]
            if (isEligible(slot, now, tier)) {
                rrCursor = (index + 1) % size
                return slot
            }
        }
        return null
    }

    /** Updates the visible viewport (retained for backward compatibility). */
    fun setOcrViewport(top: Float, bottom: Float) {
        // No-op: OCR removed
    }

    /**
     * Phase-based gating: inspection runs carDamage; framing/panorama
     * runs in panoramic phase and stops carDamage. carCorner/carPart always run.
     */
    fun setInspectionActive(active: Boolean) {
        detectEnabled = active
        isPanoramicPhase = !active
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
    ): CapturedStill {
        if (rotationDegrees == 0 && crop == null) return CapturedStill(bytes, null)
        val decoded = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            ?: return CapturedStill(bytes, null)

        // Xoay và crop trong MỘT phép createBitmap: hai phép rời nhau phải cấp
        // phát (và ghi) thêm một bitmap FullHD trung gian.
        var bmp = decoded
        val cropRect = if (crop != null && previewW > 0 && previewH > 0) {
            viewportRectInSource(decoded, crop, previewW, previewH, rotationDegrees)
        } else {
            null
        }
        val matrix = if (rotationDegrees != 0) {
            Matrix().apply { postRotate(rotationDegrees.toFloat()) }
        } else {
            null
        }
        if (cropRect != null || matrix != null) {
            val x = cropRect?.left ?: 0
            val y = cropRect?.top ?: 0
            val w = cropRect?.width() ?: decoded.width
            val h = cropRect?.height() ?: decoded.height
            val out = if (matrix != null) {
                Bitmap.createBitmap(decoded, x, y, w, h, matrix, true)
            } else {
                Bitmap.createBitmap(decoded, x, y, w, h)
            }
            if (out !== decoded) { decoded.recycle(); bmp = out }
        }

        val jpeg = ByteArrayOutputStream().also { out ->
            bmp.compress(Bitmap.CompressFormat.JPEG, jpegQuality, out)
        }.toByteArray()
        return CapturedStill(jpeg, bmp)
    }

    /**
     * Khung nhìn thấy, tính bằng pixel của ảnh **chưa xoay**. Khung được tính
     * trên ảnh đã upright rồi xoay ngược về hệ toạ độ gốc, để crop và xoay gộp
     * được vào một phép [Bitmap.createBitmap].
     */
    private fun viewportRectInSource(
        src: Bitmap,
        crop: android.graphics.RectF,
        previewW: Int,
        previewH: Int,
        rotationDegrees: Int,
    ): android.graphics.Rect {
        val swap = (rotationDegrees / 90) % 2 != 0
        val uprightW = if (swap) src.height else src.width
        val uprightH = if (swap) src.width else src.height
        val upright = viewportRectUpright(uprightW, uprightH, crop, previewW, previewH)
        return when (((rotationDegrees % 360) + 360) % 360) {
            90 -> android.graphics.Rect(
                upright.top,
                uprightW - upright.right,
                upright.bottom,
                uprightW - upright.left,
            )
            180 -> android.graphics.Rect(
                uprightW - upright.right,
                uprightH - upright.bottom,
                uprightW - upright.left,
                uprightH - upright.top,
            )
            270 -> android.graphics.Rect(
                uprightH - upright.bottom,
                upright.left,
                uprightH - upright.top,
                upright.right,
            )
            else -> upright
        }
    }

    /** Khung nhìn thấy, tính bằng pixel của ảnh đã upright ([srcW] × [srcH]). */
    private fun viewportRectUpright(
        srcW: Int,
        srcH: Int,
        crop: android.graphics.RectF,
        previewW: Int,
        previewH: Int,
    ): android.graphics.Rect {
        val wp = srcW.toFloat()
        val hp = srcH.toFloat()
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
        val w = (right.coerceIn(0f, wp).toInt() - x).coerceIn(1, srcW - x)
        val h = (bottom.coerceIn(0f, hp).toInt() - y).coerceIn(1, srcH - y)
        return android.graphics.Rect(x, y, x + w, y + h)
    }

    // endregion

    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        release()
    }
}
