# Scroll Capture Stitching — Known Issues & Solutions

## Architecture Overview

- `ScrollCaptureManager` captures frames every 300ms via Timer
- `ImageStitcher.stitchWithDebug()` processes all frames after capture ends
- Overlap detection uses 4x downscaled thumbnails
- Algorithm: 1D row-projection pre-filtering → top 5 candidates → full pixel verification on all rows

## Issue 1: Blue Preview Border in First Frame
- **Symptom**: First captured frame contained the blue preview window border
- **Root cause**: Capture started before preview window fully dismissed
- **Fix**: Added 100ms delay before starting scroll capture (AppDelegate.swift)

## Issue 2: Frame Count Stuck at "1 Frames"
- **Symptom**: Scroll events not triggering captures
- **Root cause**: `NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel)` wasn't firing
- **Fix**: Replaced scroll-event-based capture with periodic Timer (300ms)

## Issue 3: Only Head+Tail Stitched
- **Symptom**: Multi-frame captures only stitched first and last frame
- **Root cause**: Old iterative approach was O(n²) with stale accumulated image comparisons
- **Fix**: Thumbnail-based detection + single-pass composition

## Issue 4: Overlap Search Range Too Small
- **Symptom**: Frame 7→8 had no overlap (score 29.25 > 25 threshold)
- **Root cause**: Search range capped at 90% (`bottomHeight * 9/10`), true overlap at ~90% fell outside
- **Fix**: Expanded maxOverlap to 97%, raised threshold to 35

## Issue 5: False Matches on Repetitive Content
- **Symptom**: YouTube search results caused false matches at 4-10% overlap
- **Root cause**: Sampling only 12 rows + early termination at score<10 let small false overlaps win
- **Fix**: Compare ALL rows (not 12), remove early termination, raise minOverlap to 20%

## Issue 6: Performance — Brute Force O(H²×W)
- **Symptom**: Slow stitching on many frames
- **Fix**: 1D row-projection pre-filtering. Compute per-row average brightness, use 1D cross-correlation to find top 5 candidate offsets, then full pixel verification only on ~15 candidates. ~10x speedup.

## Issue 7: Mouse Wheel Bounce / Page Bottom Bounce (Current)
- **Symptom**: Brief upward bounce during downward scroll causes frames to be unmatched, stitching breaks
- **Root cause**: Each frame only compared against last valid frame. If bounce frame is accepted with wrong overlap, or causes too many consecutive skips, subsequent frames can't match.
- **Fix**: Backtracking — when a frame fails to match lastValidIdx, try matching against up to 5 earlier valid frames. If match found, discard intermediate frames as bounce artifacts. Remove force-keep mechanism.

## Key Algorithm Parameters (ImageStitcher.swift)
- `scaleFactor = 4` — thumbnail downscale for overlap detection
- `minOverlap = 20%` — minimum overlap to consider (avoids false matches)
- `maxOverlap = 97%` — maximum overlap to search
- `bestScore threshold = 35.0` — max average pixel difference to accept
- `topN = 5` — candidates from 1D pre-filter
- `maxFrames = 100` — cap in ScrollCaptureManager

## Debug Mode
- Right-click scroll capture button → "Debug Mode"
- Saves all frames + stitch-log.txt to `/tmp/super-snip-debug/<timestamp>/`
- Opens Finder to the debug directory
