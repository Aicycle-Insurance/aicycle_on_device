package com.aicycle.yolo

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log

/**
 * Bậc nhiệt đã chuẩn hoá giữa Android và iOS. Các view inference dùng [ordinal]
 * để tra bảng nhịp chạy model — nên thứ tự khai báo phải khớp với thứ tự cột
 * trong các bảng đó (và với `ThermalTier` bên Swift).
 */
enum class ThermalTier(val label: String) {
    /** Máy mát — chạy full nhịp. */
    NORMAL("normal"),

    /** Bắt đầu ấm — hạ nhịp nhẹ, user chưa cảm nhận được khác biệt. */
    WARM("warm"),

    /** Nóng rõ — hạ nhịp mạnh, hệ điều hành có thể đã bắt đầu throttle SoC. */
    HOT("hot"),

    /** Rất nóng — chạy ở nhịp tối thiểu vừa đủ để luồng nghiệp vụ không đứng. */
    CRITICAL("critical"),
}

/**
 * Theo dõi nhiệt độ thiết bị và quy đổi về [ThermalTier] để bên gọi tự hạ nhịp
 * chạy model khi máy nóng.
 *
 * Hai nguồn tín hiệu:
 *  * API 29+ — [PowerManager.getCurrentThermalStatus] + listener của hệ điều
 *    hành. Đây là nguồn chuẩn: nó phản ánh đúng thời điểm HĐH bắt đầu throttle.
 *  * API 23–28 — không có thermal API công khai, nên poll nhiệt độ pin từ sticky
 *    broadcast [Intent.ACTION_BATTERY_CHANGED]. Nhiệt độ pin trễ hơn nhiệt độ
 *    SoC và chỉ là tín hiệu thô, nhưng đủ để chặn trường hợp chạy 20–30 phút
 *    liên tục làm máy nóng ran.
 *
 * [onChange] được gọi trên main thread, chỉ khi bậc nhiệt thực sự đổi.
 */
class ThermalGovernor(
    private val context: Context,
    private val onChange: (ThermalTier) -> Unit,
) {
    companion object {
        private const val TAG = "ThermalGovernor"

        /** Nhịp poll nhiệt độ pin ở đường dự phòng (API < 29). */
        private const val BATTERY_POLL_INTERVAL_MS = 10_000L

        // Ngưỡng nhiệt độ pin (°C) cho đường dự phòng. Pin nguội hơn SoC khá
        // nhiều nên các mốc này thấp hơn cảm giác "nóng" trên tay.
        private const val BATTERY_WARM_C = 38f
        private const val BATTERY_HOT_C = 41f
        private const val BATTERY_CRITICAL_C = 44f
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager

    @Volatile
    var tier: ThermalTier = ThermalTier.NORMAL
        private set

    private var thermalListener: PowerManager.OnThermalStatusChangedListener? = null
    private var batteryPoll: Runnable? = null
    private var started = false

    /** Bắt đầu theo dõi. An toàn khi gọi nhiều lần. Phải gọi trên main thread. */
    fun start() {
        if (started) return
        started = true

        val pm = powerManager
        if (pm != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            apply(tierForThermalStatus(pm.currentThermalStatus))
            val listener = PowerManager.OnThermalStatusChangedListener { status ->
                apply(tierForThermalStatus(status))
            }
            val registered = runCatching { pm.addThermalStatusListener(listener) }.isSuccess
            if (registered) {
                thermalListener = listener
                return
            }
            Log.w(TAG, "addThermalStatusListener failed; falling back to battery temperature")
        }

        startBatteryPolling()
    }

    /** Ngừng theo dõi và gỡ mọi listener/timer. An toàn khi gọi nhiều lần và từ luồng bất kỳ. */
    fun stop() {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            mainHandler.post { stop() }
            return
        }
        if (!started) return
        started = false

        thermalListener?.let { listener ->
            thermalListener = null
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                runCatching { powerManager?.removeThermalStatusListener(listener) }
            }
        }
        batteryPoll?.let { mainHandler.removeCallbacks(it) }
        batteryPoll = null
    }

    // region Nguồn tín hiệu

    private fun startBatteryPolling() {
        val poll = object : Runnable {
            override fun run() {
                if (!started) return
                readBatteryTemperatureC()?.let { apply(tierForBatteryTemperature(it)) }
                mainHandler.postDelayed(this, BATTERY_POLL_INTERVAL_MS)
            }
        }
        batteryPoll = poll
        poll.run()
    }

    /**
     * Đọc nhiệt độ pin từ sticky broadcast. Truyền receiver null nên không có gì
     * để đăng ký/gỡ — chỉ lấy giá trị hiện tại.
     */
    private fun readBatteryTemperatureC(): Float? {
        val intent = runCatching {
            context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        }.getOrNull() ?: return null
        // EXTRA_TEMPERATURE tính theo phần mười độ C; -1 nghĩa là không có dữ liệu.
        val tenths = intent.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Int.MIN_VALUE)
        if (tenths == Int.MIN_VALUE || tenths <= 0) return null
        return tenths / 10f
    }

    // endregion

    // region Quy đổi

    private fun tierForThermalStatus(status: Int): ThermalTier = when {
        status <= PowerManager.THERMAL_STATUS_LIGHT -> ThermalTier.NORMAL
        status == PowerManager.THERMAL_STATUS_MODERATE -> ThermalTier.WARM
        status == PowerManager.THERMAL_STATUS_SEVERE -> ThermalTier.HOT
        else -> ThermalTier.CRITICAL // CRITICAL / EMERGENCY / SHUTDOWN
    }

    private fun tierForBatteryTemperature(celsius: Float): ThermalTier = when {
        celsius >= BATTERY_CRITICAL_C -> ThermalTier.CRITICAL
        celsius >= BATTERY_HOT_C -> ThermalTier.HOT
        celsius >= BATTERY_WARM_C -> ThermalTier.WARM
        else -> ThermalTier.NORMAL
    }

    private fun apply(next: ThermalTier) {
        if (next == tier) return
        val previous = tier
        tier = next
        Log.i(TAG, "Thermal tier ${previous.label} → ${next.label}")
        if (Looper.myLooper() == Looper.getMainLooper()) {
            onChange(next)
        } else {
            mainHandler.post { onChange(next) }
        }
    }

    // endregion
}
