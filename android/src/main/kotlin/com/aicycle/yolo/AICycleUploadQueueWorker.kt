package com.aicycle.yolo

import android.content.Context
import android.system.Os
import android.util.Log
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkInfo
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.asRequestBody
import okhttp3.Response
import okio.Buffer
import okio.BufferedSink
import okio.ForwardingSink
import okio.buffer
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.io.InterruptedIOException
import java.util.UUID
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Upload policy shared with the Dart queue (`photo_upload_queue.dart`) and the
 * iOS uploader. The queue file's top-level `mode` selects it:
 *  - `background`: user is still capturing; 90s per request, long backoff.
 *  - `fast`: user is waiting on the upload screen; 60s per request, quick retry.
 * A top-level `paused: true` stops the worker until Dart reschedules.
 */
internal object AICycleUploadPolicy {
    const val MODE_FAST = "fast"

    // Only these HTTP codes are retried; any other non-2xx is final (rejected).
    fun isRetryableHttp(code: Int) = code == 408 || code == 429 || code in 500..599

    fun retryDelayMillis(mode: String, attempt: Int): Long = if (mode == MODE_FAST) {
        when {
            attempt <= 1 -> 0L
            attempt == 2 -> 2_000L
            else -> 5_000L
        }
    } else {
        // Retry soon first so a brief network blip heals before the capture
        // screen's warning threshold, then back off up to 5 minutes.
        BACKGROUND_RETRY_DELAYS_MS[(attempt - 1).coerceIn(0, BACKGROUND_RETRY_DELAYS_MS.lastIndex)]
    }

    private val BACKGROUND_RETRY_DELAYS_MS =
        longArrayOf(5_000L, 15_000L, 30_000L, 60_000L, 120_000L, 300_000L)
}

object AICycleUploadScheduler {
    internal const val UNIQUE_WORK_NAME = "aicycle_photo_upload_queue"
    private const val WAKEUP_WORK_NAME = "aicycle_photo_upload_wakeup"
    private const val TAG = "AICycleUploadWorker"

    private fun networkConstraints() = Constraints.Builder()
        .setRequiredNetworkType(NetworkType.CONNECTED)
        .build()

    fun schedule(context: Context, queueFilePath: String) {
        val workManager = WorkManager.getInstance(context)
        // One queued follow-up drain is enough: it re-reads the queue file when
        // it starts. Without this check every Dart "kick" would append another
        // no-op worker to the chain while the current one is still looping.
        val queuedFollowUps = runCatching {
            workManager.getWorkInfosForUniqueWork(UNIQUE_WORK_NAME).get()
                .count { it.state == WorkInfo.State.ENQUEUED || it.state == WorkInfo.State.BLOCKED }
        }.getOrDefault(0)
        if (queuedFollowUps > 0) return

        val request = OneTimeWorkRequestBuilder<AICycleUploadQueueWorker>()
            .setConstraints(networkConstraints())
            .setInputData(workDataOf("queueFilePath" to queueFilePath))
            .addTag(UNIQUE_WORK_NAME)
            .build()
        workManager.enqueueUniqueWork(
            UNIQUE_WORK_NAME,
            // A capture can arrive while the current worker is between its final
            // queue read and completion. KEEP would discard that scheduling
            // request and leave the new photo pending until another app resume.
            // Append a follow-up drain instead; it is a cheap no-op when the
            // current worker already picked up the new item.
            ExistingWorkPolicy.APPEND_OR_REPLACE,
            request
        )
        Log.i(TAG, "Upload queue scheduled: $queueFilePath")
    }

    /** Wakes the queue when the earliest failed item becomes due again. */
    fun scheduleWakeup(context: Context, queueFilePath: String, delayMillis: Long) {
        val request = OneTimeWorkRequestBuilder<AICycleUploadWakeupWorker>()
            .setConstraints(networkConstraints())
            .setInitialDelay(delayMillis.coerceAtLeast(0L), TimeUnit.MILLISECONDS)
            .setInputData(workDataOf("queueFilePath" to queueFilePath))
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            WAKEUP_WORK_NAME,
            ExistingWorkPolicy.REPLACE,
            request
        )
        Log.i(TAG, "Upload retry wakeup in ${delayMillis}ms")
    }

    /** "Thử lại": drop the pending backoff wakeup and drain right away. */
    fun retryNow(context: Context, queueFilePath: String) {
        WorkManager.getInstance(context).cancelUniqueWork(WAKEUP_WORK_NAME)
        schedule(context, queueFilePath)
    }

    /** Cancels every upload, including the in-flight HTTP call. */
    fun cancelAll(context: Context) {
        val workManager = WorkManager.getInstance(context)
        workManager.cancelUniqueWork(WAKEUP_WORK_NAME)
        workManager.cancelUniqueWork(UNIQUE_WORK_NAME)
        Log.i(TAG, "Upload queue cancelled")
    }
}

class AICycleUploadWakeupWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        val queueFilePath = inputData.getString("queueFilePath") ?: return Result.success()
        AICycleUploadScheduler.schedule(applicationContext, queueFilePath)
        return Result.success()
    }
}

class AICycleUploadQueueWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    companion object {
        private const val TAG = "AICycleUploadWorker"
        private val queueLock = Any()

        // In fast mode the worker waits in-process for short backoffs instead of
        // round-tripping through WorkManager.
        private const val IN_PROCESS_WAIT_LIMIT_MS = 15_000L

        // Whole-request limits, and the budget the speed check projects against.
        private const val FAST_TOTAL_MS = 60_000L
        private const val BACKGROUND_TOTAL_MS = 90_000L

        // From this far into sending a body, an upload whose measured speed
        // cannot finish within the total limit is cut early.
        private const val SPEED_CHECK_AFTER_MS = 15_000L
        private const val SPEED_CHECK_INTERVAL_MS = 2_000L

        private val baseClient = OkHttpClient()
        private val fastClient = baseClient.newBuilder()
            .connectTimeout(8, TimeUnit.SECONDS)
            .writeTimeout(20, TimeUnit.SECONDS)
            .readTimeout(15, TimeUnit.SECONDS)
            .callTimeout(FAST_TOTAL_MS, TimeUnit.MILLISECONDS)
            .build()
        private val backgroundClient = baseClient.newBuilder()
            .connectTimeout(15, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .callTimeout(BACKGROUND_TOTAL_MS, TimeUnit.MILLISECONDS)
            .build()
    }

    /** Thrown when the speed check cuts an upload; handled as a timeout. */
    private class UploadTooSlowException(message: String) : InterruptedIOException(message)

    private sealed class Next {
        data class Upload(val item: JSONObject) : Next()
        data class Wait(val millis: Long, val mode: String) : Next()
        object Done : Next()
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val queueFilePath = inputData.getString("queueFilePath") ?: return@withContext Result.success()
        val queueFile = File(queueFilePath)
        if (!queueFile.exists()) return@withContext Result.success()

