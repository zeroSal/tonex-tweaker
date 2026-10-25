package com.zerosal.tonex_tweaker

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Raw CDC-ACM transport for the ToneX One "Control VCOM" interface.
 *
 * Interface 0 is CDC communication (class 2), interface 1 is CDC data (class 10)
 * with one bulk IN and one bulk OUT endpoint. Audio interfaces are left alone.
 */
class UsbBridge(private val context: Context, messenger: BinaryMessenger) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val VENDOR_IK = 0x1963
        const val PRODUCT_TONEX_ONE = 0x00D1
        private const val ACTION_PERMISSION = "com.zerosal.tonex_tweaker.USB_PERMISSION"
        private const val READ_BUFFER = 16384
        private const val WRITE_CHUNK = 16384
    }

    private val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val main = Handler(Looper.getMainLooper())
    private val writer = Executors.newSingleThreadExecutor()
    private val methods = MethodChannel(messenger, "tonex/usb")
    private val events = EventChannel(messenger, "tonex/usb/events")

    private var sink: EventChannel.EventSink? = null
    private var pendingConnect: MethodChannel.Result? = null

    @Volatile private var connection: UsbDeviceConnection? = null
    private var device: UsbDevice? = null
    private var commIface: UsbInterface? = null
    private var dataIface: UsbInterface? = null
    private var epIn: UsbEndpoint? = null
    private var epOut: UsbEndpoint? = null
    private var reader: Thread? = null

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (intent.action) {
                ACTION_PERMISSION -> {
                    val result = pendingConnect ?: return
                    pendingConnect = null
                    val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                    val dev = findToneX()
                    if (granted && dev != null) open(dev, result)
                    else result.error("PERMISSION_DENIED", "USB permission denied", null)
                }
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> notifyAttached()
                UsbManager.ACTION_USB_DEVICE_DETACHED -> {
                    val dev = usbDevice(intent)
                    if (dev != null && dev.deviceName == device?.deviceName) {
                        close()
                        emit(mapOf("type" to "detached"))
                    }
                }
            }
        }
    }

    init {
        methods.setMethodCallHandler(this)
        events.setStreamHandler(this)
        val filter = IntentFilter().apply {
            addAction(ACTION_PERMISSION)
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }
    }

    fun notifyAttached() {
        if (findToneX() != null) emit(mapOf("type" to "attached"))
    }

    fun dispose() {
        close()
        runCatching { context.unregisterReceiver(receiver) }
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
        writer.shutdownNow()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAttached" -> result.success(findToneX() != null)
            "connect" -> connect(result)
            "disconnect" -> {
                close()
                result.success(null)
            }
            "write" -> write(call.arguments as ByteArray, result)
            else -> result.notImplemented()
        }
    }

    private fun findToneX(): UsbDevice? = usbManager.deviceList.values.firstOrNull {
        it.vendorId == VENDOR_IK && it.productId == PRODUCT_TONEX_ONE
    }

    private fun connect(result: MethodChannel.Result) {
        if (connection != null) {
            result.success(true)
            return
        }
        val dev = findToneX() ?: return result.error("NOT_FOUND", "ToneX One not connected", null)
        if (usbManager.hasPermission(dev)) {
            open(dev, result)
            return
        }
        pendingConnect?.error("CANCELLED", "Superseded by a new connect request", null)
        pendingConnect = result
        val intent = Intent(ACTION_PERMISSION).setPackage(context.packageName)
        // FLAG_MUTABLE: the system adds EXTRA_PERMISSION_GRANTED to this intent.
        val flags = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        usbManager.requestPermission(dev, PendingIntent.getBroadcast(context, 0, intent, flags))
    }

    private fun open(dev: UsbDevice, result: MethodChannel.Result) {
        var comm: UsbInterface? = null
        var data: UsbInterface? = null
        for (i in 0 until dev.interfaceCount) {
            val iface = dev.getInterface(i)
            when (iface.interfaceClass) {
                UsbConstants.USB_CLASS_COMM -> if (comm == null) comm = iface
                UsbConstants.USB_CLASS_CDC_DATA -> if (data == null) data = iface
            }
        }
        if (data == null) return result.error("NO_CDC", "CDC data interface not found", null)

        var inEp: UsbEndpoint? = null
        var outEp: UsbEndpoint? = null
        for (i in 0 until data.endpointCount) {
            val ep = data.getEndpoint(i)
            if (ep.type != UsbConstants.USB_ENDPOINT_XFER_BULK) continue
            if (ep.direction == UsbConstants.USB_DIR_IN) inEp = ep else outEp = ep
        }
        if (inEp == null || outEp == null) {
            return result.error("NO_ENDPOINTS", "Bulk endpoints not found", null)
        }

        val conn = usbManager.openDevice(dev)
            ?: return result.error("OPEN_FAILED", "Unable to open USB device", null)
        if (comm != null) conn.claimInterface(comm, true)
        if (!conn.claimInterface(data, true)) {
            conn.close()
            return result.error("CLAIM_FAILED", "Unable to claim CDC data interface", null)
        }

        if (comm != null) {
            // SET_LINE_CODING 115200 8N1, then SET_CONTROL_LINE_STATE DTR|RTS.
            val coding = byteArrayOf(0x00, 0xC2.toByte(), 0x01, 0x00, 0x00, 0x00, 0x08)
            conn.controlTransfer(0x21, 0x20, 0, comm.id, coding, coding.size, 1000)
            conn.controlTransfer(0x21, 0x22, 0x03, comm.id, null, 0, 1000)
        }

        device = dev
        commIface = comm
        dataIface = data
        epIn = inEp
        epOut = outEp
        connection = conn
        startReader(conn, inEp)
        result.success(true)
    }

    private fun startReader(conn: UsbDeviceConnection, ep: UsbEndpoint) {
        reader = Thread({
            val buf = ByteArray(READ_BUFFER)
            while (connection === conn && !Thread.currentThread().isInterrupted) {
                val n = conn.bulkTransfer(ep, buf, buf.size, 250)
                if (n > 0) {
                    val chunk = buf.copyOf(n)
                    emit(mapOf("type" to "data", "bytes" to chunk))
                }
            }
        }, "tonex-usb-reader").apply {
            isDaemon = true
            start()
        }
    }

    private fun write(bytes: ByteArray, result: MethodChannel.Result) {
        val conn = connection
        val ep = epOut
        if (conn == null || ep == null) return result.error("NOT_CONNECTED", "Not connected", null)
        writer.execute {
            var offset = 0
            var ok = true
            while (offset < bytes.size) {
                val len = minOf(WRITE_CHUNK, bytes.size - offset)
                val n = conn.bulkTransfer(ep, bytes, offset, len, 1000)
                if (n <= 0) {
                    ok = false
                    break
                }
                offset += n
            }
            main.post {
                if (ok) result.success(null)
                else result.error("WRITE_FAILED", "USB bulk write failed", null)
            }
        }
    }

    private fun close() {
        val conn = connection ?: return
        connection = null
        reader?.interrupt()
        reader = null
        dataIface?.let { conn.releaseInterface(it) }
        commIface?.let { conn.releaseInterface(it) }
        conn.close()
        device = null
        commIface = null
        dataIface = null
        epIn = null
        epOut = null
    }

    private fun emit(event: Map<String, Any>) {
        main.post { sink?.success(event) }
    }

    @Suppress("DEPRECATION")
    private fun usbDevice(intent: Intent): UsbDevice? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        }
}
