import QtQuick
import QtQuick.Window

QtObject {
    required property Item target

    // Item.visible alone does not tell us whether its native window is mapped,
    // and a transparent ancestor can hide an otherwise visible item.
    readonly property bool active: {
        if (!target || target.width <= 0 || target.height <= 0)
            return false;
        const window = target.Window.window;
        if (!window || !window.visible)
            return false;
        for (let item = target; item; item = item.parent) {
            if (!item.visible || item.opacity <= 0)
                return false;
        }
        return true;
    }
}
