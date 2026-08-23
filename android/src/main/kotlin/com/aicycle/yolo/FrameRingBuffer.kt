package com.aicycle.yolo

/** One JPEG frame in the burst timeline with monotonic [stepIndex]. */
data class BurstFrame(
    val data: ByteArray,
    val stepIndex: Int,
    val isCallEngine: Boolean,
    val rotationDegrees: Int = 0,
    val previewWidth: Int = 0,
    val previewHeight: Int = 0,
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is BurstFrame) return false
        return stepIndex == other.stepIndex && isCallEngine == other.isCallEngine
    }

    override fun hashCode(): Int = stepIndex
}

/**
 * Fixed-capacity ring buffer holding the most recent [capacity] burst frames.
 * Access only from the owning serial executor (cameraExecutor).
 */
class FrameRingBuffer(capacity: Int = 5) {
    private val cap = maxOf(1, capacity)
    private val slots = arrayOfNulls<BurstFrame>(cap)
    private var writeHead = 0
    private var filled = 0

    fun write(frame: BurstFrame) {
        slots[writeHead] = frame
        writeHead = (writeHead + 1) % cap
        filled = minOf(filled + 1, cap)
    }

    /** Returns stored frames in chronological order (oldest first). */
    fun snapshot(): List<BurstFrame> {
        if (filled == 0) return emptyList()
        val count = minOf(filled, cap)
        val start = if (filled < cap) 0 else writeHead
        return (0 until count).mapNotNull { i -> slots[(start + i) % cap] }
    }

    val totalBytes: Int get() = slots.filterNotNull().sumOf { it.data.size }
}
