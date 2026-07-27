package com.eveng2bridge

import android.content.Intent
import android.os.Bundle
import android.util.Log
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity : AppCompatActivity() {

    private lateinit var logTextView: TextView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        logTextView = TextView(this).apply {
            text = "=== EvenBridge Active ===\n"
            textSize = 14f
            setPadding(32, 32, 32, 32)
        }
        setContentView(logTextView)

        // Start the foreground service
        startService(Intent(this, EvenBridgeService::class.java))
        logToScreen("Started EvenBridge Foreground Service")
    }

    override fun onDestroy() {
        super.onDestroy()
        // Stop the service when activity is destroyed
        stopService(Intent(this, EvenBridgeService::class.java))
        logToScreen("Stopped EvenBridge Foreground Service")
    }

    private fun logToScreen(msg: String) {
        Log.d("EvenBridge", msg)
        runOnUiThread { logTextView.append("\n$msg") }
    }
}
