package com.aicycle.yolo

import android.content.Context
import android.util.Log
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.asRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.math.min
import kotlin.math.pow

object AICycleUploadScheduler {
    private const val UNIQUE_WORK_NAME = "aicycle_photo_upload_queue"
    private const val TAG = "AICycleUploadWorker"

    fun schedule(context: Context, queueFilePath: String) {
        val constraints = Constraints.Builder()
            .setRequiredNetworkType(NetworkType.CONNECTED)
            .build()
        val request = OneTimeWorkRequestBuilder<AICycleUploadQueueWorker>()
            .setConstraints(constraints)
            .setBackoffCriteria(
                BackoffPolicy.EXPONENTIAL,
                30,
                TimeUnit.SECONDS
            )
            .setInputData(workDataOf("queueFilePath" to queueFilePath))
            .addTag(UNIQUE_WORK_NAME)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            UNIQUE_WORK_NAME,
            ExistingWorkPolicy.KEEP,
            request
        )
        Log.i(TAG, "Upload queue scheduled: $queueFilePath")
    }
}

class AICycleUploadQueueWorker(
    appContext: Context,
    params: WorkerParameters
) : CoroutineWorker(appContext, params) {

    companion object {
        private const val TAG = "AICycleUploadWorker"
        private val queueLock = Any()
    }

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        val queueFilePath = inputData.getString("queueFilePath") ?: return@withContext Result.success()
        val queueFile = File(queueFilePath)
        if (!queueFile.exists()) return@withContext Result.success()

        try {
            while (true) {
                val item = nextDueItem(queueFile) ?: break
                val file = File(item.optString("filePath"))
                if (!file.exists()) {
                    Log.i(TAG, "Upload item file missing, marking complete: ${item.optString("id")}")
                    markSucceeded(queueFile, item.optString("id"), 0, "")
                    continue
                }

                markUploading(queueFile, item.optString("id"))
                Log.i(
                    TAG,
                    "Uploading photo: id=${item.optString("id")} " +
                        "angle=${item.optInt("angleId")} photo=${item.optInt("photoIndex")} " +
                        "bytes=${file.length()}"
                )
                try {
                    when (val outcome = upload(item, file)) {
                        is UploadOutcome.Success -> {
                            runCatching { file.delete() }
                            markSucceeded(
                                queueFile,
                                item.optString("id"),
                                outcome.statusCode,
                                outcome.responseBody
                            )
                            Log.i(
                                TAG,
                                "Upload succeeded: id=${item.optString("id")} " +
                                    "HTTP ${outcome.statusCode} bodyBytes=${outcome.responseBody.length}"
                            )
                        }
                        is UploadOutcome.ServerError -> {
                            runCatching { file.delete() }
                            val bodySnippet = outcome.responseBody.take(500)
                            if (hasEngineErrorCode(outcome.responseBody)) {
                                markSucceeded(
                                    queueFile,
                                    item.optString("id"),
                                    outcome.statusCode,
                                    outcome.responseBody
                                )
                                Log.w(
                                    TAG,
                                    "Upload business error delivered: " +
                                        "HTTP ${outcome.statusCode} body=$bodySnippet"
                                )
                            } else {
                                markSkipped(
                                    queueFile,
                                    item.optString("id"),
                                    "HTTP ${outcome.statusCode}: $bodySnippet"
                                )
                                Log.w(
                                    TAG,
                                    "Upload skipped after server error: " +
                                        "HTTP ${outcome.statusCode} body=$bodySnippet"
                                )
                            }
                        }
                    }
                } catch (e: IOException) {
                    val error = e.message ?: "Network upload failed"
                    markFailed(queueFile, item.optString("id"), error)
                    Log.w(TAG, "Network upload failed, will retry: $error")
                    return@withContext Result.retry()
                } catch (e: Exception) {
                    val error = e.message ?: "Upload request failed"
                    runCatching { file.delete() }
                    markSkipped(queueFile, item.optString("id"), error)
                    Log.w(TAG, "Upload skipped after non-network error: $error")
                }
            }
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "Queue worker crashed", e)
            Result.retry()
        }
    }

    private fun upload(item: JSONObject, file: File): UploadOutcome {
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

        val requestBuilder = Request.Builder()
            .url(item.getString("url"))
            .post(builder.build())
        val headers = item.optJSONObject("headers") ?: JSONObject()
        headers.keys().forEach { key ->
            requestBuilder.addHeader(key, headers.optString(key))
        }

        client.newCall(requestBuilder.build()).execute().use { response ->
            val responseBody = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                return UploadOutcome.ServerError(response.code, responseBody)
            }
            return UploadOutcome.Success(response.code, responseBody)
        }
    }

    private fun hasEngineErrorCode(responseBody: String): Boolean {
        return runCatching {
            val json = JSONObject(responseBody)
            json.has("errorCodeFromEngine") && !json.isNull("errorCodeFromEngine")
        }.getOrDefault(false)
    }

    private fun nextDueItem(queueFile: File): JSONObject? = synchronized(queueLock) {
        val now = System.currentTimeMillis()
        val queue = readQueue(queueFile)
        val items = queue.optJSONArray("items") ?: return@synchronized null
        for (i in 0 until items.length()) {
            val item = items.optJSONObject(i) ?: continue
            val status = item.optString("status", "pending")
            if (status == "succeeded" || status == "skipped") continue
            if (item.optLong("nextAttemptAtMillis", 0) > now) continue
            return@synchronized JSONObject(item.toString())
        }
        null
    }

    private fun markUploading(queueFile: File, id: String) = updateItem(queueFile, id) { item ->
        item.put("status", "uploading")
        item.put("updatedAtMillis", System.currentTimeMillis())
    }

    private fun markSucceeded(
        queueFile: File,
        id: String,
        statusCode: Int,
        responseBody: String
    ) = updateItem(queueFile, id) { item ->
        item.put("status", "succeeded")
        item.put("updatedAtMillis", System.currentTimeMillis())
        item.put("responseStatusCode", statusCode)
        if (responseBody.isNotBlank()) {
            item.put("responseBody", responseBody)
        } else {
            item.remove("responseBody")
        }
        item.remove("lastError")
    }

    private fun markSkipped(queueFile: File, id: String, reason: String) = updateItem(queueFile, id) { item ->
        item.put("status", "skipped")
        item.put("updatedAtMillis", System.currentTimeMillis())
        item.put("lastError", reason)
    }

    private fun markFailed(queueFile: File, id: String, error: String) = updateItem(queueFile, id) { item ->
        val attempt = item.optInt("attempt", 0) + 1
        val delaySeconds = min(3600.0, 2.0.pow(attempt.toDouble()) * 30.0).toLong()
        item.put("status", "failed")
        item.put("attempt", attempt)
        item.put("nextAttemptAtMillis", System.currentTimeMillis() + delaySeconds * 1000)
        item.put("updatedAtMillis", System.currentTimeMillis())
        item.put("lastError", error)
    }

    private fun updateItem(queueFile: File, id: String, update: (JSONObject) -> Unit) = synchronized(queueLock) {
        val queue = readQueue(queueFile)
        val items = queue.optJSONArray("items") ?: JSONArray()
        for (i in 0 until items.length()) {
            val item = items.optJSONObject(i) ?: continue
            if (item.optString("id") == id) {
                update(item)
                break
            }
        }
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
        val tmp = File("${queueFile.absolutePath}.tmp")
        tmp.writeText(queue.toString())
        if (queueFile.exists()) queueFile.delete()
        tmp.renameTo(queueFile)
    }
}

private sealed class UploadOutcome {
    data class Success(val statusCode: Int, val responseBody: String) : UploadOutcome()
    data class ServerError(val statusCode: Int, val responseBody: String) : UploadOutcome()
}
