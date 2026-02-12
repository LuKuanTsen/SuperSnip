# Code Review Findings (2026-02-12)

## Critical
1. **ESC monitor local-only** — scroll capture & GIF recording use `addLocalMonitorForEvents` only. Need `addGlobalMonitorForEvents` too since user is in other apps during capture. (Task #6)

## Important
2. **ClipboardManager 2x on Retina** — `NSImage` created with pixel dims, not point dims. Pasted images appear 2x in other apps. (Task #8)
3. **Missing applicationShouldHandleReopen** — Dock icon click does nothing when no windows visible. (Task #9)
4. **Duplicated frame comparison code** — `framesAreNearlyIdentical` + `pixelRow` copied between ScrollCaptureManager and GifRecordingManager. (Task #11)
5. **Hardcoded GIF pasteboard type** — Use `UTType.gif.identifier` instead of `"com.compuserve.gif"`. (Task #12)
6. **No applicationWillTerminate** — Hotkey, timers, monitors not cleaned up on exit. (Task #13)
7. **Duplicated pin window size calc** — Same display size logic in handleScrollCaptureComplete and handleGifRecordingComplete. (Task #14)

## Completed
- ✅ Timer capture moved to background thread (DispatchSourceTimer + background queue)
- ✅ Double-stop guard (isStopped flag) added to both managers
- ✅ Save dialog converted to beginSheetModal (standard macOS pattern)
- ✅ Dock app conversion (LSUIElement=false, removed MenuBarExtra)

## Minor (deferred)
- OverlayWindow uses .screenSaver level (unconventional)
- AppDelegate becoming god object (~557 lines)
- asyncAfter delays for window disappearance are fragile
- RecordingIndicator pulse animation may not trigger reliably
- No VoiceOver/accessibility support
