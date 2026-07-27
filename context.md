# GarminEven — System Architecture & Communication Protocol

## System Overview

```
  ┌─────────────────────┐       Connect IQ Wireless        ┌──────────────────────────┐       WebSocket (ws://)       ┌─────────────────────────┐
  │   Garmin Watch      │ ──────────────────────────────► │   Android EvenBridge App  │ ──────────────────────────► │   Even G2 Smart Glasses │
  │   (epix2)           │    Communications.transmit()     │   (MainActivity.kt)       │    port 8080, /ws          │   (g2-hud app.js)       │
  │                     │                                  │                           │                            │                         │
  │ RunView.mc          │   JSON payload every 1 second   │   Pure relay — no         │   Raw JSON broadcast      │   Canvas bitmap → HUD   │
  │ + CommManager.mc    │                                  │   transformation          │                            │   @evenrealities SDK    │
  └─────────────────────┘                                  └──────────────────────────┘                            └─────────────────────────┘
```

Three distinct apps form a data pipeline: The Garmin watch collects running metrics and streams them wirelessly to a paired Android phone. The Android app receives these messages via the Garmin Connect IQ SDK and immediately relays them over a local WebSocket server. The Even G2 glasses app (running on the Even Mini/Phone companion) connects to that WebSocket, renders metric text as a monochrome bitmap, and pushes it to the glasses HUD.

---

## Component 1: Garmin Watch App

**Directory:** `GarminEven/garmin/`  
**Entry point:** `source/RunApp.mc` → `source/RunView.mc`  
**App ID:** `AF30E9EFAC8741EA8A9C01AF9802C841` (defined in `manifest.xml`)  
**Target device:** `epix2` (Connect IQ legacy)

### Source Files and Roles

| File | Role |
|---|---|
| `source/RunApp.mc` | Secondary app entry. Sets `isStreaming = true` and loads `RunView`. |
| `source/RunView.mc` | Main display and data transmitter. Starts a 1s timer, reads sensor data, constructs JSON, and calls `Communications.transmit()`. |
| `source/CommManager.mc` | Singleton transmission guard. Prevents concurrent `Communications.transmit()` calls with a busy-state check. |
| `source/RunDelegate.mc` | Button handlers to start/stop the recording session. |
| `source/RunMenuDelegate.mc` | Submenu for "Stream to HUD" / "Stop Run" options. |
| `manifest.xml` | Declaration of the Connect IQ app with permissions and target product. |

### Data Collection

RunView.mc polls the following on every timer tick (1 second):

- **Pace:** Derived from `Sensor.getInfo().currentSpeed`. Format: `"M:SS"` (e.g. `"6:30"`)
- **Heart Rate:** From `Sensor.getInfo().heartRate` or fallback to `Activity.getActivityInfo().currentHeartRate`
- **Distance:** `Activity.getActivityInfo().elapsedDistance` in kilometers, formatted `"%.2f"` (e.g. `"5.72"`)
- **Timer:** `Activity.getActivityInfo().timerTime` formatted as `"M:SS"` (e.g. `"5:45"`)

### Transmission Protocol

- **API:** `Toybox.Communications.transmit(data, null, listener)`
- **Transport:** Connect IQ `WIRELESS` mode (Bluetooth or WiFi, handled by the SDK)
- **Rate:** Every 1 second (1000ms `Timer.Timer`)
- **Busy guard:** `CommManager.sendCommand()` drops messages if a previous transmit is still in progress — this avoids overlapping calls
- **Connection listener:** `CommListener` extends `Connections.ConnectionListener` with `onComplete()` / `onError()` callbacks

### Wire Format (Sent by RunView.mc)

JSON object per message, sent every 1 second (while streaming is active):

```json
{
  "pace": "6:30",
  "distance": "5.72",
  "timer": "5:45",
  "hr": "82"
}
```

| Field | Type | Example | Source |
|---|---|---|---|
| `pace` | String | `"6:30"` | `formatPace(info.currentSpeed)` → minutes:seconds per km |
| `distance` | String | `"5.72"` | `info.elapsedDistance / 1000.0` formatted with `%.2f` |
| `timer` | String | `"5:45"` | `info.timerTime` → `M:SS` |
| `hr` | String | `"82"` | `sensorInfo.heartRate` or `info.currentHeartRate` |

