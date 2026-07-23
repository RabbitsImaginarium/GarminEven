package com.eveng2bridge

import android.os.Bundle
import android.util.Log
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import com.garmin.android.connectiq.ConnectIQ
import com.garmin.android.connectiq.IQApp
import com.garmin.android.connectiq.exception.InvalidStateException
import io.ktor.server.application.*
import io.ktor.server.engine.*
import io.ktor.server.netty.*
import io.ktor.server.routing.*
import io.ktor.server.websocket.*
import io.ktor.websocket.*
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

import java.util.concurrent.CopyOnWriteArrayList

class MainActivity : AppCompatActivity() {
    val MY_GARMIN_APP_ID = "AF30E9EFAC8741EA8A9C01AF9802C841" // Correct (Matches manifest.xml exactly)
    //private val MY_GARMIN_APP_ID = "AF30E9EF-AC87-41EA-8A9C-01AF9802C841"
    private var connectIQ: ConnectIQ? = null
    private val connectedSockets = CopyOnWriteArrayList<DefaultWebSocketSession>()
    private lateinit var logTextView: TextView
    private var server: ApplicationEngine? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        logTextView = TextView(this).apply {
            text = "=== EvenBridge Active ===\n"
            textSize = 14f
            setPadding(32, 32, 32, 32)
        }
        setContentView(logTextView)

        startWebSocketServer()
        initConnectIQ()
    }

    override fun onDestroy() {
        server?.stop(1000, 2000)
        super.onDestroy()
    }

    private fun logToScreen(msg: String) {
        Log.d("EvenBridge", msg)
        runOnUiThread { logTextView.append("\n$msg") }
    }

    private fun startWebSocketServer() {
        CoroutineScope(Dispatchers.IO).launch {
            try {
                server = embeddedServer(Netty, port = 8080) {
                    install(WebSockets)
                    routing {
                        webSocket("/ws") {
                            connectedSockets.add(this)
                            logToScreen("HUD Webview Connected to WS")
                            try {
                                for (frame in incoming) {} 
                            } finally {
                                connectedSockets.remove(this)
                            }
                        }
                    }
                }
                server?.start(wait = false)
                logToScreen("WS Server running on port 8080")
            } catch (e: Exception) {
                logToScreen("Server start error: ${e.message}")
            }
        }
    }

    private fun broadcastToWebview(jsonPayload: String) {
        CoroutineScope(Dispatchers.IO).launch {
            connectedSockets.forEach { socket ->
                try {
                    socket.send(Frame.Text(jsonPayload))
                } catch (e: Exception) {
                    Log.e("EvenBridge", "Send error: ${e.message}")
                }
            }
        }
    }

    private fun initConnectIQ() {
        connectIQ = ConnectIQ.getInstance(this, ConnectIQ.IQConnectType.WIRELESS)
        connectIQ?.initialize(this, true, object : ConnectIQ.ConnectIQListener {
            override fun onSdkReady() {
                logToScreen("Garmin SDK Ready. Searching...")
                registerGarminDevice()
            }
            override fun onInitializeError(status: ConnectIQ.IQSdkErrorStatus?) {
                logToScreen("Garmin Init Error: ${status?.name}")
            }
            override fun onSdkShutDown() {}
        })
    }

	private fun registerGarminDevice() {
        try {
            val pairedDevices = connectIQ?.knownDevices ?: emptyList()
            if (pairedDevices.isEmpty()) {
                logToScreen("No paired Garmin devices found.")
                return
            }

            val device = pairedDevices.first()
            logToScreen("Paired with: ${device.friendlyName}. Requesting status...")

            connectIQ?.registerForDeviceEvents(device, object : ConnectIQ.IQDeviceEventListener {
                override fun onDeviceStatusChanged(iqDevice: com.garmin.android.connectiq.IQDevice, status: com.garmin.android.connectiq.IQDevice.IQDeviceStatus) {
                    logToScreen("Device Status Changed: ${status.name}")

                    if (status == com.garmin.android.connectiq.IQDevice.IQDeviceStatus.CONNECTED) {
                        try {
                            val iqApp = IQApp(MY_GARMIN_APP_ID)
                            logToScreen("Registering direct listener for app ID: $MY_GARMIN_APP_ID")
                            
                            connectIQ?.registerForAppEvents(device, iqApp) { _, _, messageData, appStatus ->
                                logToScreen("Garmin Callback Fired! Status: ${appStatus?.name}")
                                if (appStatus == ConnectIQ.IQMessageStatus.SUCCESS && messageData != null) {
                                    val rawPayload = messageData.firstOrNull()?.toString() ?: "{}"
                                    logToScreen("RX: $rawPayload")
                                    broadcastToWebview(rawPayload)
                                }
                            }
                        } catch (e: Exception) {
                            logToScreen("Direct Registration Error: ${e.message}")
                        }
                    }
                }
            })

        } catch (e: InvalidStateException) {
            logToScreen("ConnectIQ State Error: ${e.message}")
        }
    }

    private fun OLDregisterGarminDevice() {
        try {
            val pairedDevices = connectIQ?.knownDevices ?: emptyList()
            if (pairedDevices.isEmpty()) {
                logToScreen("No paired Garmin devices found.")
                return
            }

            val device = pairedDevices.first()
            logToScreen("Paired with: ${device.friendlyName}")

            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                try {
                    val iqApp = IQApp(MY_GARMIN_APP_ID)
                    logToScreen("Registering listener for app ID: $MY_GARMIN_APP_ID")
                    connectIQ?.registerForAppEvents(device, iqApp) { _, _, messageData, status ->
                        logToScreen("Garmin Callback Fired! Status: ${status?.name}")
                        if (status == ConnectIQ.IQMessageStatus.SUCCESS && messageData != null) {
                            val rawPayload = messageData.firstOrNull()?.toString() ?: "{}"
                            logToScreen("RX: $rawPayload")
                            broadcastToWebview(rawPayload)
                        }
                    }
                } catch (e: InvalidStateException) {
                    logToScreen("ConnectIQ Delayed State Error: ${e.message}")
                } catch (e: Exception) {
                    logToScreen("Unexpected Registration Error: ${e.message}")
                }
            }, 1000)

        } catch (e: InvalidStateException) {
            logToScreen("ConnectIQ State Error: ${e.message}")
        }
    }
}
