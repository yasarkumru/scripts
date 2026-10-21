// Exempt fullscreen windows from opacity window-rules.
// When a window goes fullscreen (e.g. YouTube fullscreen), force opacity to 1.0.
// When it leaves fullscreen, restore the previous opacity.

var savedOpacity = new Map();

function handleFullscreen(window) {
    if (!window || window.deleted) {
        return;
    }
    if (window.fullScreen) {
        if (!savedOpacity.has(window)) {
            savedOpacity.set(window, window.opacity);
        }
        window.opacity = 1.0;
    } else {
        if (savedOpacity.has(window)) {
            window.opacity = savedOpacity.get(window);
            savedOpacity.delete(window);
        }
    }
}

function watchWindow(window) {
    if (!window || window.deleted) {
        return;
    }
    // Apply current state (covers windows that start fullscreen)
    handleFullscreen(window);
    try {
        window.fullScreenChanged.connect(function () {
            handleFullscreen(window);
        });
    } catch (e) {}
    try {
        window.closed.connect(function () {
            savedOpacity.delete(window);
        });
    } catch (e) {}
}

function getAllWindows() {
    try {
        if (typeof workspace.windowList === "function") {
            return workspace.windowList();
        }
    } catch (e) {}
    try {
        return workspace.stackingOrder;
    } catch (e) {}
    return [];
}

getAllWindows().forEach(watchWindow);

try {
    workspace.windowAdded.connect(watchWindow);
} catch (e) {}
