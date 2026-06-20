package com.apartalo.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Receiver para el escáner de hardware Sunmi
 * Algunos modelos Sunmi envían el código por broadcast
 */
class SunmiScannerReceiver : BroadcastReceiver() {
    
    companion object {
        private const val TAG = "SunmiScanner"
        const val ACTION_DATA_CODE_RECEIVED = "com.sunmi.scanner.ACTION_DATA_CODE_RECEIVED"
        const val DATA = "data"
        const val SOURCE = "source_byte"
    }
    
    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent?.action == ACTION_DATA_CODE_RECEIVED) {
            val code = intent.getStringExtra(DATA)
            if (code != null) {
                Log.d(TAG, "Código escaneado: $code")
                // El código se envía por teclado, Flutter lo captura directamente
            }
        }
    }
}
