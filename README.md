# Super Snip

A lightweight, open-source screenshot tool for macOS.

## Features

- **Area Capture** -- Select any region of the screen with a crosshair overlay
- **Multi-Monitor Support** -- Works across multiple displays
- **Preview & Pin** -- Pin screenshots as floating windows on your desktop; freely drag, resize, copy, or save
- **Scrolling Capture** -- Automatically capture and stitch long scrollable content into a single image
- **Global Hotkey** -- Trigger capture with `Cmd + Shift + S` from anywhere

## Requirements

- macOS 13.0 (Ventura) or later
- Screen Recording permission (the app will prompt on first launch)

## Install

### From Source

```bash
git clone https://github.com/LuKuanTsen/SuperSnip.git
cd SuperSnip
swift build -c release
```

The built binary is at `.build/release/SuperSnip`. Run it directly or copy it to a location of your choice.

### From GitHub Releases

Download the latest `.zip` from the [Releases](https://github.com/LuKuanTsen/SuperSnip/releases) page, unzip, and move `Super Snip.app` to your Applications folder.

> **Note:** The app is not notarized. On first launch, right-click the app and select **Open**, then click **Open** in the dialog to bypass Gatekeeper.

## Usage

1. Press `Cmd + Shift + S` (or click the menu bar icon) to start a capture
2. Click and drag to select a region
3. A preview window appears with options:
   - **Copy** to clipboard
   - **Save** to file
   - **Pin** as a floating window
   - **Scroll Capture** for long content
4. Pinned windows can be dragged, resized (bottom-right handle), and closed with `Esc`

### Scrolling Capture

1. Select the scrollable area, then click the scroll capture button in the preview toolbar
2. Scroll through the content at a steady pace
3. Press `Esc` to finish -- the captured frames are automatically stitched together

## Tech Stack

- Swift + AppKit (no Electron, no SwiftUI for core UI)
- ScreenCaptureKit for screen capture
- Custom image stitching with 1D row-projection pre-filtering for overlap detection

## License

[GPLv3](LICENSE)
