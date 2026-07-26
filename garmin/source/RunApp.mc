import Toybox.Application;
import Toybox.WatchUi;

var isStreaming = true;

class RemoteApp extends Application.AppBase {
    function initialize() { AppBase.initialize(); }
    function onStart(state) {}
    function onStop(state) {}
    function getInitialView() {
        return [ new RunView(), new RunDelegate() ];
    }
}
