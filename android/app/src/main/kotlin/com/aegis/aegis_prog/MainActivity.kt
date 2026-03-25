package com.aegis.aegis_prog

import android.app.Activity
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * ============================================================================ AEGIS MainActivity —
 * สะพานเชื่อม Flutter ↔ Android Native
 * ============================================================================
 *
 * หน้าที่หลัก: ทำหน้าที่เป็นตัวกลาง (bridge) ระหว่าง Flutter UI กับ Android Native VPN Service
 * โดยใช้ Platform Channels 2 ตัว:
 *
 * 1. MethodChannel ("com.aegis/vpn")
 * ```
 *      - Flutter เรียก → Kotlin: สั่ง start/stop VPN
 *      - รองรับ 3 methods: startVpn, stopVpn, isVpnRunning
 * ```
 * 2. EventChannel ("com.aegis/logs")
 * ```
 *      - Kotlin ส่ง → Flutter: stream log messages จาก VPN Service
 *      - VPN Service ส่ง broadcast → BroadcastReceiver จับ → EventSink ส่งไป Flutter
 * ```
 * Flow การทำงาน: Flutter toggleAdBlock(true)
 * ```
 *     → MethodChannel.invokeMethod('startVpn')
 *       → startVpnService()
 *         → VpnService.prepare() → ขอ permission จาก user
 *         → launchVpn() → startService(MyVpnService)
 *           → MyVpnService.onStartCommand() → สร้าง TUN interface
 *             → processPackets() → DNS filtering loop
 *               → sendLog() → broadcast "🚫 Blocked: ufabet.com"
 *                 → vpnLogReceiver.onReceive() → logEventSink.success()
 *                   → Flutter _logChannel.listen() → _addLog()
 *                     → แสดงใน Live Log panel
 * ```
 * ============================================================================
 */
class MainActivity : FlutterActivity() {

    companion object {
        const val TAG = "AegisMain" // Log tag สำหรับ debug
        const val VPN_CHANNEL = "com.aegis/vpn" // MethodChannel name
        const val LOG_CHANNEL = "com.aegis/logs" // EventChannel name
        const val VPN_REQUEST_CODE = 100 // requestCode สำหรับ VPN permission dialog
    }

    // เก็บ Result ไว้ตอบ Flutter หลังจาก user กด OK/Cancel ที่ VPN permission dialog
    private var pendingResult: MethodChannel.Result? = null

    // EventSink สำหรับส่ง log จาก Native → Flutter
    // null = Flutter ยังไม่ได้ listen, not null = Flutter กำลัง listen อยู่
    private var logEventSink: EventChannel.EventSink? = null

