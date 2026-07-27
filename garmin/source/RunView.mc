import Toybox.Graphics;
import Toybox.WatchUi;
import Toybox.Communications;
import Toybox.Timer;
import Toybox.Lang;
import Toybox.Activity;
import Toybox.Sensor;

class RunView extends WatchUi.View {
    var updateTimer;

    function initialize() { 
        View.initialize(); 
        updateTimer = new Timer.Timer();
        updateTimer.start(method(:onTimerTick) as Method() as Void, 1000, true);
    }

    function onTimerTick() as Void { 
        WatchUi.requestUpdate(); 
    }
    
    function formatPace(speedMs) {
        if (speedMs == null || speedMs <= 0.2) { return "--:--"; }
        var paceSecKm = (1000.0 / speedMs).toLong();
        var mins = paceSecKm / 60;
        var secs = paceSecKm % 60;
        return mins.format("%d") + ":" + (secs < 10 ? "0" : "") + secs.format("%d");
    }

    function formatTimer(elapsedMs) {
        if (elapsedMs == null || elapsedMs <= 0) { return "0:00"; }
        var totalSecs = elapsedMs / 1000;
        var mins = totalSecs / 60;
        var secs = totalSecs % 60;
        return mins.format("%d") + ":" + (secs < 10 ? "0" : "") + secs.format("%d");
    }

    function toggleRecording() {
        // This method is required by RemoteDelegate.
        // Recording session is currently managed by RunDelegate.
    }

    function onUpdate(dc) {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // 1. Fetch Real-time Activity and Sensor Data
        var info = Activity.getActivityInfo();
        var sensorInfo = Sensor.getInfo();

        var paceStr = formatPace(info.currentSpeed);
        var distKm = (info.elapsedDistance != null) ? (info.elapsedDistance / 1000.0) : 0.0;
        var distStr = distKm.format("%.2f");
        var timerStr = formatTimer(info.timerTime);

        var hr = (sensorInfo != null && sensorInfo.heartRate != null) ? sensorInfo.heartRate : info.currentHeartRate;
        var hrStr = (hr != null) ? hr.format("%d") : "---";

        // Outer Orange Accent Ring
        dc.setPenWidth(4);
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(208, 208, 195);

        // Top: PACE
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT); 
        dc.drawText(208, 55, Graphics.FONT_XTINY, "PACE", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(208, 75, Graphics.FONT_NUMBER_HOT, paceStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Middle Divider Line
        dc.setPenWidth(2);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(208, 175, 208, 255);

        // Middle Left: DISTANCE
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(106, 175, Graphics.FONT_XTINY, "DISTANCE", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(106, 195, Graphics.FONT_NUMBER_MEDIUM, distStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Middle Right: TIMER
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(310, 175, Graphics.FONT_XTINY, "TIMER", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(310, 195, Graphics.FONT_NUMBER_MEDIUM, timerStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Bottom: HR
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(155, 295, Graphics.FONT_SMALL, "HR", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(240, 280, Graphics.FONT_NUMBER_HOT, hrStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Transmit dynamic metrics to bridge if streaming is active
        if (isStreaming) {
            var jsonStr = "{\"pace\":\"" + paceStr + "\",\"distance\":\"" + distStr + "\",\"timer\":\"" + timerStr + "\",\"hr\":\"" + hrStr + "\"}";
            Communications.transmit(jsonStr, null, new CommListener());
        }
    }
}
