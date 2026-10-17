.pragma library

// Only consider the supplied workspace. A different scrolling column may be
// offscreen, so never guess between multiple tiled windows after a reload.
function tiledBackground(windows, activeWindowId, rememberedWindowId) {
    const tiled = windows.filter(window => !window.isFloating && !window.isMinimized);
    return tiled.find(window => window.id === activeWindowId)
            || tiled.find(window => window.id === rememberedWindowId)
            || (tiled.length === 1 ? tiled[0] : null);
}