    /**
     * ========================================================================== vpnLogReceiver —
     * BroadcastReceiver รับ log จาก MyVpnService
     * ========================================================================== Logic:
     * 1. MyVpnService เรียก sendBroadcast() เมื่อมี event เกิดขึ้น
     * ```
     *      (เช่น DNS blocked, packet forwarded)
     * ```
     * 2. BroadcastReceiver นี้จับ broadcast ที่มี action = ACTION_LOG
     * 3. ดึง log message จาก Intent extra
     * 4. ส่งต่อไปยัง Flutter ผ่าน logEventSink.success()
     * ```
     *      (ต้อง runOnUiThread เพราะ EventSink ต้องเรียกจาก main thread)
     * ```
     * เอาไว้: เป็นตัวกลางรับ log จาก VPN Service แล้วส่งไป Flutter
     * ==========================================================================
     */
    private val vpnLogReceiver =
            object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    // ดึง log message จาก broadcast intent
                    val message = intent?.getStringExtra(MyVpnService.EXTRA_LOG_MESSAGE) ?: return
                    Log.d(TAG, "VPN Log: $message")
                    // ส่งไป Flutter (ต้องอยู่บน UI thread)
                    runOnUiThread { logEventSink?.success(message) }
                }
            }

    /**
     * ==========================================================================
     * configureFlutterEngine — ตั้งค่า Platform Channels
     * ========================================================================== Logic: เรียกโดย
     * Flutter เมื่อ FlutterEngine พร้อมใช้งาน ตั้งค่า 2 channels:
     *
     * 1. MethodChannel → รับคำสั่งจาก Flutter
     * ```
     *      - "startVpn"     → เปิด VPN (ขอ permission ถ้ายังไม่มี)
     *      - "stopVpn"      → ปิด VPN
     *      - "isVpnRunning" → ตรวจสอบสถานะ VPN
     * ```
     * 2. EventChannel → ส่ง log stream ไป Flutter
     * ```
     *      - onListen  → Flutter เริ่มฟัง → เก็บ EventSink ไว้ใช้
     *      - onCancel  → Flutter หยุดฟัง → ล้าง EventSink
     * ```
     * เอาไว้: เป็น "สัญญา" ระหว่าง Flutter และ Kotlin ว่าจะสื่อสารผ่าน
     * ```
     *         channel ไหน ด้วย method ชื่ออะไร
     * ```
     * ==========================================================================
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // --- MethodChannel: รับคำสั่ง Start/Stop VPN จาก Flutter ---
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VPN_CHANNEL)
                .setMethodCallHandler { call, result ->
                    when (call.method) {
                        "startVpn" -> startVpnService(result)
                        "stopVpn" -> stopVpnService(result)
                        "isVpnRunning" -> result.success(MyVpnService.isRunning.get())
                        else -> result.notImplemented()
                    }
                }

        // --- EventChannel: Stream log จาก VPN ไป Flutter ---
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, LOG_CHANNEL)
                .setStreamHandler(
                        object : EventChannel.StreamHandler {
                            override fun onListen(
                                    arguments: Any?,
                                    events: EventChannel.EventSink?
                            ) {
                                logEventSink = events // เก็บ EventSink ไว้ส่ง log ภายหลัง
                                Log.d(TAG, "Log EventChannel connected")
                            }

                            override fun onCancel(arguments: Any?) {
                                logEventSink = null // Flutter หยุด listen → ล้าง reference
                                Log.d(TAG, "Log EventChannel disconnected")
                            }
                        }
                )
    }

    /**
     * ========================================================================== onCreate —
     * เรียกเมื่อ Activity ถูกสร้าง
     * ========================================================================== Logic:
     * 1. ลงทะเบียน BroadcastReceiver เพื่อรับ log จาก MyVpnService
     * 2. ใช้ RECEIVER_NOT_EXPORTED สำหรับ Android 13+ (Tiramisu)
     * ```
     *      เพื่อความปลอดภัย — รับได้เฉพาะ broadcast จากภายในแอปเท่านั้น
     * ```
     * เอาไว้: เตรียมรับ log จาก VPN Service ตั้งแต่เปิดแอป
     * ==========================================================================
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // ลงทะเบียน receiver สำหรับรับ VPN logs
        val filter = IntentFilter(MyVpnService.ACTION_LOG)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Android 13+ ต้องระบุ flag ว่า receiver ไม่รับ broadcast จากแอปอื่น
            registerReceiver(vpnLogReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(vpnLogReceiver, filter)
        }
        Log.d(TAG, "VPN log receiver registered")
    }

    /**
     * ========================================================================== startVpnService —
     * เริ่มต้น VPN Service
     * ========================================================================== Logic:
     * 1. เรียก VpnService.prepare(this) เพื่อเช็ค VPN permission
     * ```
     *      - ถ้า return Intent (ไม่ null) → user ยังไม่อนุญาต
     *        → แสดง system dialog ขอ permission (startActivityForResult)
     *        → เก็บ Result ไว้ใน pendingResult รอตอบ Flutter ทีหลัง
     *      - ถ้า return null → permission อนุญาตแล้ว
     *        → เปิด VPN ทันที (launchVpn)
     *        → ตอบ Flutter ว่า "VPN started"
     * ```
     * เอาไว้: เรียกจาก MethodChannel เมื่อ Flutter สั่ง startVpn
     * ==========================================================================
     */
    private fun startVpnService(result: MethodChannel.Result) {
        val intent = VpnService.prepare(this)
        if (intent != null) {
            // VPN permission ยังไม่ได้ → แสดง dialog ให้ user อนุญาต
            pendingResult = result
            startActivityForResult(intent, VPN_REQUEST_CODE)
        } else {
            // Permission อนุญาตแล้ว → เปิด VPN ทันที
            launchVpn()
            result.success("VPN started")
        }
    }

    /**
     * ========================================================================== stopVpnService —
     * หยุด VPN Service ==========================================================================
     * Logic:
     * 1. สร้าง Intent ชี้ไปที่ MyVpnService
     * 2. เรียก stopService → trigger MyVpnService.onDestroy()
     * ```
     *      → stopVpn() → ปิด TUN interface + หยุด packet loop
     * ```
     * 3. ตอบ Flutter ว่า "VPN stopped" เอาไว้: เรียกจาก MethodChannel เมื่อ Flutter สั่ง stopVpn
     * ==========================================================================
     */
    private fun stopVpnService(result: MethodChannel.Result) {
        val intent = Intent(this, MyVpnService::class.java)
        stopService(intent)
        result.success("VPN stopped")
        Log.d(TAG, "VPN service stop requested")
    }

    /**
     * ========================================================================== launchVpn —
     * สั่งเปิด MyVpnService
     * ========================================================================== Logic: สร้าง
     * Intent แล้วเรียก startService → Android จะ instantiate MyVpnService แล้วเรียก
     * onStartCommand() → MyVpnService จะสร้าง TUN interface และเริ่ม packet processing เอาไว้:
     * helper method แยกออกมาเพื่อเรียกจากทั้ง startVpnService
     * ```
     *         และ onActivityResult
     * ```
     * ==========================================================================
     */
    private fun launchVpn() {
        val intent = Intent(this, MyVpnService::class.java)
        startService(intent)
        Log.d(TAG, "VPN service started")
    }

    /**
     * ========================================================================== onActivityResult —
     * รับผลลัพธ์จาก VPN Permission Dialog
     * ========================================================================== Logic:
     * 1. เช็คว่า requestCode ตรงกับ VPN_REQUEST_CODE หรือไม่
     * 2. ถ้า user กด OK (RESULT_OK):
     * ```
     *      → เปิด VPN (launchVpn)
     *      → ตอบ Flutter ว่า "VPN started" (ผ่าน pendingResult)
     * ```
     * 3. ถ้า user กด Cancel:
     * ```
     *      → ตอบ Flutter ว่า error "VPN_DENIED"
     *      → Flutter จะ reset toggle กลับเป็น false
     * ```
     * 4. ล้าง pendingResult เพื่อป้องกัน memory leak เอาไว้: handle ผลลัพธ์จาก VPN permission
     * dialog ของระบบ ==========================================================================
     */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == VPN_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                // User อนุญาต → เปิด VPN
                launchVpn()
                pendingResult?.success("VPN started")
            } else {
                // User ไม่อนุญาต → ส่ง error กลับ Flutter
                pendingResult?.error("VPN_DENIED", "User denied VPN permission", null)
            }
            pendingResult = null // ล้าง reference
        }
    }

    /**
     * ========================================================================== onDestroy —
     * เรียกเมื่อ Activity ถูกทำลาย
     * ========================================================================== Logic:
     * ยกเลิกการลงทะเบียน BroadcastReceiver เพื่อป้องกัน memory leak try-catch เพราะอาจ unregister
     * ซ้ำ (receiver ไม่ได้ register) เอาไว้: cleanup resources เมื่อปิดแอป
     * ==========================================================================
     */
    override fun onDestroy() {
        super.onDestroy()
        try {
            unregisterReceiver(vpnLogReceiver)
        } catch (e: Exception) {
            Log.w(TAG, "Receiver not registered: ${e.message}")
        }
    }
}
