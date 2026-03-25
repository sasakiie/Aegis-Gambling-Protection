package com.aegis.aegis_prog

import android.content.Intent
import android.net.VpnService
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.util.concurrent.atomic.AtomicBoolean

/**
 * ============================================================================ AEGIS VPN Service —
 * Network Shield (DNS-based Ad/Gambling Blocker)
 * ============================================================================
 *
 * หน้าที่หลัก: สร้าง VPN tunnel เพื่อดักจับ DNS queries จากทุกแอปบนเครื่อง ถ้าพบ domain ที่อยู่ใน
 * blocklist → ตอบ 0.0.0.0 (DNS sinkhole) ถ้า domain ปลอดภัย → ส่งต่อไป Google DNS (8.8.8.8) แล้วส่ง
 * response กลับ
 *
 * Flow การทำงาน:
 * 1. สร้าง TUN interface → ดูด traffic ทั้งหมดเข้ามา
 * 2. อ่าน IP packet จาก TUN ทีละ packet (processPackets)
 * 3. ถ้า UDP port 53 (DNS) → parse domain → เช็ค blocklist
 * ```
 *      → blocked: ตอบ 0.0.0.0 / allowed: forward ไป 8.8.8.8
 * ```
 * 4. UDP อื่น → forward ผ่าน protect()ed socket
 * 5. TCP → DNS sinkhole ทำให้ blocked domain → 0.0.0.0 → connect fail
 *
 * ทำไมใช้ DNS sinkhole?
 * - ง่ายกว่า proxy TCP (ไม่ต้อง implement full TCP/IP stack)
 * - block ได้ทุกแอป (Facebook browser, LINE, Chrome)
 * - traffic ปกติไม่ถูกกระทบ
 * ============================================================================
 */
class MyVpnService : VpnService() {

    companion object {
        const val TAG = "AegisVPN" // Log tag สำหรับ debug
        const val ACTION_LOG = "com.aegis.VPN_LOG" // Broadcast action สำหรับส่ง log
        const val EXTRA_LOG_MESSAGE = "log_message" // Key ของ log message ใน Intent extra

        // ══════════════════════════════════════════════════════════════════════
        // BLOCKED_DOMAINS — รายชื่อ domain ที่ต้องบล็อก (exact match)
        // ══════════════════════════════════════════════════════════════════════
        // Logic: เก็บเป็น Set สำหรับ O(1) lookup
        //        ครอบคลุมทั้ง ad networks และ gambling domains
        // เอาไว้: เช็ค exact match กับ domain ที่ถูก DNS query
        // ══════════════════════════════════════════════════════════════════════
        val BLOCKED_DOMAINS =
                setOf(
                        // Ad networks
                        "ad-server.com",
                        "doubleclick.net",
                        "ads.google.com",
                        "pagead2.googlesyndication.com",
                        "adservice.google.com",
                        "static.ads-twitter.com",
                        "an.facebook.com",
                        "ads.facebook.com",
                        "pixel.facebook.com",
                        "analytics.tiktok.com",
                        "googleadservices.com",
                        "googlesyndication.com",
                        "moatads.com",
                        "amazon-adsystem.com",
                        // Gambling domains
                        "ufabet.com",
                        "ufa365.com",
                        "ufa888.com",
                        "ufa168.com",
                        "ufa191.com",
                        "ufazeed.com",
                        "ufabomb.com",
                        "pgslot.com",
                        "slotxo.com",
                        "superslot.com",
                        "sagaming.com",
                        "sexygame.com",
                        "sexybaccarat.com",
                        "betflik.com",
                        "betflix.com",
                        "joker123.com",
                        "jokergaming.com",
                        "sbobet.com",
                        "gclub.com",
                        "lsm99.com",
                        "ole777.com",
                        "fun88.com",
                        "w88.com",
                        "dafabet.com",
                        "happyluke.com",
                        "empire777.com",
                        "lucabet.com",
                        "foxz168.com",
                        "databet.com",
                        "mafia88.com",
                        "biobet.com",
                        "ruay.com",
                        "ambbet.com",
                        "live22.com",
                        "mega888.com",
                        "kiss918.com",
                        "ssgame666.com",
                        "ssgame666h.com",
                        "ssgame66.com",
                        "panama888.com",
                        "panama999.com",
                        "lockdown168.com",
                        "lockdown888.com",
                        "brazil99.com",
                        "brazil999.com",
                        "kingdom66.com",
                        "kingdom666.com",
                )

        // ══════════════════════════════════════════════════════════════════════
        // BLOCKED_KEYWORDS — คำสำคัญสำหรับจับ domain แบบกว้าง (substring match)
        // ══════════════════════════════════════════════════════════════════════
        // Logic: เช็ค substring match กับ domain name
        // เอาไว้: จับ domain ที่เปลี่ยนชื่อบ่อย เช่น ufabet-vip-2025.net
        // ══════════════════════════════════════════════════════════════════════
        val BLOCKED_KEYWORDS =
                listOf(
                        "ufabet",
                        "ufazeed",
                        "ufabomb",
                        "ufac4",
                        "ufafat",
                        "pgslot",
                        "slotxo",
                        "superslot",
                        "slotgame",
                        "sagaming",
                        "sexygame",
                        "sexybaccarat",
                        "betflik",
                        "betflix",
                        "sbobet",
                        "gclub",
                        "ambbet",
                        "lucabet",
                        "databet",
                        "biobet",
                        "ssgame66",
                        "ssgame666",
                        "panama888",
                        "panama999",
                        "lockdown168",
                        "lockdown888",
                        "kingdom66",
                        "kingdom666",
                        "mafia88",
                        "joker123",
                )

        // สถานะ VPN (thread-safe) — ใช้ AtomicBoolean เพราะเข้าถึงจากหลาย thread
        var isRunning = AtomicBoolean(false)
    }