        try {
            while (true) {
                when (val next = nextItem(queueFile)) {
                    is Next.Done -> break
                    is Next.Wait -> {
                        if (next.mode == AICycleUploadPolicy.MODE_FAST &&
                            next.millis <= IN_PROCESS_WAIT_LIMIT_MS
                        ) {
                            delay(next.millis)
                            continue
                        }
                        AICycleUploadScheduler.scheduleWakeup(
                            applicationContext,
                            queueFilePath,
                            next.millis
                        )
                        break
                    }
                    is Next.Upload -> processItem(queueFile, next.item)
                }
            }
            Result.success()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "Queue worker crashed", e)
            Result.retry()
        }
    }

    private suspend fun processItem(queueFile: File, item: JSONObject) {
        val id = item.optString("id")
        val file = File(item.optString("filePath"))
        if (!file.exists()) {
            Log.i(TAG, "Upload item file missing, dropping: $id")
            markSkipped(queueFile, id, "File missing")
            return
        }

        val mode = readMode(queueFile)
        markUploading(queueFile, id)
        Log.i(
            TAG,
            "Uploading photo: id=$id angle=${item.optInt("angleId")} " +
                "photo=${item.optInt("photoIndex")} bytes=${file.length()} mode=$mode"
        )
        try {
            val (code, body) = upload(item, file, mode)
            when {
                code in 200..299 -> {
                    // Persist the response before deleting the only photo copy.
                    // If the process is stopped between these steps, Dart can
                    // still replay the cached response on resume.
                    markSucceeded(queueFile, id, code, body)
                    runCatching { file.delete() }
                    Log.i(TAG, "Upload succeeded: id=$id HTTP $code bodyBytes=${body.length}")
                }
                AICycleUploadPolicy.isRetryableHttp(code) ||
                    isRetryableEngineError(queueFile, code, body) -> {
                    markFailed(queueFile, id, "server", "HTTP $code", code, mode)
                    Log.w(TAG, "Upload server error, will retry: id=$id HTTP $code body=${body.take(500)}")
                }
                else -> {
                    // The server rejected this photo; retrying cannot help.
                    markRejected(queueFile, id, code, body)
                    runCatching { file.delete() }
                    Log.w(TAG, "Upload rejected: id=$id HTTP $code body=${body.take(500)}")
                }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: InterruptedIOException) {
            // SocketTimeoutException and OkHttp call timeouts.
            markFailed(queueFile, id, "timeout", e.message ?: "Upload timed out", null, mode)
            Log.w(TAG, "Upload timed out, will retry: id=$id ${e.message}")
        } catch (e: IOException) {
            markFailed(queueFile, id, "network", e.message ?: "Network upload failed", null, mode)
            Log.w(TAG, "Network upload failed, will retry: id=$id ${e.message}")
        } catch (e: Exception) {
            runCatching { file.delete() }
            markSkipped(queueFile, id, e.message ?: "Upload request failed")
            Log.w(TAG, "Upload skipped after non-network error: id=$id ${e.message}")
        }
    }

    private suspend fun upload(item: JSONObject, file: File, mode: String): Pair<Int, String> {
        val builder = MultipartBody.Builder().setType(MultipartBody.FORM)
        val fields = item.optJSONObject("fields") ?: JSONObject()
        fields.keys().forEach { key ->
            builder.addFormDataPart(key, fields.optString(key))
        }
        builder.addFormDataPart(
            item.optString("fileField", "img"),
            item.optString("fileName", file.name),
            file.asRequestBody("image/jpeg".toMediaType())
        )

        val body = CountingRequestBody(builder.build())
        val requestBuilder = Request.Builder()
            .url(item.getString("url"))
            .post(body)
        val headers = item.optJSONObject("headers") ?: JSONObject()
        headers.keys().forEach { key ->
            requestBuilder.addHeader(key, headers.optString(key))
        }

        val fast = mode == AICycleUploadPolicy.MODE_FAST
        val client = if (fast) fastClient else backgroundClient
        val totalLimitMs = if (fast) FAST_TOTAL_MS else BACKGROUND_TOTAL_MS
        val call = client.newCall(requestBuilder.build())
        return coroutineScope {
            var tooSlow: String? = null
            val speedCheck = launch {
                while (true) {
                    delay(SPEED_CHECK_INTERVAL_MS)
                    val reason = body.tooSlowReason(totalLimitMs) ?: continue
                    tooSlow = reason
                    call.cancel()
                    break
                }
            }
            try {
                call.await().use { response -> response.code to response.body.string() }
            } catch (e: IOException) {
                tooSlow?.let { throw UploadTooSlowException(it) }
                throw e
            } finally {
                speedCheck.cancel()
            }
        }
    }

    /**
     * Counts body bytes handed to the socket so the speed check can project
     * whether the upload finishes within the total limit.
     */
    private class CountingRequestBody(private val delegate: RequestBody) : RequestBody() {
        private val sent = AtomicLong(0)
        @Volatile private var sendStartedAt = 0L

        override fun contentType(): MediaType? = delegate.contentType()

        override fun contentLength(): Long = delegate.contentLength()

        override fun writeTo(sink: BufferedSink) {
            sent.set(0)
            sendStartedAt = System.currentTimeMillis()
            val counting = object : ForwardingSink(sink) {
                override fun write(source: Buffer, byteCount: Long) {
                    super.write(source, byteCount)
                    sent.addAndGet(byteCount)
                }
            }.buffer()
            delegate.writeTo(counting)
            counting.flush()
        }

        /** Non-null when, at the measured speed, the body cannot finish in time. */
        fun tooSlowReason(totalLimitMs: Long): String? {
            val startedAt = sendStartedAt
            val total = contentLength()
            val sentBytes = sent.get()
            if (startedAt == 0L || total <= 0 || sentBytes >= total) return null
            val elapsed = System.currentTimeMillis() - startedAt
            if (elapsed < SPEED_CHECK_AFTER_MS) return null
            val projected = if (sentBytes > 0) {
                elapsed + (total - sentBytes) * elapsed / sentBytes
            } else {
                Long.MAX_VALUE
            }
            if (projected <= totalLimitMs) return null
            return "Upload too slow: sent $sentBytes/$total bytes in ${elapsed}ms, " +
                "needs ~${projected}ms > ${totalLimitMs}ms"
        }
    }

    /** Suspends on the call so cancelling the worker also cancels the HTTP request. */
    private suspend fun Call.await(): Response = suspendCancellableCoroutine { cont ->
        cont.invokeOnCancellation { cancel() }
        enqueue(object : Callback {
            override fun onFailure(call: Call, e: IOException) {
                if (cont.isActive) cont.resumeWithException(e)
            }

            override fun onResponse(call: Call, response: Response) {
                @Suppress("DEPRECATION")
                cont.resume(response) { response.close() }
            }
        })
    }

    /**
     * New photos go first, then failed photos whose backoff has elapsed, so one
     * failing photo never holds back the rest of the queue.
     */
    private fun nextItem(queueFile: File): Next = synchronized(queueLock) {
        val queue = readQueue(queueFile)
        // Dart pauses the queue while an upload error is shown and reschedules
        // it when the user taps "Thử lại" / "Chụp tiếp".
        if (queue.optBoolean("paused", false)) return@synchronized Next.Done
        val items = queue.optJSONArray("items") ?: return@synchronized Next.Done
        val now = System.currentTimeMillis()
        var dueRetry: JSONObject? = null
        var earliestRetryAt = Long.MAX_VALUE
        for (i in 0 until items.length()) {
            val item = items.optJSONObject(i) ?: continue
            when (item.optString("status", "pending")) {
                "succeeded", "skipped", "rejected" -> continue
                "failed" -> {
                    val at = item.optLong("nextAttemptAtMillis", 0L)
                    if (at <= now) {
                        if (dueRetry == null) dueRetry = item
                    } else if (at < earliestRetryAt) {
                        earliestRetryAt = at
                    }
                }
                // pending, or "uploading" left behind by a killed worker.
                else -> return@synchronized Next.Upload(JSONObject(item.toString()))
            }
        }
        dueRetry?.let { return@synchronized Next.Upload(JSONObject(it.toString())) }
        if (earliestRetryAt != Long.MAX_VALUE) {
            return@synchronized Next.Wait(earliestRetryAt - now, modeOf(queue))
        }
        Next.Done
    }

    /**
     * HTTP 400 whose body carries an `errorCodeFromEngine` listed in the queue
     * file's `retryableEngineErrorCodes` (declared in Dart): the server stored
     * the photo but its AI engine failed transiently, so retry like a 5xx.
     */
    private fun isRetryableEngineError(queueFile: File, code: Int, body: String): Boolean {
        if (code != 400) return false
        val retryable = synchronized(queueLock) {
            val codes = readQueue(queueFile).optJSONArray("retryableEngineErrorCodes")
                ?: return false
            (0 until codes.length()).mapNotNull { codes.optString(it).trim().ifEmpty { null } }.toSet()
        }
        if (retryable.isEmpty()) return false
        val json = runCatching { org.json.JSONTokener(body).nextValue() }.getOrNull() ?: return false
        return findEngineErrorCodes(json).any { it in retryable }
    }

    /** Every `errorCodeFromEngine` value at any depth, as strings ("10012"). */
    private fun findEngineErrorCodes(node: Any?): List<String> = when (node) {
        is JSONObject -> node.keys().asSequence().flatMap { key ->
            val value = node.opt(key)
            if (key == "errorCodeFromEngine") {
                sequenceOf(engineCodeString(value))
            } else {
                findEngineErrorCodes(value).asSequence()
            }
        }.filterNotNull().toList()
        is JSONArray -> (0 until node.length()).flatMap { findEngineErrorCodes(node.opt(it)) }
        else -> emptyList()
    }

    private fun engineCodeString(value: Any?): String? = when (value) {
        is Number -> value.toLong().toString()
        is String -> value.trim().ifEmpty { null }
        else -> null
    }

    private fun readMode(queueFile: File): String = synchronized(queueLock) {
        modeOf(readQueue(queueFile))
    }

    private fun modeOf(queue: JSONObject) = queue.optString("mode", "background")

    private fun markUploading(queueFile: File, id: String) = updateQueue(queueFile, id) { _, item ->
        item.put("status", "uploading")
        item.put("updatedAtMillis", System.currentTimeMillis())
    }

    private fun markSucceeded(
        queueFile: File,
        id: String,
        statusCode: Int,
        responseBody: String
    ) = updateQueue(queueFile, id) { queue, item ->
        val now = System.currentTimeMillis()
        item.put("status", "succeeded")
        item.put("updatedAtMillis", now)
        item.put("responseStatusCode", statusCode)
        putResponseBody(item, responseBody)
        item.remove("lastError")
        item.remove("errorType")
        queue.put("lastResponseAtMillis", now)
        if (item.optBoolean("isCallEngine")) {
            queue.put("lastSuccessAtMillis", now)
            queue.remove("failureStreak")
        }
    }

    private fun markRejected(
        queueFile: File,
        id: String,
        statusCode: Int,
        responseBody: String
    ) = updateQueue(queueFile, id) { queue, item ->
        item.put("status", "rejected")
        item.put("updatedAtMillis", System.currentTimeMillis())
        queue.put("lastResponseAtMillis", System.currentTimeMillis())
        item.put("responseStatusCode", statusCode)
        item.put("errorType", "rejected")
        putResponseBody(item, responseBody)
        // The server answered, so it is reachable: the failure streak is over.
        if (item.optBoolean("isCallEngine")) queue.remove("failureStreak")
    }

    private fun markSkipped(queueFile: File, id: String, reason: String) = updateQueue(queueFile, id) { _, item ->
        item.put("status", "skipped")
        item.put("updatedAtMillis", System.currentTimeMillis())
        item.put("lastError", reason)
    }

    private fun markFailed(
        queueFile: File,
        id: String,
        errorType: String,
        error: String,
        statusCode: Int?,
        mode: String
    ) = updateQueue(queueFile, id) { queue, item ->
        val now = System.currentTimeMillis()
        val attempt = item.optInt("attempt", 0) + 1
        item.put("status", "failed")
        item.put("attempt", attempt)
        item.put("errorType", errorType)
        item.put("lastFailedAtMillis", now)
        item.put("nextAttemptAtMillis", now + AICycleUploadPolicy.retryDelayMillis(mode, attempt))
        item.put("updatedAtMillis", now)
        item.put("lastError", error)
        if (statusCode != null) {
            item.put("lastStatusCode", statusCode)
            // The server answered (with an error): the connection is alive.
            queue.put("lastResponseAtMillis", now)
        } else {
            item.remove("lastStatusCode")
        }
        if (item.optBoolean("isCallEngine")) recordFailure(queue, id, errorType, now)
    }

    /**
     * Consecutive captured-photo failures since the last server answer, read by
     * Dart to decide when to warn the user. Any success or rejection removes
     * it. Context-stream frames are not counted.
     */
    private fun recordFailure(queue: JSONObject, id: String, errorType: String, now: Long) {
        val streak = queue.optJSONObject("failureStreak") ?: JSONObject().put("sinceMillis", now)
        streak.put("count", streak.optInt("count", 0) + 1)
        streak.put(
            "timeoutCount",
            if (errorType == "timeout") streak.optInt("timeoutCount", 0) + 1 else 0
        )
        streak.put("lastErrorType", errorType)
        streak.put("lastFailedAtMillis", now)
        val ids = streak.optJSONArray("itemIds") ?: JSONArray()
        val known = (0 until ids.length()).any { ids.optString(it) == id }
        if (!known && ids.length() < 50) ids.put(id)
        streak.put("itemIds", ids)
        queue.put("failureStreak", streak)
    }

    private fun putResponseBody(item: JSONObject, responseBody: String) {
        if (responseBody.isNotBlank()) {
            item.put("responseBody", responseBody)
        } else {
            item.remove("responseBody")
        }
    }

    private fun updateQueue(
        queueFile: File,
        id: String,
        update: (JSONObject, JSONObject) -> Unit
    ) = synchronized(queueLock) {
        val queue = readQueue(queueFile)
        val items = queue.optJSONArray("items") ?: JSONArray()
        var found = false
        for (i in 0 until items.length()) {
            val item = items.optJSONObject(i) ?: continue
            if (item.optString("id") == id) {
                update(queue, item)
                found = true
                break
            }
        }
        // The item is gone when the session was cancelled mid-upload; do not
        // resurrect streak/success bookkeeping for it.
        if (!found) return@synchronized
        queue.put("items", items)
        writeQueue(queueFile, queue)
    }

    private fun readQueue(queueFile: File): JSONObject {
        return runCatching {
            JSONObject(queueFile.readText())
        }.getOrElse {
            JSONObject().put("version", 1).put("items", JSONArray())
        }
    }

    private fun writeQueue(queueFile: File, queue: JSONObject) {
        val tmp = File("${queueFile.absolutePath}.android-${UUID.randomUUID()}.tmp")
        try {
            tmp.writeText(queue.toString())
            // POSIX rename atomically replaces the destination. A unique temp
            // path avoids racing with Dart or the iOS-style background writer.
            Os.rename(tmp.absolutePath, queueFile.absolutePath)
        } finally {
            if (tmp.exists()) tmp.delete()
        }
    }
}
