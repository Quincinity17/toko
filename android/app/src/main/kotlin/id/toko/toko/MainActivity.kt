package id.toko.toko

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.Executors

/**
 * Printer thermal Bluetooth (SPP) untuk struk: daftar perangkat yang sudah
 * dipasangkan, kirim byte ESC/POS mentah, dan cek sambungan. Dipanggil dari
 * Dart lewat kanal `id.toko/bluetooth` (lib/features/receipt/data/
 * android_bluetooth.dart). Hanya perangkat yang sudah dipasangkan di
 * Pengaturan Bluetooth HP; tidak memindai.
 */
class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "id.toko/bluetooth")
            .setMethodCallHandler { call, result ->
                val adapter = adapter()
                if (adapter == null) {
                    result.error("NO_BLUETOOTH", "HP ini tidak punya Bluetooth.", null)
                    return@setMethodCallHandler
                }
                if (!hasPermission()) {
                    requestPermission()
                    result.error(
                        "PERMISSION",
                        "Izinkan akses Bluetooth (Perangkat di sekitar), lalu coba lagi.",
                        null,
                    )
                    return@setMethodCallHandler
                }
                if (!adapter.isEnabled) {
                    result.error("OFF", "Bluetooth HP mati. Nyalakan dulu.", null)
                    return@setMethodCallHandler
                }
                when (call.method) {
                    "bondedDevices" -> result.success(bonded(adapter))
                    "send" -> {
                        val address = call.argument<String>("address") ?: ""
                        val bytes = call.argument<ByteArray>("bytes") ?: ByteArray(0)
                        io.execute {
                            try {
                                write(adapter, address, bytes)
                                main.post { result.success(null) }
                            } catch (e: Exception) {
                                main.post {
                                    result.error(
                                        "SEND",
                                        "Printer $address tidak bisa dihubungi. Pastikan " +
                                            "printer menyala dan dekat. (${e.message})",
                                        null,
                                    )
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun adapter(): BluetoothAdapter? =
        (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    private fun hasPermission(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), 7)
        }
    }

    @SuppressLint("MissingPermission") // dicek di hasPermission()
    private fun bonded(adapter: BluetoothAdapter): List<Map<String, String>> =
        adapter.bondedDevices.map {
            mapOf("name" to (it.name ?: it.address), "address" to it.address)
        }

    /** Sambung RFCOMM (SPP), kirim [bytes] (boleh kosong = cek), lalu putus. */
    @SuppressLint("MissingPermission")
    private fun write(adapter: BluetoothAdapter, address: String, bytes: ByteArray) {
        val device = adapter.getRemoteDevice(address)
        adapter.cancelDiscovery()
        var socket: BluetoothSocket? = null
        try {
            socket = try {
                device.createRfcommSocketToServiceRecord(SPP).also { it.connect() }
            } catch (e: Exception) {
                // Sebagian printer murah hanya menerima sambungan "insecure".
                device.createInsecureRfcommSocketToServiceRecord(SPP).also { it.connect() }
            }
            if (bytes.isNotEmpty()) {
                val out = socket.outputStream
                // Dikirim per potongan supaya buffer printer tidak meluap.
                var i = 0
                while (i < bytes.size) {
                    val n = minOf(CHUNK, bytes.size - i)
                    out.write(bytes, i, n)
                    out.flush()
                    i += n
                    Thread.sleep(10)
                }
                // Beri waktu printer menerima sisa data sebelum diputus.
                Thread.sleep(300)
            }
        } finally {
            try {
                socket?.close()
            } catch (_: Exception) {
            }
        }
    }

    companion object {
        private val SPP: UUID = UUID.fromString("00001101-0000-1000-8000-00805F9B34FB")
        private const val CHUNK = 512
    }
}
