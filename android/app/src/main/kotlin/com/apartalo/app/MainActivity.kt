package com.apartalo.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import kotlin.concurrent.thread

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.apartalo/device_info"
    private val COMPROBANTE = "com.apartalo/comprobante"
    private var comprobante: MethodChannel? = null
    // Una imagen compartida (WhatsApp → Finca Rosal) que Flutter todavía no tomó.
    private var pendiente: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getManufacturer" -> {
                    result.success(Build.MANUFACTURER)
                }
                "getModel" -> {
                    result.success(Build.MODEL)
                }
                "isSunmi" -> {
                    val isSunmi = Build.MANUFACTURER.lowercase().contains("sunmi")
                    result.success(isSunmi)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        comprobante = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, COMPROBANTE).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "pendiente" -> {
                        result.success(pendiente)
                        pendiente = null
                    }
                    "leerTexto" -> {
                        val ruta = call.argument<String>("ruta")
                        if (ruta == null) {
                            result.success("")
                        } else {
                            thread {
                                val texto = try {
                                    val imagen = InputImage.fromFilePath(this@MainActivity, Uri.fromFile(File(ruta)))
                                    val lector = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
                                    try { Tasks.await(lector.process(imagen)).text } finally { lector.close() }
                                } catch (e: Exception) {
                                    ""
                                }
                                runOnUiThread { result.success(texto) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
        recibir(intent, avisar = false) // al abrir la app, Flutter la pide con "pendiente"
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        recibir(intent, avisar = true) // la app ya estaba abierta: se avisa a Flutter
    }

    /// Una imagen compartida: se copia a la caché de la app (nunca a la galería) mientras dura el permiso de
    /// WhatsApp; Flutter la borra al guardar o al cerrar sin guardar.
    private fun recibir(intent: Intent?, avisar: Boolean) {
        if (intent?.action != Intent.ACTION_SEND || intent.type?.startsWith("image/") != true) return
        @Suppress("DEPRECATION")
        val uri: Uri = (if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                        else intent.getParcelableExtra(Intent.EXTRA_STREAM)) ?: return
        intent.action = null // no se vuelve a leer al rotar la pantalla
        try {
            val carpeta = File(cacheDir, "comprobantes").apply { mkdirs() }
            val extension = if (intent.type == "image/png") "png" else "jpg"
            val destino = File(carpeta, "compartido_${System.currentTimeMillis()}.$extension")
            contentResolver.openInputStream(uri)?.use { entrada -> destino.outputStream().use { entrada.copyTo(it) } } ?: return
            val canal = comprobante
            if (avisar && canal != null) canal.invokeMethod("compartido", destino.absolutePath) else pendiente = destino.absolutePath
        } catch (e: Exception) {
            // Sin la imagen no se abre nada: la persona puede compartirla de nuevo.
        }
    }
}
