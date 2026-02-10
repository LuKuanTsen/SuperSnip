# Super Snip - macOS Screenshot Tool Design

## Overview

Super Snip is a native macOS menu bar application for screen capture with built-in editing and annotation tools. Built with SwiftUI + AppKit, using ScreenCaptureKit for capture.

## Core Decisions

- **Tech Stack**: SwiftUI (UI) + AppKit (window management, global hotkeys) + ScreenCaptureKit (capture)
- **App Type**: Menu Bar app, no Dock icon
- **Min Target**: macOS 13+ (ScreenCaptureKit requirement)

## Feature Scope

### Phase 1 - Basic Area Screenshot
- Global hotkey triggers area selection
- Full-screen overlay with crosshair cursor
- Click-drag to select region, shows dimension label (W x H pt)
- ESC to cancel
- Capture selected region, display screenshot in-place with action toolbar

### Phase 2 - Action Toolbar
After capture, screenshot stays on screen with toolbar below:
- **Copy to clipboard** - copies image and dismisses
- **Save to file** - file dialog, save as PNG/JPG
- **Edit** - enters editing mode (Phase 3)
- **Pin to screen** - creates always-on-top floating window with the screenshot
- **Cancel (X)** - dismisses screenshot

### Phase 3 - Editing Tools
In-place annotation on the captured screenshot:
- **Draw line** - freehand or straight line (shift-constrained)
- **Draw rectangle** - outline rectangle
- **Draw circle/ellipse** - outline ellipse
- **Mosaic/blur** - brush that pixelates the area underneath
- **Undo / Redo**
- Color picker + stroke width for drawing tools

### Phase 4 - Scrolling Capture
- After selecting a region, enter "scroll capture" mode
- Detect scroll events within the region
- Capture frames on each scroll tick
- Use pixel-overlap detection to find seams between consecutive frames
- Stitch frames into a single long image, removing duplicate overlap
- Same action toolbar after completion

## Architecture

```
SuperSnip/
  App/
    SuperSnipApp.swift          # @main, MenuBarExtra, app lifecycle
    AppState.swift              # Global state: mode, settings, hotkeys
  Capture/
    ScreenCaptureManager.swift  # ScreenCaptureKit wrapper
    OverlayWindow.swift         # Full-screen transparent overlay for selection
    SelectionView.swift         # Crosshair + drag-to-select UI
    RegionSelector.swift        # Handles mouse events, computes selected rect
  Preview/
    CapturePreviewWindow.swift  # Borderless window showing captured image in-place
    ActionToolbar.swift         # Toolbar with copy/save/edit/pin/cancel buttons
    PinWindow.swift             # Always-on-top floating window for pinned screenshots
  Editor/
    EditorView.swift            # Main editing canvas (SwiftUI)
    AnnotationCanvas.swift      # Drawing layer using Core Graphics
    Tools/
      LineTool.swift
      RectangleTool.swift
      EllipseTool.swift
      MosaicTool.swift
    AnnotationState.swift       # Undo/redo stack, current tool, color, stroke
  ScrollCapture/
    ScrollCaptureManager.swift  # Orchestrates scroll detection + multi-frame capture
    ImageStitcher.swift         # Overlap detection + stitching algorithm
  Utilities/
    HotkeyManager.swift        # Global keyboard shortcut registration
    ClipboardManager.swift      # NSPasteboard helper
    ImageExporter.swift         # Save to file (PNG/JPG)
```

## Key Technical Details

### Screen Capture
- Use `SCScreenshotManager` for single-frame capture (macOS 14+), fallback to `CGWindowListCreateImage` for macOS 13
- Request screen recording permission on first launch

### Overlay Window
- `NSPanel` with `.borderless` style, covers all screens
- `level = .screenSaver` so it's above everything
- Transparent background, captures all mouse events
- SwiftUI view inside for the selection rectangle rendering

### Preview Window
- `NSPanel` positioned exactly at the captured region
- `.floating` level, no title bar
- Toolbar appears below the image

### Pin Window
- `NSPanel` with `.floating` level
- Draggable, resizable, click-through toggle
- Close button on hover

### Editing
- Core Graphics based drawing on an offscreen `CGContext`
- Each annotation is a struct (type, points, color, strokeWidth)
- Canvas renders: base image + all annotations
- Mosaic: read pixels in brush area, downscale then upscale (pixelate effect)

### Scrolling Capture
- Monitor `NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel)` within the selected region
- On each scroll event, wait for screen to settle, then capture frame
- Overlap detection: compare bottom N rows of previous frame with top N rows of new frame using pixel similarity (e.g., sum of squared differences)
- Find best alignment offset, crop overlap, vertically concatenate

### Global Hotkey
- Use `NSEvent.addGlobalMonitorForEvents(matching: .keyDown)` or Carbon `RegisterEventHotKey` for reliable global hotkey
- Default: Cmd+Shift+4 (configurable)
