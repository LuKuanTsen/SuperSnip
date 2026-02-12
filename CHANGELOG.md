# Changelog

## [0.0.2] - 2026-02-12

### Features
- Freehand drawing with 3 brush sizes (S/M/L) and 6 colors
- Mosaic (pixelation) brush for redacting sensitive content
- Undo/Redo support in both editing and preview modes
- GIF screen recording (8 FPS, up to 30 seconds)
- Animated GIF playback in pin window preview
- App now appears in Dock with right-click "Capture Area" menu

### Improvements
- Scroll capture stitching now compares against accumulated image for better accuracy
- GIF copied to clipboard as file URL for broad app compatibility
- Hide draw/mosaic buttons on GIF pin windows

### Fixes
- ESC monitor cleanup on app termination
- Clipboard overwrite behavior (only copies on explicit action)
- Resize event loop edge case

## [0.0.1] - 2026-02-11

First pre-release.

### Features
- Area screenshot with crosshair overlay (`Cmd + Shift + S`)
- Multi-monitor support
- Preview toolbar with copy, save, pin, and scroll capture
- Pin screenshots as floating windows (drag, resize, ESC to close)
- Scrolling capture with automatic image stitching
- Scroll capture debug mode (right-click scroll capture button)
