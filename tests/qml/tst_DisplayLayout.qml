import QtQuick
import QtTest
import "../../Modules/ControlCenter/DisplayLayout.js" as Geometry

TestCase {
    name: "DisplayLayout"

    function test_scaledAndRotatedLogicalDimensions() {
        const outputs = [
                  {
                      name: "A",
                      logical: {
                          x: 0,
                          y: 0,
                          width: 1920,
                          height: 1080
                      }
                  },
                  {
                      name: "B",
                      logical: {
                          x: -1080,
                          y: -200,
                          width: 1080,
                          height: 1920
                      }
                  }
              ];
        const screens = Geometry.rectangles(outputs, {});
        compare(Geometry.bounds(screens), {
                    x: -1080,
                    y: -200,
                    width: 3000,
                    height: 1920
                });
        verify(!Geometry.hasOverlap(screens));
    }

    function test_touchingEdgesAreAllowed() {
        const a = {
            x: 0,
            y: 0,
            width: 1920,
            height: 1080
        };
        verify(!Geometry.overlaps(a, {
                                      x: 1920,
                                      y: 0,
                                      width: 1280,
                                      height: 720
                                  }));
        verify(Geometry.overlaps(a, {
                                     x: 1919,
                                     y: 0,
                                     width: 1280,
                                     height: 720
                                 }));
    }

    function test_nearEdgesSnapWithoutOverlap() {
        const a = {
            name: "A",
            x: 0,
            y: 0,
            width: 1920,
            height: 1080
        };
        const b = {
            name: "B",
            x: 1905,
            y: 7,
            width: 1280,
            height: 720
        };
        compare(Geometry.snap(b, [a, b], 20), {
                    x: 1920,
                    y: 0
                });
    }

    function test_distantEdgesDoNotSnap() {
        const a = {
            name: "A",
            x: 0,
            y: 0,
            width: 1920,
            height: 1080
        };
        const b = {
            name: "B",
            x: 1905,
            y: 3000,
            width: 1280,
            height: 720
        };
        compare(Geometry.snap(b, [a, b], 20), {
                    x: 1905,
                    y: 3000
                });
    }

    function test_horizontalAndVerticalArrangement() {
        const screens = [
                  {
                      name: "A",
                      width: 1920,
                      height: 1080
                  },
                  {
                      name: "B",
                      width: 1080,
                      height: 1920
                  }
              ];
        compare(Geometry.arrange(screens, false), {
                    A: {
                        x: 0,
                        y: 0
                    },
                    B: {
                        x: 1920,
                        y: 0
                    }
                });
        compare(Geometry.arrange(screens, true), {
                    A: {
                        x: 0,
                        y: 0
                    },
                    B: {
                        x: 0,
                        y: 1080
                    }
                });
    }
}