All values are **strings** in the JSON payload (not numbers). Numeric formatting is done on the watch before serialization.

---

## Component 2: Android EvenBridge App

**Directory:** `GarminEven/EvenBridgeApp/`

### Source File

| File | Role |
|---|---|
| `app/src/main/java/com/eveng2bridge/MainActivity.kt` | Single Activity: initializes Connect IQ SDK and Ktor WebSocket server |

### Garmin Side (Consumer)

- **SDK:** `com.garmin.android.connectiq.ConnectIQ`
- **Connection type:** `WIRELESS` (wireless)
- **Initialization flow:**
  1. `initConnectIQ()` → `onSdkReady()` callback
  2. Query `connectIQ?.knownDevices` for paired devices
  3. Pick first device and call `registerForDeviceEvents()`
  4. On `CONNECTED` status → create `IQApp(MY_GARMIN_APP_ID)` → call `registerForAppEvents()`
  5. App events callback receives `messageData` — raw JSON string from the watch

### WebSocket Side (Publisher)

- **Server:** Ktor Netty embedded server on **port 8080**
- **Endpoint:** `ws://127.0.0.1:8080/ws`
- **Behavior:** Maintains a `CopyOnWriteArrayList` of connected WebSocket sessions. Any JSON message from Garmin is broadcast to **all** connected WebSocket clients via `Frame.Text(jsonPayload)`.
- **No transformation — pure relay:** The Android app does not parse, validate, or modify the JSON. It passes the raw string through.

### Key Code Paths

- `startWebSocketServer()` — launches Ktor Netty on port 8080
- `initConnectIQ()` → `registerGarminDevice()` — connects to paired watch
- Garmin callback: status check → `broadcastToWebview(rawPayload)` → sends to all WebSocket sessions

---

## Component 3: Even G2 HUD (Glasses App)

**Directory:** `GarminEven/g2-hud/`

### Entry Point

| File | Role |
|---|---|
| `app.js` | Main application — WebSocket client + HUD renderer |
| `app.json` | Package manifest (package: `com.garmin.hud`, version `1.0.48`) |
| `index.html` | Simple container page with debug log `<pre>` element |

### Permissions

```json
{
  "name": "network",
  "desc": "Connects to local Android bridge server for streaming data",
  "whitelist": ["127.0.0.1", "localhost"]
}
```

Only localhost network access is allowed (for reaching the Android bridge WebSocket).

### Initialization Flow

1. `initGlasses()` called on DOMContentLoaded
2. Calls `await waitForEvenAppBridge()` from the `@evenrealities/even_hub_sdk`
3. Creates a startup page container with **2 containers**:
   - **containerID 4:** Text container ("ready-text", 240x60) at position (100, 80), initial content "Ready"
   - **containerID 5:** Image container ("pace_img", 200x100) at position (10, 10)
4. On success (`result === 0`): pushes default metrics, then calls `connectWebsock()`

### WebSocket Client

- **URL:** `ws://127.0.0.1:8080/ws`
- **Reconnect:** On close (`socket.onclose`), waits 3 seconds then reconnects
- **Message handling:**
  - Unmarshals JSON from WebSocket
  - Extract fields: `t.pace`, `t.hr`, `t.distance`, `t.timer`
  - Applies display formatting:
    - Pace: `"${t.pace} min/km"`
    - HR: `"${t.hr} bpm"`
    - Distance: `"${t.distance} km"`
    - Timer: as-is (e.g. `"5:45"`)
  - **Throttles updates:** only redraws every **5th message** (or the first message)

### HUD Rendering (Canvas Bitmap)

The `createMetricBitmap()` function renders a **200x100px canvas**:

- Background: Black (`#000000` → transparent on HUD)
- Text: White (`#FFFFFF` → green monochrome pixel on HUD)
- Layout:
  - Line 1 (y=8, font 24px bold monospace): Pace (e.g. "6:30 min/km")
  - Line 2 (y=40, font 24px bold monospace): HR (e.g. "82 bpm")
  - Line 3 (y=76, font 15px bold monospace): Distance | Timer (e.g. "5.72 km | 5:45")
- Raw pixel data (20,000 bytes) extracted via `createImageData()` and pushed to container via `bridge.updateImageRawData({ containerID: 5, containerName: "pace_img", imageData: rawPixels })`

