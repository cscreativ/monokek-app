package com.monokek.monokek_flutter

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Raw access to USB thermal printers (Xprinter & co) through UsbManager: list, ask permission, and write
 * ESC/POS bytes to the printer's bulk OUT endpoint. Devices are addressed by vendorId/productId.
 * Channel: "com.monokek.pos/usb_printer" — see lib/core/printing/usb_printer.dart.
 */
class UsbPrinterPlugin(private val context: Context) : MethodChannel.MethodCallHandler {

    private val usb = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "list" -> result.success(usb.deviceList.values.map(::describe))
            "requestPermission" -> requestPermission(find(call), result)
            "write" -> write(find(call), call.argument<ByteArray>("data"), result)
            else -> result.notImplemented()
        }
    }

    private fun find(call: MethodCall): UsbDevice? {
        val vid = call.argument<Int>("vendorId")
        val pid = call.argument<Int>("productId")
        return usb.deviceList.values.firstOrNull { it.vendorId == vid && it.productId == pid }
    }

    private fun describe(d: UsbDevice): Map<String, Any> = mapOf(
        "vendorId" to d.vendorId,
        "productId" to d.productId,
        "name" to (d.productName ?: d.deviceName),
        "isPrinter" to (0 until d.interfaceCount).any { d.getInterface(it).interfaceClass == UsbConstants.USB_CLASS_PRINTER },
    )

    private fun requestPermission(device: UsbDevice?, result: MethodChannel.Result) {
        if (device == null) return result.error("no_device", "Imprimante USB introuvable (débranchée ?)", null)
        if (usb.hasPermission(device)) return result.success(true)

        val action = "$ACTION_PERMISSION.${device.vendorId}.${device.productId}"
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(c: Context, intent: Intent) {
                context.unregisterReceiver(this)
                result.success(intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false))
            }
        }
        ContextCompat.registerReceiver(context, receiver, IntentFilter(action), ContextCompat.RECEIVER_NOT_EXPORTED)
        // Mutable (the system adds the grant result to it) but explicit: implicit mutable intents are rejected on Android 14+.
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
        val pending = PendingIntent.getBroadcast(context, 0, Intent(action).setPackage(context.packageName), flags)
        usb.requestPermission(device, pending)
    }

    private fun write(device: UsbDevice?, data: ByteArray?, result: MethodChannel.Result) {
        if (device == null) return result.error("no_device", "Imprimante USB introuvable (débranchée ?)", null)
        if (data == null) return result.error("no_data", "Aucune donnée à imprimer", null)
        if (!usb.hasPermission(device)) return result.error("no_permission", "Accès USB non autorisé", null)

        // Off the main thread: a bulk transfer to a busy printer can take seconds.
        io.execute {
            val outcome = try {
                writeBlocking(device, data)
                null
            } catch (e: Exception) {
                e.message ?: "Échec d'écriture USB"
            }
            main.post { if (outcome == null) result.success(null) else result.error("write_failed", outcome, null) }
        }
    }

    private fun writeBlocking(device: UsbDevice, data: ByteArray) {
        val (intf, endpoint) = findBulkOut(device) ?: throw IllegalStateException("Aucun canal d'écriture USB sur cet appareil")
        val connection = usb.openDevice(device) ?: throw IllegalStateException("Impossible d'ouvrir l'imprimante USB")
        try {
            if (!connection.claimInterface(intf, true)) throw IllegalStateException("Imprimante USB occupée")
            var offset = 0
            while (offset < data.size) {
                val len = minOf(CHUNK, data.size - offset)
                val sent = connection.bulkTransfer(endpoint, data, offset, len, TIMEOUT_MS)
                if (sent < 0) throw IllegalStateException("L'imprimante ne répond pas (écrit $offset/${data.size} octets)")
                offset += sent
            }
            connection.releaseInterface(intf)
        } finally {
            connection.close()
        }
    }

    /** The printer-class interface first (class 7), else any interface that has a bulk OUT endpoint. */
    private fun findBulkOut(device: UsbDevice): Pair<UsbInterface, UsbEndpoint>? {
        val interfaces = (0 until device.interfaceCount).map { device.getInterface(it) }
        for (intf in interfaces.sortedBy { if (it.interfaceClass == UsbConstants.USB_CLASS_PRINTER) 0 else 1 }) {
            for (i in 0 until intf.endpointCount) {
                val ep = intf.getEndpoint(i)
                if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK && ep.direction == UsbConstants.USB_DIR_OUT) return intf to ep
            }
        }
        return null
    }

    private companion object {
        const val ACTION_PERMISSION = "com.monokek.pos.USB_PERMISSION"
        const val CHUNK = 16 * 1024
        const val TIMEOUT_MS = 5000
    }
}
