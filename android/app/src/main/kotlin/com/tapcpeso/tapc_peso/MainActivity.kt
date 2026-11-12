package com.tapcpeso.tapc_peso

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.nfc.NfcAdapter
import android.nfc.tech.IsoDep
import android.nfc.cardemulation.CardEmulation
import android.content.ComponentName
import android.content.pm.PackageManager
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterFragmentActivity() {
    private val adapter: NfcAdapter? get() = NfcAdapter.getDefaultAdapter(this)
    @Volatile private var pending: MethodChannel.Result? = null
    private val connecting = AtomicBoolean(false)
    private val worker = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tapcpeso/nfc").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "capabilities" -> result.success(mapOf("reader" to (adapter != null),
                        "sender" to packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION),
                        "enabled" to (adapter?.isEnabled == true)))
                    "offer" -> {
                        val nfc = adapter
                        val payload = (call.arguments as? String)?.toByteArray(Charsets.UTF_8)
                        require(nfc?.isEnabled == true) { "Enable NFC first." }
                        require(packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION)) { "HCE unavailable." }
                        require(payload != null && payload.size in 1..4096) { "Invalid payload size." }
                        stopNfc()
                        val emulation = CardEmulation.getInstance(nfc)
                        require(emulation.setPreferredService(this, ComponentName(this, WalletCardService::class.java))) {
                            "Could not route NFC to TapCPeso. Close other NFC apps and retry."
                        }
                        WalletCardService.offeredPayload = payload
                        result.success(null)
                    }
                    "read" -> {
                        val nfc = adapter
                        require(nfc?.isEnabled == true) { "Enable NFC first." }
                        require(pending == null) { "NFC reader already active." }
                        WalletCardService.offeredPayload = null
                        if (packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION)) {
                            CardEmulation.getInstance(nfc).unsetPreferredService(this)
                        }
                        pending = result
                        connecting.set(false)
                        nfc!!.enableReaderMode(this, { tag ->
                            if (connecting.compareAndSet(false, true)) {
                                val session = pending
                                worker.execute {
                                    try {
                                        val iso = IsoDep.get(tag) ?: error("Not a TapCPeso ISO-DEP sender.")
                                        val text = try {
                                            iso.connect(); iso.timeout = 5000
                                            val header = checked(iso.transceive(WalletCardService.select))
                                            require(header.size == 2) { "Bad payment header." }
                                            val length = ((header[0].toInt() and 255) shl 8) or (header[1].toInt() and 255)
                                            require(length in 1..4096) { "Bad payment size." }
                                            val out = ByteArrayOutputStream()
                                            while (out.size() < length) {
                                                val offset = out.size()
                                                val count = minOf(192, length - offset)
                                                val bytes = checked(iso.transceive(byteArrayOf(0x00, 0xB0.toByte(),
                                                    (offset shr 8).toByte(), offset.toByte(), count.toByte())))
                                                require(bytes.size == count) { "Incomplete NFC transfer." }
                                                out.write(bytes)
                                            }
                                            out.toByteArray().toString(Charsets.UTF_8)
                                        } finally { try { iso.close() } catch (_: Exception) {} }
                                        runOnUiThread { if (pending === session && session != null) {
                                            pending = null; adapter?.disableReaderMode(this); session.success(text)
                                        } }
                                    } catch (e: Exception) {
                                        runOnUiThread { if (pending === session && session != null) {
                                            pending = null; adapter?.disableReaderMode(this)
                                            session.error("NFC_READ", e.message, null)
                                        } }
                                    } finally { connecting.set(false) }
                                }
                            }
                        }, NfcAdapter.FLAG_READER_NFC_A or NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK, null)
                    }
                    "stop" -> { stopNfc(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                if (pending === result) pending = null
                result.error("NFC_UNAVAILABLE", e.message, null)
            }
        }
    }
    private fun checked(response: ByteArray): ByteArray {
        require(response.size >= 2 && response[response.size - 2] == 0x90.toByte() && response.last() == 0.toByte()) {
            "Sender not ready. Open the payment and start real NFC on the sender."
        }
        return response.copyOfRange(0, response.size - 2)
    }
    private fun stopNfc() {
        WalletCardService.offeredPayload = null
        adapter?.let { nfc ->
            nfc.disableReaderMode(this)
            if (packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION)) {
                CardEmulation.getInstance(nfc).unsetPreferredService(this)
            }
        }
        val result = pending; pending = null
        result?.error("NFC_CANCELLED", "NFC session stopped.", null)
    }
    override fun onPause() { stopNfc(); super.onPause() }
    override fun onDestroy() { worker.shutdownNow(); super.onDestroy() }
}