### Display Format

```
╔══════════════════════╗
║   6:30 min/km       ║   ← Pace (larger, 24px)
║      82 bpm        ║   ← Heart Rate (larger, 24px)
║ 5.72 km | 5:45     ║   ← Distance | Timer (smaller, 15px)
╚══════════════════════╝
```

---

## End-to-End Data Flow Summary

```
Step 1: RunView.onUpdate() is called every 1 second
         → Reads Activity.getActivityInfo() + Sensor.getInfo()
         → Formats: pace (M:SS), distance (km string), timer (M:SS), hr (string)
         → Checks isStreaming === true

Step 2: CommManager.getInstance().sendCommand(jsonString)
         ├─ If not busy → Communications.transmit(jsonString) to paired phone
         └─ If busy → drop packet (log "BUSY_DROP")

Step 3: Android ConnectIQ SDK receives message
         ├─ ConnectIQListener.onDeviceStatusChanged → CONNECTED
         ├─ registerForAppEvents() with IQApp("AF30E9EFAC32432EA8A8C01AF0814C841")
         └─ App event callback fires: messageData = JSON string

Step 4: MainActivity.broadcastToWebview(rawPayload)
         └─ All connected WebSocket sessions receive Frame.Text(jsonPayload)

Step 5: g2-hud/app.js receives WebSocket message
         ├─ JSON.parse() → object.place, object.hr, object.distance, object.timer
         ├─ Apply display formatting and fallback defaults
         ├─ Throttle check (every 5th message)
         └─ createMetricBitmap() → raw pixel array → bridge.updateImageRawData()

Step 6: Even G2 glasses display the monochrome bitmap on the HUD
```

---

## Connection Lifecycle

### Garmin → Android

1. Watch app launches → `CommManager` singleton initialized
2. Android `ConnectIQ` initializes → SDK reports `onSdkReady`
3. Android queries known devices → picks first one → registers for device events
4. On `CONNECTED` → register for app events with the monitored IQ app ID
5. Watch sends `Communications.transmit()` → Android receives in app event callback
6. If watch disconnects → `onDeviceStatusChanged` fires → new connection cycle starts

### Android → HUD

1. Ktor Netty server starts on port 8080 on app creation
2. WebSocket at `/ws` accepts incoming connections
3. On connection → adds session to `connectedSessions` list
4. The HUD `app.js` connects via `new WebSocket("ws://127.0.0.1:8080/ws")`
5. Android broadcasts all Garmin messages to all connected WebSocket clients
6. On HUD WebSocket close → auto-reconnect after 3 seconds

### HUD → Glasses

1. `initGlasses()` calls `waitForEvenAppBridge()` from the Even SDK
2. Creates head-up display containers (2 total: text + image)
3. Sets initial defaults: "Ready" status text, default metrics bitmap
4. On WebSocket message → updates only the image container (containerID 5)
5. No teardown — all containers are created once and updated in place

---

## Known Limitations & Points of Interest

1. **Packet drop on watch:** If the 1-second timer fires while a previous `Communications.transmit()` is still pending, the new packet is dropped silently (`"BUSY_DROP"` in the TX status display). This means occasional 1-second gaps can occur.

2. **No retry/ack mechanism:** There is no acknowledgment from the Android bridge back to the watch. If a transmit fails, the data for that second is simply lost.

3. **Throttling on HUD:** The g2-hud only redraws every 5th WebSocket message to avoid overwhelming the glasses rendering pipeline. This means the HUD updates at roughly 0.2 Hz, though fresh metrics arrive at 1 Hz.

4. **All values are strings:** The watch serializes all numeric values as strings. The HUD does not re-parse them — it manually appends units (e.g. `"82"` → `"82 bpm"`).

5. **Localhost-only:** The HUD app's network permission is whitelisted to localhost. The Android bridge + Even companion app (hosting the g2-hud webview) must run on the same device.

---

## Build & Deployment Notes

- **Garmin app** — built with ConnectIQ SDK, targeted to epix2
- **Android app** — Gradle-built Kotlin app with `connectiq` SDK and `ktor-server-netty` dependencies
- **g2-hud** — packaged with `compile.sh` into `g2uhud.ehpk` (Even package format), uses `@evenrealities/even_hub_sdk` library