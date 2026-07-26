import Toybox.WatchUi;
import Toybox.ActivityRecording;

class RunDelegate extends WatchUi.BehaviorDelegate {
    var session = null;

    function initialize() { BehaviorDelegate.initialize(); }

    // Top Right Button (Start/Stop Recording)
    function onSelect() {
        if (session == null) {
            session = ActivityRecording.createSession({:name=>"Run", :sport=>ActivityRecording.SPORT_RUNNING});
            session.start();
        } else if (session.isRecording()) {
            session.stop();
        } else {
            session.start();
        }
        return true;
    }

    // Up/Down Buttons (Open Settings SubMenu)
    function onNextPage() { return pushSubMenu(); }
    function onPreviousPage() { return pushSubMenu(); }
    
    function pushSubMenu() {
        var menu = new WatchUi.Menu2({:title=>"Run Settings"});
        menu.addItem(new WatchUi.MenuItem("Stream to HUD", null, "stream", null));
        menu.addItem(new WatchUi.MenuItem("Stop Run", null, "stop", null));
        WatchUi.pushView(menu, new RunMenuDelegate(), WatchUi.SLIDE_UP);
        return true; 
    }
}
