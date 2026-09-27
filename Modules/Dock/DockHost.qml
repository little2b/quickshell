import QtQuick
import Quickshell
import Quickshell.Io
import qs.Modules.Launchpad
import qs.Services

Item {
    id: root

    // Retain the menu, its decoded icons and page snapshots between sessions.
    LazyLoader {
        active: LaunchpadService.backendReady && !LaunchpadService.externalEnabled
        LaunchpadWindow {}
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
        function status(): string {
            return JSON.stringify({
                                      backend: LaunchpadService.externalEnabled ? "external" : "builtin",
                                      available: LaunchpadService.externalAvailable,
                                      visible: LaunchpadService.visible,
                                      chromeHold: LaunchpadService.chromeHold
                                  });
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
