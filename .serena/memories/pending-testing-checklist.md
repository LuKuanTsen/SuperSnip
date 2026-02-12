# Pending Testing Checklist - Drawing & Mosaic Editing

## Features to Test

### 1. Drawing (Pencil)
- Cmd+Shift+S → capture → click pencil → select color/size → draw lines → Done → Copy → paste in Preview to verify

### 2. Mosaic
- Capture → click mosaic → brush over text → Done → verify pixelation covers correctly
- Repeated brushing over same area should produce denser mosaic (random grid offset per stroke)

### 3. Cross-session Undo
- Draw a few strokes → Done → re-enter drawing → press Undo → should revert to earlier strokes

### 4. Preview Toolbar Undo/Redo
- After edits, toolbar shows undo/redo buttons → click to undo/redo without entering edit mode
- Cmd+Z / Cmd+Shift+Z also work in preview mode

### 5. Draggable Preview
- After capture, drag the preview window freely

### 6. Brush Size Memory
- Change brush size → exit editing → re-enter → should remember last size and color

### 7. Pin Window Editing
- Capture → Pin → hover to show toolbar → click pencil or mosaic → edit → verify

### 8. Brush Preview Circle
- In editing mode, cursor shows a circle indicating brush size

## Commits
- `6906b73` feat: add drawing and mosaic editing canvas and toolbar
- `4f6463c` feat: integrate editing mode with preview toolbar and undo/redo
- `fc976fe` feat: add draw/mosaic editing to pin windows
