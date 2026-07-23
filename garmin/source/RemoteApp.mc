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
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);

        var width = dc.getWidth();
        var height = dc.getHeight();

        if (!_isRecording) {
            dc.drawText(width / 2, height / 2 - 20, Graphics.FONT_MEDIUM, "PRESS SELECT", Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(width / 2, height / 2 + 15, Graphics.FONT_SMALL, "TO START RUN", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        // Top: Pace
        var paceStr = formatPace(_lastPace) + " min/km";
        dc.drawText(width / 2, 50, Graphics.FONT_LARGE, paceStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Center: HR (Shifted down to eliminate dead space in middle)
        var hrStr = _lastHr.toString() + " bpm";
        dc.drawText(width / 2, height / 2 - 20, Graphics.FONT_NUMBER_HOT, hrStr, Graphics.TEXT_JUSTIFY_CENTER);

        // Bottom: Distance & Time (Moved up from outer bezel crop)
        var distStr = _elapsedDistance.format("%.2f") + " km";
        var timeStr = formatTime(_elapsedSeconds);

        dc.drawText(50, height - 90, Graphics.FONT_MEDIUM, distStr, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(width - 50, height - 90, Graphics.FONT_MEDIUM, timeStr, Graphics.TEXT_JUSTIFY_RIGHT);
        
        var txStatus = CommManager.getInstance().txStatus;
        if (txStatus != null) {
            dc.drawText(width / 2, height - 35, Graphics.FONT_XTINY, "TX: " + txStatus, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
}
