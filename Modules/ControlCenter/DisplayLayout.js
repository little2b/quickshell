function rectangles(outputs, positions) {
    return outputs.map(function(output) {
        const p = positions[output.name] || output.logical;
        return {name: output.name, x: p.x, y: p.y,
            width: output.logical.width, height: output.logical.height};
    });
}

function bounds(screens) {
    if (!screens.length)
        return {x: 0, y: 0, width: 1, height: 1};
    const x = Math.min.apply(null, screens.map(function(s) { return s.x; }));
    const y = Math.min.apply(null, screens.map(function(s) { return s.y; }));
    return {x: x, y: y,
        width: Math.max.apply(null, screens.map(function(s) { return s.x + s.width; })) - x,
        height: Math.max.apply(null, screens.map(function(s) { return s.y + s.height; })) - y};
}

function overlaps(a, b) {
    return a.x < b.x + b.width && b.x < a.x + a.width
        && a.y < b.y + b.height && b.y < a.y + a.height;
}

function hasOverlap(screens) {
    return screens.some(function(a, i) {
        return screens.some(function(b, j) { return i < j && overlaps(a, b); });
    });
}

function snap(moving, screens, tolerance) {
    let x = moving.x;
    let y = moving.y;
    let dx = tolerance;
    let dy = tolerance;
    screens.forEach(function(other) {
        if (other.name === moving.name)
            return;
        // Only snap to nearby screens, not unrelated edges across the desktop.
        if (moving.y <= other.y + other.height + tolerance && moving.y + moving.height >= other.y - tolerance) {
            [other.x - moving.width, other.x, other.x + other.width - moving.width, other.x + other.width].forEach(function(value) {
                if (Math.abs(value - moving.x) < dx) {
                    x = value;
                    dx = Math.abs(value - moving.x);
                }
            });
        }
        if (moving.x <= other.x + other.width + tolerance && moving.x + moving.width >= other.x - tolerance) {
            [other.y - moving.height, other.y, other.y + other.height - moving.height, other.y + other.height].forEach(function(value) {
                if (Math.abs(value - moving.y) < dy) {
                    y = value;
                    dy = Math.abs(value - moving.y);
                }
            });
        }
    });
    return {x: Math.round(x), y: Math.round(y)};
}

function arrange(screens, vertical) {
    let offset = 0;
    const positions = {};
    screens.forEach(function(screen) {
        positions[screen.name] = {x: vertical ? 0 : offset, y: vertical ? offset : 0};
        offset += vertical ? screen.height : screen.width;
    });
    return positions;
}
