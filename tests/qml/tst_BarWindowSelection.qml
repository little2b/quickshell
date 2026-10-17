import QtQuick
import QtTest
import "../../Common/functions/BarWindowSelection.js" as BarWindowSelection

TestCase {
    name: "BarWindowSelection"

    function test_background_data() {
        const first = {
            id: 1,
            isFloating: false,
            isMinimized: false
        };
        const second = {
            id: 2,
            isFloating: false,
            isMinimized: false
        };
        const translator = {
            id: 3,
            isFloating: true,
            isMinimized: false
        };
        const minimized = {
            id: 1,
            isFloating: false,
            isMinimized: true
        };
        return [
                    {
                        tag: "translation preserves background",
                        windows: [first, second, translator],
                        active: 3,
                        remembered: 1,
                        expected: 1
                    },
                    {
                        tag: "switching tiled window replaces background",
                        windows: [first, second, translator],
                        active: 2,
                        remembered: 1,
                        expected: 2
                    },
                    {
                        tag: "reload with one tiled window",
                        windows: [first, translator],
                        active: 3,
                        remembered: 0,
                        expected: 1
                    },
                    {
                        tag: "reload does not guess offscreen column",
                        windows: [first, second, translator],
                        active: 3,
                        remembered: 0,
                        expected: 0
                    },
                    {
                        tag: "closed or other workspace background ignored",
                        windows: [second, translator],
                        active: 3,
                        remembered: 1,
                        expected: 2
                    },
                    {
                        tag: "minimized background ignored",
                        windows: [minimized, translator],
                        active: 3,
                        remembered: 1,
                        expected: 0
                    },
                    {
                        tag: "background moved to floating",
                        windows: [
                            {
                                id: 1,
                                isFloating: true
                            },
                            translator],
                        active: 3,
                        remembered: 1,
                        expected: 0
                    },
                    {
                        tag: "empty workspace",
                        windows: [],
                        active: 0,
                        remembered: 1,
                        expected: 0
                    }
                ];
    }

    function test_background(data) {
        const background = BarWindowSelection.tiledBackground(data.windows, data.active, data.remembered);
        compare(background ? background.id : 0, data.expected);
    }
}
