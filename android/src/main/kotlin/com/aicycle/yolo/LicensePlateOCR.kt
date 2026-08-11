// LicensePlateOCR — standalone LiteRT license-plate recognizer (CCT model).
//
// This is NOT a YOLO detector: it expects an already-cropped license-plate bitmap
// and returns the recognized plate string. Ported from the reference pipeline in
// license_plate_ocr/tflite/license_plate_ocr_tflite.py.
//
// Input : [1, 64, 128, 3] float32, raw 0–255, RGB, NHWC (flattened H,W,C).
// Output: reshapeable to [1, 12, 39] (12 char slots × 39 alphabet).

package com.aicycle.yolo

import android.content.Context
import android.graphics.Bitmap
import android.util.Log

class LicensePlateOCR(
    context: Context,
    modelPath: String,
    useGpu: Boolean,
    /** Minimum mean digit-confidence for a read to be accepted. */
    private val threshold: Double = 0.85,
) {
    companion object {
        private const val TAG = "LicensePlateOCR"
        private const val IMG_W = 128
        private const val IMG_H = 64
        private const val NUM_SLOTS = 12
        private val ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-._".toCharArray()
        private const val PAD_CHAR = '_'
        private val SPECIAL_CHARS = listOf("NG", "NN")
        private val PLATE_REGEX = Regex("^(\\d{2}[A-Za-z]{1,2})(\\d+)$")
    }

    // Reuse the project's LiteRT wrapper: float-in / float-out, positional buffers
    // (so the OCR model's non-Ultralytics tensor names don't matter for run()).
    private val model = LiteRtModel(context, modelPath, useGpu, TAG)

    // Scratch buffers reused across frames (OCR runs on a single executor thread).
    private val pixels = IntArray(IMG_W * IMG_H)
    private val input = FloatArray(IMG_W * IMG_H * 3)

    /** Recognizes the plate in [plateBitmap] (already cropped to the plate box). */
    fun read(plateBitmap: Bitmap): Pair<String, Double>? {
        return try {
            val scaled = Bitmap.createScaledBitmap(plateBitmap, IMG_W, IMG_H, true)
            scaled.getPixels(pixels, 0, IMG_W, 0, 0, IMG_W, IMG_H)
            if (scaled != plateBitmap) scaled.recycle()

            var dst = 0
            for (p in pixels) {
                // ARGB int → RGB float, raw 0–255 (no normalization).
                input[dst] = ((p shr 16) and 0xFF).toFloat()     // R
                input[dst + 1] = ((p shr 8) and 0xFF).toFloat()  // G
                input[dst + 2] = (p and 0xFF).toFloat()          // B
                dst += 3
            }

            val outputs = model.run(input)
            if (outputs.isEmpty()) return null
            postprocess(outputs[0])
        } catch (e: Exception) {
            Log.e(TAG, "inference failed: ${e.message}")
            null
        }
    }

    /** Decodes the [1,12,39] logits into a validated Vietnamese plate string. */
    private fun postprocess(logits: FloatArray): Pair<String, Double>? {
        val classes = ALPHABET.size // 39
        if (logits.size < NUM_SLOTS * classes) return null

        val rawChars = StringBuilder()
        val scores = ArrayList<Double>(NUM_SLOTS)
        for (t in 0 until NUM_SLOTS) {
            var bestIdx = 0
            var bestVal = -Float.MAX_VALUE
            val baseI = t * classes
            for (k in 0 until classes) {
                val v = logits[baseI + k]
                if (v > bestVal) { bestVal = v; bestIdx = k }
            }
            val ch = ALPHABET[bestIdx]
            if (ch == PAD_CHAR) continue // drop padding
            rawChars.append(ch)
            scores.add(bestVal.toDouble())
        }

        val joined = rawChars.toString()
        val cleaned = joined.filter { it != '.' && it != '-' && it != '_' }

        if (cleaned.length < 7) return null
        if (cleaned.length == 7 && joined.contains('.')) return null

        // Format: 2 digits + 1–2 letters, then remaining digits → "30H 12345".
        val finalPlate: String = run {
            val m = PLATE_REGEX.find(cleaned)
            when {
                m != null -> "${m.groupValues[1]} ${m.groupValues[2]}"
                SPECIAL_CHARS.any { joined.contains(it) } -> cleaned
                else -> return null
            }
        }

        // Confidence = mean score over the DIGIT characters only.
        val digitScores = ArrayList<Double>()
        for (i in joined.indices) {
            if (joined[i].isDigit()) digitScores.add(scores[i])
        }
        if (digitScores.isEmpty()) return null
        val finalScore = digitScores.average()

        return if (finalScore > threshold) Pair(finalPlate, finalScore) else null
    }

    fun close() {
        try { model.close() } catch (_: Throwable) { /* best-effort */ }
    }
}
