import QtQuick
import Quickshell
import Quickshell.Io
import qs.Modules.Launchpad
import qs.Services

Item {
    id: root

    Loader {
        active: LaunchpadService.visible
        sourceComponent: LaunchpadWindow {}
    }
    IpcHandler {
        target: "launchpad"
        function open(): bool {
            return LaunchpadService.open();
        }
        function close(): bool {
            LaunchpadService.close();
            return true;
        }
        function toggle(): bool {
            return LaunchpadService.toggle();
        }
    }

    // Recreate the layer surface when its anchoring topology changes.
    Variants {
        model: DockService.enabled && DockService.position === "bottom" ? Quickshell.screens : []
        DockSurface {
            required property var modelData
            screen: modelData
            edge: "bottom"
        }
    }
    Variants {
        model: DockService.enabled && DockService.position === "left" ? Quickshell.screens : []
        DockSurface {
            required property var modelData
            screen: modelData
            edge: "left"
        }
    }
    Variants {
        model: DockService.enabled && DockService.position === "right" ? Quickshell.screens : []
        DockSurface {
            required property var modelData
            screen: modelData
            edge: "right"
        }
    }
}
