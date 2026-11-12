package com.tapcpeso.tapc_peso

import android.nfc.cardemulation.HostApduService
import android.os.Bundle

/** Custom demo ISO-DEP protocol. It is unrelated to EMV or bank card payments. */
class WalletCardService : HostApduService() {
    companion object {
        @Volatile var offeredPayload: ByteArray? = null
        val aid = byteArrayOf(0xF0.toByte(), 0x54, 0x41, 0x50, 0x43, 0x50, 0x45, 0x53, 0x4F, 0x01)
        val select = byteArrayOf(0x00, 0xA4.toByte(), 0x04, 0x00, aid.size.toByte()) + aid + byteArrayOf(0x00)
        val ok = byteArrayOf(0x90.toByte(), 0x00)
    }
    private var selected: ByteArray? = null
    override fun processCommandApdu(command: ByteArray, extras: Bundle?): ByteArray {
        // Core NFC discovery may SELECT without the optional trailing Le byte.
        if (command.contentEquals(select) || command.contentEquals(select.copyOf(select.size - 1))) {
            val data = offeredPayload ?: return byteArrayOf(0x69, 0x85.toByte())
            selected = data
            return byteArrayOf((data.size shr 8).toByte(), data.size.toByte()) + ok
        }
        val data = selected ?: return byteArrayOf(0x69, 0x85.toByte())
        // A stopped or backgrounded offer cannot continue serving an old snapshot.
        if (offeredPayload !== data) return byteArrayOf(0x69, 0x85.toByte())
        if (command.size != 5 || command[0] != 0.toByte() || command[1] != 0xB0.toByte()) {
            return byteArrayOf(0x6D, 0x00)
        }
        val offset = ((command[2].toInt() and 255) shl 8) or (command[3].toInt() and 255)
        val count = command[4].toInt() and 255
        if (offset >= data.size || count !in 1..192) return byteArrayOf(0x6B, 0x00)
        return data.copyOfRange(offset, minOf(offset + count, data.size)) + ok
    }
    override fun onDeactivated(reason: Int) { selected = null }
}
