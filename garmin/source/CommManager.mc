import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class CommManager {
    static var _instance;
    var _isTransmitting = false;
    var txStatus = "IDLE";

    static function getInstance() {
        if (_instance == null) {
            _instance = new CommManager();
        }
        return _instance;
    }

    function sendCommand(data) {
        if (_isTransmitting) {
            System.println("CommManager: BUSY, dropping packet");
            txStatus = "BUSY_DROP";
            return false;
        }

        try {
            _isTransmitting = true;
            txStatus = "SENDING...";
            var listener = new CommListener();
            System.println("CommManager: Invoking Communications.transmit");
            Communications.transmit(data, null, listener);
            return true;
        } catch (e) {
            _isTransmitting = false;
            txStatus = "EXCEPTION";
            System.println("CommManager Exception");
            return false;
        }
    }

    function onTxComplete(success) {
        _isTransmitting = false;
        if (success) {
            txStatus = "SUCCESS";
            System.println("CommManager: TX SUCCESS");
        } else {
            txStatus = "FAIL";
            System.println("CommManager: TX FAIL");
        }
        WatchUi.requestUpdate();
    }
}

class CommListener extends Communications.ConnectionListener {
    function initialize() {
        ConnectionListener.initialize();
    }

    function onComplete() as Void {
        CommManager.getInstance().onTxComplete(true);
    }

    function onError() as Void {
        CommManager.getInstance().onTxComplete(false);
    }
}
