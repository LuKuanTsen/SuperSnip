# Super Snip - Development Notes

## Build & Run

- Build: `swift build`
- Run: `swift run`
- No xcodebuild (active developer directory is CommandLineTools, not Xcode)

## Workflow

- Always run `swift run` in the background after completing changes (use `run_in_background`). No need to stop it during edits, but restart it when edits are done.

## Architecture

- **Per-screen overlays**: One `OverlayWindow` per screen with shared `SelectionCoordinator` (global screen coordinates)
- **Scroll capture**: Timer-based (300ms), thumbnail overlap detection with 1D row-projection pre-filtering
- **Unified floating window**: `PinWindow` is the single window type for all capture results (no separate preview window)
- **Custom drag/resize**: Not `isMovableByWindowBackground`; `constrainFrameRect` override for free movement
- **Debug output**: Scroll capture saves frames + stitch log to `/tmp/super-snip-debug/`

## Window State Machine

All capture results use `PinWindow` with a `WindowMode` that determines toolbar buttons and behavior.

```
               Cmd+Shift+S / Dock menu
                       │
                       ▼
                  SELECTING
                  │       │
               cancel   complete
                  │       │
                  ▼       ▼
                IDLE ◄── FLOATING [firstPreview]
                  ▲      │  ▲  │
                  │      │  │  │  drag/resize anytime
                  │  draw/mosaic  done/cancel
                  │      │  │
                  │      ▼  │
                  │    EDITING ──→ FLOATING [pinned]
                  │
                  │   scrollCapture        recordGif
                  │       │                    │
                  │       ▼                    ▼
                  │  SCROLL_CAPTURING    GIF_COUNTDOWN
                  │       │                 │     │
                  │      done              3s    ESC
                  │       │                │     │
                  │       ▼           GIF_RECORDING │
                  │  FLOATING [pinned]     │     │
                  │                       done   │
                  │                        │     │
                  │                        ▼     │
                  │                   FLOATING [gif]
                  │                        │
                  │                   copy/save/close
                  └────────────────────────┘
```

### WindowMode

| Mode | Description | Toolbar buttons |
|------|-------------|-----------------|
| `.firstPreview` | Initial capture result | copy, save, draw, mosaic, undo/redo, GIF, scroll capture, cancel |
| `.pinned` | From scroll capture or after editing | copy, save, draw, mosaic, undo/redo, close |
| `.gif` | Animated GIF result | copy, save, close |

### Key behaviors

- **No separate preview window** — capture result is immediately a draggable/resizable `PinWindow`
- **Editing in-place** — draw/mosaic opens canvas on the same window; Done returns to same window
- **Mode transition** — `.firstPreview` → `.pinned` after editing (scroll/GIF buttons removed)
- **Copy/Save don't dismiss** — window stays open, user closes explicitly
- **Toolbar on hover** — appears on mouse-enter, hides on mouse-exit (150ms delay)
- **First preview exception** — toolbar visible immediately until first mouse-exit
- **Multiple windows** — each capture/scroll/GIF result is independent, can coexist
