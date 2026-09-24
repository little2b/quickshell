import QtQuick
import QtQuick.Effects
import qs.Common
import qs.Services

Item {
    id: root

    property string screenName: ""
    readonly property string wallpaperPath: WallpaperService.overviewWallpaperForScreen(screenName)
    readonly property bool imageWallpaper: WallpaperService.isImagePath(wallpaperPath)
    readonly property bool ready: !imageWallpaper || wallpaper.status === Image.Ready || wallpaper.status
                                  === Image.Error
    // Keep a decoded thumbnail and filter at this small size. The final
    // texture is enlarged only after blurring, including during transitions.
    property size viewportSize: Qt.size(width, height)
    readonly property size sampleSize: {
        const targetWidth = Math.max(1, viewportSize.width);
        const targetHeight = Math.max(1, viewportSize.height);
        const ratio = Math.min(1, 720 / Math.max(targetWidth, targetHeight));
        return Qt.size(Math.max(1, Math.round(targetWidth * ratio)), Math.max(1, Math.round(targetHeight
                                                                                            * ratio)));
    }

    Rectangle {
        anchors.fill: parent
        color: "#202938"
    }
    Image {
        id: wallpaper
        width: root.sampleSize.width
        height: root.sampleSize.height
        source: root.imageWallpaper ? Paths.fileUrl(root.wallpaperPath) : ""
        sourceSize: root.sampleSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        retainWhileLoading: true
        visible: false
    }
    MultiEffect {
        width: root.sampleSize.width
        height: root.sampleSize.height
        source: wallpaper
        blurEnabled: true
        blurMax: 32
        blur: 1
        saturation: -0.15
        autoPaddingEnabled: false
        visible: root.imageWallpaper
        transform: Scale {
            xScale: root.width / root.sampleSize.width
            yScale: root.height / root.sampleSize.height
        }
    }
    Rectangle {
        anchors.fill: parent
        color: "#730c1220"
    }
}