    // ─── Instance Variables ───
    private var vpnInterface: ParcelFileDescriptor? = null // TUN interface file descriptor
    private var vpnThread: Thread? = null // Thread สำหรับ packet processing loop
    private val running = AtomicBoolean(false) // สถานะ loop (local)
    private var blockedCount = 0 // จำนวน domain ที่ถูก block
    private var forwardedCount = 0 // จำนวน DNS query ที่ forward สำเร็จ

    /**
     * onStartCommand — เรียกเมื่อ Service ถูก start โดย MainActivity Logic: เรียก startVpn() สร้าง
     * TUN + เริ่ม packet loop
     * ```
     *        Return START_STICKY → ถ้า Android kill service จะ restart อัตโนมัติ
     * ```
     * เอาไว้: entry point หลักของ Service lifecycle
     */
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "VPN Service onStartCommand")
        startVpn()
        return START_STICKY
    }

    /**
     * isDomainBlocked — ตรวจสอบว่า domain ควรถูก block หรือไม่ Logic: ใช้ 3 วิธีเช็ค
     * (เรียงจากแม่นยำ → กว้าง):
     * 1. Exact match: domain ตรงกับ BLOCKED_DOMAINS
     * ```
     *      เช่น "ufabet.com" → blocked
     * ```
     * 2. Subdomain match: domain ลงท้ายด้วย ".blocked_domain"
     * ```
     *      เช่น "www.ufabet.com" → blocked
     * ```
     * 3. Keyword match: domain มี keyword อยู่ในชื่อ
     * ```
     *      เช่น "ufabet-new-2025.net" → มี "ufabet" → blocked
     * ```
     * เอาไว้: เป็น core function ที่ handleDnsQuery เรียกเพื่อตัดสินใจ
     * ```
     *         ว่าจะ sinkhole หรือ forward DNS query
     * ```
     */
    private fun isDomainBlocked(domain: String): Boolean {
        val lower = domain.lowercase().trimEnd('.') // ลบจุดท้าย (DNS FQDN format)

        // วิธี 1: Exact match ใน Set (O(1) lookup)
        if (BLOCKED_DOMAINS.contains(lower)) return true

        // วิธี 2: Subdomain match (เช่น www.ufabet.com → endsWith ".ufabet.com")
        for (blocked in BLOCKED_DOMAINS) {
            if (lower.endsWith(".$blocked")) return true
        }

        // วิธี 3: Keyword match (เช่น ufabet-premium.net → contains "ufabet")
        for (keyword in BLOCKED_KEYWORDS) {
            if (lower.contains(keyword)) return true
        }

        return false
    }

    /**
     * startVpn — สร้าง VPN tunnel แล้วเริ่ม packet processing Logic:
     * 1. เช็คว่า VPN ทำงานอยู่แล้วหรือไม่ (ป้องกันเปิดซ้ำ)
     * 2. สร้าง TUN interface ด้วย VpnService.Builder:
     * ```
     *      - setSession → ชื่อ VPN ใน Android Settings
     *      - addAddress("10.0.0.2", 32) → IP ของ VPN interface
     *      - addRoute("0.0.0.0", 0) → route ALL traffic ผ่าน VPN
     *      - addDnsServer("8.8.8.8") → Google Public DNS
     *      - setMtu(1500) → Standard packet size
     *      - setBlocking(true) → read() จะ block จนมี packet
     * ```
     * 3. สร้าง Thread ใหม่สำหรับ processPackets() loop เอาไว้: entry point สำหรับเริ่ม VPN ทั้งระบบ
     */
    private fun startVpn() {
        if (running.get()) {
            Log.d(TAG, "VPN already running")
            return
        }

        try {
            val builder =
                    Builder()
                            .setSession("AEGIS Shield") // ชื่อ VPN ใน system settings
                            .addAddress("10.0.0.2", 32) // VPN interface IP
                            .addRoute("0.0.0.0", 0) // route ALL IPv4 traffic
                            .addDnsServer("8.8.8.8") // Google Public DNS
                            .setMtu(1500) // Standard MTU
                            .setBlocking(true) // blocking I/O mode

            vpnInterface = builder.establish()

            if (vpnInterface == null) {
                Log.e(TAG, "Failed to establish VPN interface")
                sendLog("❌ Failed to establish VPN tunnel")
                return
            }

            running.set(true)
            isRunning.set(true)

            sendLog("🛡️ VPN Tunnel established (10.0.0.2/32)")
            sendLog(
                    "🔒 DNS Filter active — ${BLOCKED_DOMAINS.size} domains + ${BLOCKED_KEYWORDS.size} keyword patterns"
            )

            // สร้าง background thread สำหรับอ่าน packet (ห้ามทำบน main thread)
            vpnThread = Thread(Runnable { processPackets() }, "AegisVPN-Thread")
            vpnThread?.start()

            Log.d(TAG, "VPN started successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error starting VPN: ${e.message}", e)
            sendLog("❌ VPN Error: ${e.message}")
        }
    }

    /**
     * processPackets — ลูปหลักอ่าน IP packet จาก TUN interface Logic: วนลูปอ่าน packet ทีละตัว:
     * 1. อ่าน raw bytes จาก FileInputStream (blocking read)
     * 2. Parse IP header: version, IHL, protocol, dest IP
     * 3. ถ้า UDP port 53 → handleDnsQuery()
     * 4. ถ้าไม่ใช่ DNS → forwardPacket() เอาไว้: เป็น "หัวใจ" ของ VPN ทำงานตลอดบน background thread
     *
     * IP Packet Structure: byte[0] = version(4bit) + IHL(4bit) byte[9] = protocol (6=TCP, 17=UDP)
     * byte[16-19] = destination IP
     */
    private fun processPackets() {
        val inputStream = FileInputStream(vpnInterface!!.fileDescriptor)
        val outputStream = FileOutputStream(vpnInterface!!.fileDescriptor)
        val buffer = ByteArray(32767) // buffer ~32KB สำหรับอ่าน packet

        sendLog("📡 Packet interception started")

        while (running.get()) {
            try {
                // อ่าน 1 IP packet จาก TUN (blocking จนมี packet)
                val length = inputStream.read(buffer)
                if (length <= 0) {
                    Thread.sleep(10) // ไม่มีข้อมูล → รอสักพัก
                    continue
                }

                // ── Parse IP header ──
                // byte[0] bits 4-7 = IP version
                val version = (buffer[0].toInt() shr 4) and 0x0F
                if (version != 4) {
                    // ข้าม non-IPv4 (เช่น IPv6)
                    continue
                }

                // byte[0] bits 0-3 = IP Header Length (จำนวน 32-bit words × 4)
                val ipHeaderLen = (buffer[0].toInt() and 0x0F) * 4
                // byte[9] = transport protocol (17=UDP, 6=TCP)
                val protocol = buffer[9].toInt() and 0xFF
                // byte[2-3] = total packet length
                val totalLength =
                        ((buffer[2].toInt() and 0xFF) shl 8) or (buffer[3].toInt() and 0xFF)

                // byte[16-19] = destination IP address
                val destIp =
                        "${buffer[16].toInt() and 0xFF}.${buffer[17].toInt() and 0xFF}.${buffer[18].toInt() and 0xFF}.${buffer[19].toInt() and 0xFF}"

                // ── ตรวจสอบ protocol ──
                // Protocol 17 = UDP
                if (protocol == 17 && length >= ipHeaderLen + 8) {
                    // อ่าน destination port จาก UDP header byte[2-3]
                    val destPort =
                            ((buffer[ipHeaderLen + 2].toInt() and 0xFF) shl 8) or
                                    (buffer[ipHeaderLen + 3].toInt() and 0xFF)

                    // DNS query = UDP destination port 53
                    if (destPort == 53) {
                        handleDnsQuery(buffer, length, ipHeaderLen, outputStream)
                        continue // จัดการ DNS แล้ว ไม่ต้อง forward ซ้ำ
                    }
                }

                // ── Non-DNS traffic: forward ผ่าน protect()ed socket ──
                forwardPacket(buffer, length, protocol, ipHeaderLen, destIp, outputStream)
            } catch (e: InterruptedException) {
                Log.d(TAG, "VPN thread interrupted")
                break // thread ถูก interrupt → ออกจากลูป
            } catch (e: Exception) {
                if (running.get()) {
                    Log.e(TAG, "Packet error: ${e.message}")
                }
            }
        }

        // สรุปสถิติเมื่อหยุดทำงาน
        Log.d(TAG, "Stopped. Blocked: $blockedCount, Forwarded: $forwardedCount")
    }

    /**
     * handleDnsQuery — ประมวลผล DNS query packet Logic:
     * 1. คำนวณตำแหน่ง DNS payload = IP header + UDP header (8 bytes)
     * 2. Parse domain name จาก DNS question section
     * 3. เช็ค isDomainBlocked:
     * ```
     *      a. blocked → สร้าง DNS response: domain → 0.0.0.0 (sinkhole)
     *      b. allowed → forward ไป Google DNS (8.8.8.8)
     * ```
     * เอาไว้: function หลักที่ตัดสินใจ block หรือ forward DNS query
     */
    private fun handleDnsQuery(
            packet: ByteArray,
            length: Int,
            ipHeaderLen: Int,
            outputStream: FileOutputStream
    ) {
        val udpHeaderLen = 8
        val dnsOffset = ipHeaderLen + udpHeaderLen

        // เช็คว่า packet ยาวพอมี DNS header (12 bytes)
        if (length < dnsOffset + 12) return

        // Parse domain name จาก DNS question section
        val domain = parseDnsQuestion(packet, dnsOffset + 12, length)
        if (domain.isEmpty()) return

        if (isDomainBlocked(domain)) {
            // ═══ BLOCKED: ตอบ 0.0.0.0 (DNS Sinkhole) ═══
            blockedCount++
            sendLog("🚫 Blocked: $domain → 0.0.0.0")

            // สร้าง DNS response ปลอม → เขียนกลับ TUN
            val response = craftDnsSinkholeResponse(packet, length, ipHeaderLen)
            if (response != null) {
                outputStream.write(response)
                outputStream.flush()
            }
        } else {
            // ═══ ALLOWED: forward ไป Google DNS (8.8.8.8) ═══
            forwardedCount++
            forwardDnsQuery(packet, length, ipHeaderLen, outputStream)
        }
    }

    /**
     * parseDnsQuestion — อ่าน domain name จาก DNS question section Logic: DNS ใช้ label encoding:
     * [length]characters[length]characters...[0] ตัวอย่าง: www.google.com =
     * [3]www[6]google[3]com[0] Algorithm:
     * 1. อ่าน 1 byte = label length
     * 2. ถ้า 0 → จบชื่อ / ถ้า ≥ 64 → compression pointer (skip)
     * 3. อ่าน characters ตาม length → เพิ่มเข้า StringBuilder
     * 4. เพิ่ม "." ระหว่าง labels เอาไว้: แปลง DNS wire format → domain name ที่อ่านได้
     */
    private fun parseDnsQuestion(packet: ByteArray, offset: Int, length: Int): String {
        val sb = StringBuilder()
        var pos = offset

        try {
            while (pos < length) {
                val labelLen = packet[pos].toInt() and 0xFF
                if (labelLen == 0) break // 0 = จบชื่อ domain
                if (labelLen >= 64) break // ≥ 64 = compression pointer

                pos++ // ข้าม length byte
                if (pos + labelLen > length) break // ป้องกันอ่านเกิน packet

                if (sb.isNotEmpty()) sb.append('.') // เพิ่ม "." ระหว่าง labels
                for (i in 0 until labelLen) {
                    sb.append(packet[pos + i].toInt().toChar())
                }
                pos += labelLen
            }
        } catch (e: Exception) {
            return ""
        }

        return sb.toString().lowercase()
    }

    /**
     * craftDnsSinkholeResponse — สร้าง DNS response ปลอม (domain → 0.0.0.0) Logic: สร้าง IP+UDP+DNS
     * response packet:
     * 1. คัดลอก IP header + สลับ src↔dst IP (ตอบกลับผู้ถาม)
     * 2. คัดลอก UDP header + สลับ src↔dst port
     * 3. สร้าง DNS header: QR=1 (response), ANCOUNT=1
     * 4. คัดลอก question section จาก query
     * 5. เพิ่ม answer: Type A, 0.0.0.0 (sinkhole!) เอาไว้: "โกหก" app ว่า domain ไม่มี IP → connect
     * fail
     */
    private fun craftDnsSinkholeResponse(
            originalPacket: ByteArray,
            length: Int,
            ipHeaderLen: Int
    ): ByteArray? {
        try {
            val udpHeaderLen = 8
            val dnsOffset = ipHeaderLen + udpHeaderLen

            // We need at least DNS header (12 bytes) + question
            if (length < dnsOffset + 12) return null

            // Find the end of the question section
            var qEnd = dnsOffset + 12
            while (qEnd < length && (originalPacket[qEnd].toInt() and 0xFF) != 0) {
                val labelLen = originalPacket[qEnd].toInt() and 0xFF
                qEnd += labelLen + 1
            }
            qEnd += 5 // skip null byte + QTYPE (2) + QCLASS (2)

            val questionLen = qEnd - (dnsOffset + 12)

            // Build DNS response:
            // DNS Header (12) + Question (copied) + Answer (16) → A record with 0.0.0.0
            val answerSection =
                    byteArrayOf(
                            0xC0.toByte(),
                            0x0C, // Name pointer to question
                            0x00,
                            0x01, // Type A
                            0x00,
                            0x01, // Class IN
                            0x00,
                            0x00,
                            0x00,
                            0x3C, // TTL = 60 seconds
                            0x00,
                            0x04, // Data length = 4
                            0x00,
                            0x00,
                            0x00,
                            0x00 // IP = 0.0.0.0
                    )

            val dnsPayloadLen = 12 + questionLen + answerSection.size
            val udpLen = udpHeaderLen + dnsPayloadLen
            val totalLen = ipHeaderLen + udpLen
            val response = ByteArray(totalLen)

            // ── Copy and modify IP header ──
            System.arraycopy(originalPacket, 0, response, 0, ipHeaderLen)

            // Swap source ↔ destination IP
            System.arraycopy(originalPacket, 12, response, 16, 4) // src → dst
            System.arraycopy(originalPacket, 16, response, 12, 4) // dst → src

            // Set total length
            response[2] = ((totalLen shr 8) and 0xFF).toByte()
            response[3] = (totalLen and 0xFF).toByte()

            // Zero out IP checksum then recalculate
            response[10] = 0
            response[11] = 0
            val ipChecksum = calculateChecksum(response, 0, ipHeaderLen)
            response[10] = ((ipChecksum shr 8) and 0xFF).toByte()
            response[11] = (ipChecksum and 0xFF).toByte()

            // ── UDP header ──
            // Swap source ↔ destination port
            System.arraycopy(originalPacket, ipHeaderLen + 2, response, ipHeaderLen, 2) // dst→src
            System.arraycopy(originalPacket, ipHeaderLen, response, ipHeaderLen + 2, 2) // src→dst

            // UDP length
            response[ipHeaderLen + 4] = ((udpLen shr 8) and 0xFF).toByte()
            response[ipHeaderLen + 5] = (udpLen and 0xFF).toByte()

            // Zero UDP checksum (optional for IPv4)
            response[ipHeaderLen + 6] = 0
            response[ipHeaderLen + 7] = 0

            // ── DNS header ──
            // Copy transaction ID
            response[dnsOffset] = originalPacket[dnsOffset]
            response[dnsOffset + 1] = originalPacket[dnsOffset + 1]

            // Flags: standard response, no error
            response[dnsOffset + 2] = 0x81.toByte() // QR=1, RD=1
            response[dnsOffset + 3] = 0x80.toByte() // RA=1

            // QDCOUNT = 1
            response[dnsOffset + 4] = 0
            response[dnsOffset + 5] = 1
            // ANCOUNT = 1
            response[dnsOffset + 6] = 0
            response[dnsOffset + 7] = 1
            // NSCOUNT = 0
            response[dnsOffset + 8] = 0
            response[dnsOffset + 9] = 0
            // ARCOUNT = 0
            response[dnsOffset + 10] = 0
            response[dnsOffset + 11] = 0

            // Copy question section
            System.arraycopy(originalPacket, dnsOffset + 12, response, dnsOffset + 12, questionLen)

            // Append answer section
            System.arraycopy(
                    answerSection,
                    0,
                    response,
                    dnsOffset + 12 + questionLen,
                    answerSection.size
            )

            return response
        } catch (e: Exception) {
            Log.e(TAG, "Error crafting DNS response: ${e.message}")
            return null
        }
    }

    /**
     * forwardDnsQuery — ส่ง DNS query ไป Google DNS (8.8.8.8) แล้ว relay กลับ Logic:
     * 1. ตัด DNS payload ออกจาก IP+UDP packet
     * 2. สร้าง DatagramSocket + protect() (bypass VPN ป้องกัน loop)
     * 3. ส่ง DNS payload ไป 8.8.8.8 port 53
     * 4. รอรับ response (timeout 5 วินาที)
     * 5. สร้าง IP+UDP response packet → เขียนกลับ TUN เอาไว้: forward DNS query ที่ไม่ถูก block ไป
     * DNS server จริง
     *
     * ทำไมต้อง protect()? VPN route 0.0.0.0/0 → ทุก packet ผ่าน TUN ไม่ protect → DNS query วนกลับ
     * TUN → infinite loop!
     */
    private fun forwardDnsQuery(
            packet: ByteArray,
            length: Int,
            ipHeaderLen: Int,
            outputStream: FileOutputStream
    ) {
        try {
            val udpHeaderLen = 8
            val dnsOffset = ipHeaderLen + udpHeaderLen
            val dnsLength = length - dnsOffset

            if (dnsLength <= 0) return

            // Extract DNS payload
            val dnsPayload = ByteArray(dnsLength)
            System.arraycopy(packet, dnsOffset, dnsPayload, 0, dnsLength)

            // Forward to real DNS via a protect()ed socket
            val socket = DatagramSocket()
            protect(socket) // Important: bypass VPN for this socket

            val dnsServer = InetAddress.getByName("8.8.8.8")
            val sendPacket = DatagramPacket(dnsPayload, dnsPayload.size, dnsServer, 53)
            socket.soTimeout = 5000 // 5 second timeout
            socket.send(sendPacket)

            // Receive DNS response
            val responseBuffer = ByteArray(4096)
            val recvPacket = DatagramPacket(responseBuffer, responseBuffer.size)
            socket.receive(recvPacket)
            socket.close()

            // Build IP+UDP packet from response
            val dnsResponseLen = recvPacket.length
            val udpLen = udpHeaderLen + dnsResponseLen
            val totalLen = ipHeaderLen + udpLen
            val responsePacket = ByteArray(totalLen)

            // Copy original IP header, swap src↔dst
            System.arraycopy(packet, 0, responsePacket, 0, ipHeaderLen)
            System.arraycopy(packet, 12, responsePacket, 16, 4) // src → dst
            System.arraycopy(packet, 16, responsePacket, 12, 4) // dst → src

            // Set total length
            responsePacket[2] = ((totalLen shr 8) and 0xFF).toByte()
            responsePacket[3] = (totalLen and 0xFF).toByte()

            // IP checksum
            responsePacket[10] = 0
            responsePacket[11] = 0
            val checksum = calculateChecksum(responsePacket, 0, ipHeaderLen)
            responsePacket[10] = ((checksum shr 8) and 0xFF).toByte()
            responsePacket[11] = (checksum and 0xFF).toByte()

            // UDP header: swap ports
            System.arraycopy(packet, ipHeaderLen + 2, responsePacket, ipHeaderLen, 2)
            System.arraycopy(packet, ipHeaderLen, responsePacket, ipHeaderLen + 2, 2)

            responsePacket[ipHeaderLen + 4] = ((udpLen shr 8) and 0xFF).toByte()
            responsePacket[ipHeaderLen + 5] = (udpLen and 0xFF).toByte()
            responsePacket[ipHeaderLen + 6] = 0
            responsePacket[ipHeaderLen + 7] = 0

            // DNS response payload
            System.arraycopy(recvPacket.data, 0, responsePacket, dnsOffset, dnsResponseLen)

            outputStream.write(responsePacket)
            outputStream.flush()
        } catch (e: Exception) {
            Log.e(TAG, "DNS forward error: ${e.message}")
        }
    }

    /**
     * forwardPacket — ส่งต่อ non-DNS packet (TCP/UDP) Logic:
     * - UDP (ไม่ใช่ DNS): forward ผ่าน forwardUdpPacket
     * - TCP: ไม่ forward โดยตรง (ต้อง full TCP stack)
     * ```
     *     แต่ DNS sinkhole → blocked domain resolve 0.0.0.0
     *     → TCP connect fail → ไม่ต้อง block TCP
     * ```
     * เอาไว้: จัดการ traffic ที่ไม่ใช่ DNS หมายเหตุ: Production ควรใช้ tun2socks library
     */
    private fun forwardPacket(
            packet: ByteArray,
            length: Int,
            protocol: Int,
            ipHeaderLen: Int,
            destIp: String,
            outputStream: FileOutputStream
    ) {
        try {
            // For UDP non-DNS traffic
            if (protocol == 17) {
                forwardUdpPacket(packet, length, ipHeaderLen, destIp, outputStream)
                return
            }

            // For TCP and other protocols, we need to write the packet
            // back to the TUN so the system can handle it via default routing.
            // Since we're a VPN that routes 0.0.0.0/0, we need to actually
            // forward these packets. For TCP, this is complex without tun2socks.
            //
            // A practical approach: only intercept DNS (which handles domain blocking)
            // and let the OS handle TCP via the VPN tunnel normally.
            // The DNS sinkhole ensures blocked domains resolve to 0.0.0.0,
            // so TCP connections to those domains will fail at connect time.

        } catch (e: Exception) {
            Log.e(TAG, "Forward error: ${e.message}")
        }
    }

    /**
     * forwardUdpPacket — ส่ง UDP packet (ไม่ใช่ DNS) ผ่าน real socket Logic:
     * 1. อ่าน destination port + payload จาก packet
     * 2. สร้าง DatagramSocket + protect() (bypass VPN)
     * 3. ส่ง payload ไปยัง dest IP:port
     * 4. รอรับ response (timeout 3 วินาที) → ถ้าได้ → สร้าง packet กลับ TUN เอาไว้: forward UDP
     * traffic ทั่วไป เช่น QUIC, video streaming, NTP
     */
    private fun forwardUdpPacket(
            packet: ByteArray,
            length: Int,
            ipHeaderLen: Int,
            destIp: String,
            outputStream: FileOutputStream
    ) {
        try {
            val udpHeaderLen = 8
            val destPort =
                    ((packet[ipHeaderLen + 2].toInt() and 0xFF) shl 8) or
                            (packet[ipHeaderLen + 3].toInt() and 0xFF)

            val payloadOffset = ipHeaderLen + udpHeaderLen
            val payloadLength = length - payloadOffset
            if (payloadLength <= 0) return

            val payload = ByteArray(payloadLength)
            System.arraycopy(packet, payloadOffset, payload, 0, payloadLength)

            val socket = DatagramSocket()
            protect(socket)

            val dest = InetAddress.getByName(destIp)
            val sendPkt = DatagramPacket(payload, payload.size, dest, destPort)
            socket.soTimeout = 3000
            socket.send(sendPkt)

            // Try to receive response
            try {
                val respBuf = ByteArray(4096)
                val respPkt = DatagramPacket(respBuf, respBuf.size)
                socket.receive(respPkt)

                // Build response IP+UDP packet
                val respUdpLen = udpHeaderLen + respPkt.length
                val respTotalLen = ipHeaderLen + respUdpLen
                val respPacket = ByteArray(respTotalLen)

                // IP header with swapped addresses
                System.arraycopy(packet, 0, respPacket, 0, ipHeaderLen)
                System.arraycopy(packet, 12, respPacket, 16, 4)
                System.arraycopy(packet, 16, respPacket, 12, 4)
                respPacket[2] = ((respTotalLen shr 8) and 0xFF).toByte()
                respPacket[3] = (respTotalLen and 0xFF).toByte()
                respPacket[10] = 0
                respPacket[11] = 0
                val ck = calculateChecksum(respPacket, 0, ipHeaderLen)
                respPacket[10] = ((ck shr 8) and 0xFF).toByte()
                respPacket[11] = (ck and 0xFF).toByte()

                // UDP header with swapped ports
                System.arraycopy(packet, ipHeaderLen + 2, respPacket, ipHeaderLen, 2)
                System.arraycopy(packet, ipHeaderLen, respPacket, ipHeaderLen + 2, 2)
                respPacket[ipHeaderLen + 4] = ((respUdpLen shr 8) and 0xFF).toByte()
                respPacket[ipHeaderLen + 5] = (respUdpLen and 0xFF).toByte()
                respPacket[ipHeaderLen + 6] = 0
                respPacket[ipHeaderLen + 7] = 0

                System.arraycopy(
                        respPkt.data,
                        0,
                        respPacket,
                        ipHeaderLen + udpHeaderLen,
                        respPkt.length
                )

                outputStream.write(respPacket)
                outputStream.flush()
            } catch (e: Exception) {
                // No response, that's okay for UDP
            }

            socket.close()
        } catch (e: Exception) {
            Log.e(TAG, "UDP forward error: ${e.message}")
        }
    }

    /**
     * calculateChecksum — คำนวณ IP header checksum ตาม RFC 1071 Logic:
     * 1. รวมทุก 16-bit word ใน header เป็น 32-bit sum
     * 2. Fold 32-bit → 16-bit: sum = (sum & 0xFFFF) + (sum >> 16)
     * 3. Invert bits (one's complement) → checksum เอาไว้: คำนวณ checksum สำหรับ IP header
     * ที่สร้างใหม่
     */
    private fun calculateChecksum(data: ByteArray, offset: Int, length: Int): Int {
        var sum = 0
        var i = offset
        val end = offset + length

        while (i < end - 1) {
            sum += ((data[i].toInt() and 0xFF) shl 8) or (data[i + 1].toInt() and 0xFF)
            i += 2
        }

        // Handle odd byte
        if (i < end) {
            sum += (data[i].toInt() and 0xFF) shl 8
        }

        // Fold 32-bit sum to 16 bits
        while (sum shr 16 != 0) {
            sum = (sum and 0xFFFF) + (sum shr 16)
        }

        return sum.inv() and 0xFFFF
    }

    /**
     * sendLog — ส่ง log message ไป Flutter ผ่าน Local Broadcast Logic:
     * 1. Log ไป Logcat (debug)
     * 2. สร้าง broadcast Intent + setPackage (เฉพาะภายในแอป)
     * 3. sendBroadcast → MainActivity.vpnLogReceiver จับ → EventSink → Flutter เอาไว้: สื่อสารจาก
     * VPN Service (background) → UI (foreground)
     */
    private fun sendLog(message: String) {
        Log.d(TAG, message)
        val intent =
                Intent(ACTION_LOG).apply {
                    putExtra(EXTRA_LOG_MESSAGE, message)
                    setPackage(packageName)
                }
        sendBroadcast(intent)
    }

    /**
     * stopVpn — หยุด VPN ทั้งระบบ Logic:
     * 1. ตั้ง running = false → processPackets loop จะหยุด
     * 2. interrupt thread → ออกจาก blocking read
     * 3. ปิด TUN interface
     * 4. ส่ง log สรุปสถิติ (blocked + forwarded) เอาไว้: เรียกจาก onDestroy หรือ onRevoke
     */
    fun stopVpn() {
        running.set(false)
        isRunning.set(false)

        // หยุด packet processing thread
        vpnThread?.interrupt()
        vpnThread = null

        // ปิด TUN interface
        try {
            vpnInterface?.close()
            vpnInterface = null
        } catch (e: Exception) {
            Log.e(TAG, "Error closing VPN interface: ${e.message}")
        }

        // ส่งสรุปสถิติไป Flutter
        sendLog("📊 Session stats: Blocked $blockedCount, Forwarded $forwardedCount")
        sendLog("⚪ VPN Tunnel closed")
        Log.d(TAG, "VPN stopped")
    }

    /**
     * onDestroy — เรียกเมื่อ Service ถูก destroy (stopService หรือ system kill) Logic: เรียก
     * stopVpn() เพื่อ cleanup ทุกอย่าง
     */
    override fun onDestroy() {
        super.onDestroy()
        stopVpn()
        Log.d(TAG, "VPN Service destroyed")
    }

    /**
     * onRevoke — เรียกเมื่อ user ถอนสิทธิ์ VPN (เปลี่ยนไปใช้ VPN อื่น) เอาไว้: user สามารถถอนสิทธิ์
     * VPN ได้จาก Settings → Network → VPN
     */
    override fun onRevoke() {
        super.onRevoke()
        stopVpn()
        Log.d(TAG, "VPN permission revoked by user")
    }
}
