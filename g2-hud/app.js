import { waitForEvenAppBridge } from 'https://cdn.jsdelivr.net/npm/@evenrealities/even_hub_sdk@0.0.12/+esm';

const WS_URL = "ws://127.0.0.1:8080/ws";
let bridge = null;
let isContainerCreated = false;
let rxCount = 0;

function logStatus(msg) {
    console.log("[Status]", msg);
    const el = document.getElementById("status");
    if (el) el.innerText = msg;
}

function logWs(msg) {
    console.log("[WS]", msg);
    const el = document.getElementById("ws-debug");
    if (el) el.innerText = msg;
}

function formatPace(paceVal) {
    const num = parseFloat(paceVal);
    if (isNaN(num) || num <= 0.0 || num > 30.0) {
        return "--:--";
    }
    const mins = Math.floor(num);
    const secs = Math.round((num - mins) * 60);
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
}

async function initGlasses() {
    try {
        logStatus("Connecting Bridge...");
        bridge = await waitForEvenAppBridge();
        
        // Text Container Setup for HUD
        const startupPayload = {
            containerTotalNum: 1,
            textObject: [{
                containerID: 1,
                containerName: "garmin_hud_text",
                isEventCapture: 1,
                zOrderIndex: 1,
                xPosition: 0,
                yPosition: 0,
                width: 576,
                height: 288,
                content: "WAITING FOR DATA..."
            }]
        };

        const res = await bridge.createStartUpPageContainer(startupPayload);
        if (res === 0) {
            isContainerCreated = true;
            logStatus("Text HUD Ready on Lenses");
        } else {
            logStatus(`SDK Container Fail: ${res}`);
        }
    } catch (e) {
        logStatus("SDK Error: " + (e.stack || e.message));
    }
}

function updateGlassesDisplay(paceStr, hr, distance, time) {
    if (!bridge || !isContainerCreated) return;

    // Clean multi-line layout for the lenses
    const formattedText = `${paceStr} min/km\n\n${hr} BPM\n\n${distance} km   ${time}`;

    bridge.textContainerUpgrade({
        containerID: 1,
        containerName: "garmin_hud_text",
        content: formattedText
    }).then(res => {
        logStatus(`Glasses Update OK (${res})`);
    }).catch(err => {
        logStatus(`Upgrade Error: ${err.message || err}`);
        console.error("Text Upgrade error:", err);
    });
}

function connectBridge() {
    logWs(`Connecting to ${WS_URL}...`);
    
    let socket;
    try {
        socket = new WebSocket(WS_URL);
    } catch (e) {
        logWs("WS Connect Fail: " + e.message);
        return;
    }

    socket.onopen = () => {
        logWs("WS Connected! Waiting for packet...");
    };

    socket.onmessage = (e) => {
        try {
            rxCount++;
            const t = JSON.parse(e.data);
            
            const rawPace = t.pace !== undefined ? t.pace : "--:--";
            const paceStr = typeof rawPace === 'number' ? formatPace(rawPace) : rawPace.replace(" min/km", "");
            
            const hr = t.hr !== undefined ? t.hr : "--";
            const distance = t.distance !== undefined ? t.distance : "0.00";
            const time = t.time !== undefined ? t.time : "0:00";

            // Update local phone DOM preview
            const paceEl = document.getElementById("pace-display");
            const hrEl = document.getElementById("hr-display");
            const distEl = document.getElementById("dist-display");
            const timeEl = document.getElementById("time-display");

            if (paceEl) paceEl.innerText = paceStr;
            if (hrEl) hrEl.innerText = `${hr} bpm`;
            if (distEl) distEl.innerText = distance;
            if (timeEl) timeEl.innerText = time;
            
            logWs(`Packets Received: ${rxCount} | Pace: ${paceStr}`);

            // Make sure UI remains visible on phone
            document.body.style.opacity = 1;

            // Push updated text to HUD
            updateGlassesDisplay(paceStr, hr, distance, time);

            /* 
             * BLACKOUT TIMEOUT DISABLED FOR TESTING
             * 
             * if (blackoutTimeout) {
             *     clearTimeout(blackoutTimeout);
             * }
             * blackoutTimeout = setTimeout(() => {
             *     triggerBlackout();
             * }, 5000);
             */

        } catch (err) {
            logWs("WS JSON Parse Error");
            console.error("WS Parse Error:", err);
        }
    };

    socket.onerror = (err) => {
        logWs("WS Error: Cannot reach port 8080");
    };

    socket.onclose = () => {
        logWs("WS Disconnected. Reconnecting in 3s...");
        setTimeout(connectBridge, 3000);
    };
}

initGlasses();
connectBridge();
