import Toybox.Application;
import Toybox.WatchUi;
import Toybox.ActivityRecording;
import Toybox.Activity;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.Graphics;
import Toybox.Lang;

class EvenG2BridgeApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() {
        var view = new RemoteView();
        var delegate = new RemoteDelegate(view);
        return [ view, delegate ];
    }
}

class RemoteView extends WatchUi.View {
    private var _session as ActivityRecording.Session? = null;
    private var _timer as Timer.Timer?;
    private var _lastHr as Number = 0;
    private var _lastPace as Float = 0.0;
    private var _elapsedSeconds as Number = 0;
    private var _elapsedDistance as Float = 0.0;
    private var _isRecording as Boolean = false;

    function initialize() {
        View.initialize();
        
        Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
        Sensor.enableSensorEvents(method(:onSensorUpdate));
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPositionUpdate));

        _timer = new Timer.Timer();
        if (_timer != null) {
            _timer.start(method(:onTimerTick), 1000, true);
        }
    }

    function onSensorUpdate(sensorInfo as Sensor.Info) as Void {
        if (sensorInfo != null && sensorInfo.heartRate != null) {
            _lastHr = sensorInfo.heartRate;
        }
    }

    function onPositionUpdate(posInfo as Position.Info) as Void {
        if (posInfo != null && posInfo.speed != null && posInfo.speed > 0) {
            _lastPace = (1000.0 / posInfo.speed) / 60.0;
        } else {
            _lastPace = 0.0;
        }
    }

    function toggleRecording() as Void {
        if (!_isRecording) {
            _session = ActivityRecording.createSession({
                :name => "Run",
                :sport => ActivityRecording.SPORT_RUNNING
            });
            var session = _session;
            if (session != null) {
                session.start();
                _isRecording = true;
                _elapsedSeconds = 0;
                _elapsedDistance = 0.0;
            }
        } else {
            var session = _session;
            if (session != null) {
                session.stop();
                session.save();
                _session = null;
            }
            _isRecording = false;
        }
        WatchUi.requestUpdate();
    }

    function onTimerTick() as Void {
        if (_isRecording) {
            _elapsedSeconds += 1;
            
            try {
                var actInfo = Activity.getActivityInfo();
                if (actInfo != null) {
                    if (actInfo.elapsedDistance != null) {
                        _elapsedDistance = actInfo.elapsedDistance / 1000.0;
                    }
                    if (actInfo.elapsedTime != null) {
                        _elapsedSeconds = (actInfo.elapsedTime / 1000.0).toNumber();
                    }
                }
            } catch (e) {
                // Fallback tick
            }

            if (_elapsedSeconds % 15 == 0) {
                var paceStr = formatPace(_lastPace);
                var timeStr = formatTime(_elapsedSeconds);
                var payloadString = "{\"type\":\"metrics\",\"hr\":" + _lastHr + ",\"pace\":\"" + paceStr + "\",\"distance\":" + _elapsedDistance.format("%.2f") + ",\"time\":\"" + timeStr + "\"}";

                try {
                    CommManager.getInstance().sendCommand(payloadString);
                } catch (e) {
                    // Suppress transmission exceptions
                }
            }
        }
        WatchUi.requestUpdate();
    }

    function formatPace(paceVal as Float) as String {
        if (paceVal <= 0.0 || paceVal > 20.0) {
            return "--:--";
        }
        var mins = paceVal.toNumber();
        var secs = ((paceVal - mins) * 60.0).toNumber();
        return mins.format("%d") + ":" + secs.format("%02d");
    }

    function formatTime(totalSecs as Number) as String {
        var hours = totalSecs / 3600;
        var mins = (totalSecs % 3600) / 60;
        var secs = totalSecs % 60;
        if (hours > 0) {
            return hours.format("%d") + ":" + mins.format("%02d") + ":" + secs.format("%02d");
        }
        return mins.format("%d") + ":" + secs.format("%02d");
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Outer Orange Accent Ring
        dc.setPenWidth(4);
        dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(208, 208, 195);

        // Top: PACE
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT); 
        dc.drawText(208, 55, Graphics.FONT_XTINY, "PACE", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(208, 75, Graphics.FONT_NUMBER_HOT, formatPace(_lastPace), Graphics.TEXT_JUSTIFY_CENTER);

        // Middle Divider Line
        dc.setPenWidth(2);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(208, 175, 208, 255);

        // Middle Left: DISTANCE
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(106, 175, Graphics.FONT_XTINY, "DISTANCE", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(106, 195, Graphics.FONT_NUMBER_MEDIUM, _elapsedDistance.format("%.2f"), Graphics.TEXT_JUSTIFY_CENTER);

        // Middle Right: TIMER
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(310, 175, Graphics.FONT_XTINY, "TIMER", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(310, 195, Graphics.FONT_NUMBER_MEDIUM, formatTime(_elapsedSeconds), Graphics.TEXT_JUSTIFY_CENTER);

        // Bottom: HR
        dc.setColor(0x55AAFF, Graphics.COLOR_TRANSPARENT);
        dc.drawText(175, 295, Graphics.FONT_SMALL, "HR", Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        
        var hrDisplay = _lastHr > 0 ? _lastHr.toString() : "---";
        dc.drawText(240, 280, Graphics.FONT_NUMBER_HOT, hrDisplay, Graphics.TEXT_JUSTIFY_CENTER);

        if (!_isRecording) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(208, 135, Graphics.FONT_XTINY, "STOPPED - PRESS SELECT", Graphics.TEXT_JUSTIFY_CENTER);
        }

        var txStatus = CommManager.getInstance().txStatus;
        if (txStatus != null) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(208, 370, Graphics.FONT_XTINY, "TX: " + txStatus, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}
