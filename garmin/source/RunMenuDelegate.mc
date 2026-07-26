import Toybox.WatchUi;
import Toybox.System;

class RunMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() { Menu2InputDelegate.initialize(); }
    
    function onSelect(item) {
        System.println("Menu Selected: " + item.getId());
        if (item.getId().equals("stream")) {
            isStreaming = true;
        } else if (item.getId().equals("stop")) {
            isStreaming = false;
        }
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}
