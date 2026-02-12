# Super Snip

A lightweight, open-source screenshot tool for macOS.

## Features

- **Area Capture** -- Select any region of the screen with a crosshair overlay
- **Multi-Monitor Support** -- Works across multiple displays
- **Preview & Pin** -- Pin screenshots as floating windows; freely drag, resize, copy, or save
- **Drawing** -- Annotate screenshots with freehand drawing (3 brush sizes, 6 colors)
- **Mosaic** -- Redact sensitive content with a pixelation brush
- **GIF Recording** -- Record screen area as animated GIF (up to 30 seconds)
- **Scrolling Capture** -- Automatically capture and stitch long scrollable content
- **Undo/Redo** -- Full undo/redo support for editing
- **Global Hotkey** -- Trigger capture with `Cmd + Shift + S` from anywhere

## Requirements

- macOS 13.0 (Ventura) or later
- Screen Recording permission (the app will prompt on first launch)

## Install

### From GitHub Releases

Download the latest `.zip` from the [Releases](https://github.com/LuKuanTsen/SuperSnip/releases) page, unzip, and move `Super Snip.app` to your Applications folder.

> **Note:** The app is ad-hoc signed (not notarized by Apple). You need to remove the quarantine attribute before opening:
>
> ```bash
> xattr -cr /path/to/Super\ Snip.app
> ```
>
> Replace `/path/to/` with the actual location (e.g. `~/Downloads/`).

### From Source

```bash
git clone https://github.com/LuKuanTsen/SuperSnip.git
cd SuperSnip
swift build -c release
```

The built binary is at `.build/release/SuperSnip`.

## Usage

1. Press `Cmd + Shift + S` (or right-click the Dock icon → **Capture Area**) to start
2. Click and drag to select a region
3. A preview window appears with options:
   - **Copy** to clipboard
   - **Save** to file
   - **Pin** as a floating window
   - **Draw** -- annotate with freehand drawing
   - **Mosaic** -- pixelate sensitive areas
   - **Record GIF** -- record the selected area as animated GIF
   - **Scroll Capture** -- capture long scrollable content

### Drawing & Mosaic

1. Click the pencil (draw) or grid (mosaic) icon in the preview toolbar
2. Choose brush size (S/M/L) and color (draw only)
3. Draw on the image, use **Undo** to remove strokes
4. Click the checkmark to apply, or `Esc` to discard

### GIF Recording

1. Select an area, then click the record button in the preview toolbar
2. The area starts recording at 8 FPS with a red indicator
3. Click **Done** or press `Esc` to stop
4. The animated GIF is copied to clipboard and shown in a pin window

### Scrolling Capture

1. Select the scrollable area, then click the scroll capture button
2. Scroll through the content at a steady pace
3. Press `Esc` to finish -- frames are automatically stitched together

### Pinned Windows

- Drag to move (can extend beyond screen edges)
- Resize from the bottom-right handle
- Press `Esc` to close
- Hover to show toolbar (copy, save, draw, mosaic, close)

## Tech Stack

- Swift + AppKit (no Electron, no SwiftUI for core UI)
- ScreenCaptureKit for screen capture
- Custom image stitching with 1D row-projection pre-filtering
- ImageIO for GIF encoding

## License

[GPLv3](LICENSE)
