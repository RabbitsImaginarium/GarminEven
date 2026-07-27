package com.eveng2bridge

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
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

class EvenBridgeService : Service() {

    companion object {
        const val CHANNEL_ID = "EvenBridgeForegroundServiceChannel"
        const val NOTIFICATION_ID = 1
    }

    val MY_GARMIN_APP_ID = "AF30E9EFAC8741EA8A9C01AF9802C841"
    private var connectIQ: ConnectIQ? = null
    private val connectedSockets = CopyOnWriteArrayList<DefaultWebSocketSession>()
    private var server: ApplicationEngine? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        
        startWebSocketServer()
        initConnectIQ()
        
        Log.d("EvenBridge", "Foreground Service Created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Service started, return START_STICKY to keep running if killed
        Log.d("EvenBridge", "Foreground Service Started")
        return Service.START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        server?.stop(1000, 2000)
        Log.d("EvenBridge", "Foreground Service Destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? {
        // Not used for started service
        return null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "EvenBridge Service"
            val descriptionText = "Keeps Garmin-EvenBridge connection active"
            val importance = NotificationManager.IMPORTANCE_LOW
            val channel = NotificationChannel(CHANNEL_ID, name, importance).apply {
                description = descriptionText
            }
            // Register the channel with the system
            val notificationManager: NotificationManager =
                getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val notificationBuilder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("EvenBridge Active")
            .setContentText("Maintaining Garmin to HUD connection")
            .setSmallIcon(android.R.drawable.ic_dialog_info) // Using default icon
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)

        return notificationBuilder.build()
    }

    private fun logToScreen(msg: String) {
        Log.d("EvenBridge", msg)
        // Note: We don't update UI in service, but we could send broadcasts if needed
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
}