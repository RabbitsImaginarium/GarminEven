import Toybox.WatchUi;

class RemoteDelegate extends WatchUi.BehaviorDelegate {
    private var _view;

    function initialize(view) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() {
        _view.toggleRecording();
        return true;
    }
}
