# Scan precision research (2026)

## Why photo-only AI is wrong for walls / doors / furniture

RoomCraft is a Flutter Android app. Uploading photos and asking a vision LLM for XY feet **cannot** match measured floor plans:

| Method | Typical error | Notes |
|--------|---------------|-------|
| Monocular photo → LLM layout | Often **meters off**, wrong walls | No metric scale; perspective distortion; hallucinated furniture |
| magicplan AR camera scan | ~**5–15%** room size if used carefully | Corner/wall detection; lighting critical |
| magicplan + Bluetooth laser | ~**mm–cm** on locked walls | Pros treat laser as ground truth |
| Apple RoomPlan (LiDAR) | often **&lt;5%** wall error | Parametric walls + furniture; still not CAD-perfect |
| Houzz Pro / Twindo (Canvas) LiDAR | field as-builts | Pros still verify hard measurements |
| Interior designer **field measure** | plan truth | Tape/laser + sketch; openings as chain dimensions |

**Competitors never claim “one photo = accurate plan.”** They use AR geometry, LiDAR, laser meters, or human measure + CAD polish.

## How interior designers map a room

From professional field-measure practice:

1. **Overall** wall-to-wall width × length (and diagonals if irregular).
2. **Walk clockwise** each wall: from corner → first opening → opening clear width → next → end.
3. Measure openings **to rough opening / jamb**, not decorative trim (note trim separately).
4. Mark **door swing**, window type, fixed units, columns.
5. Furniture: measure **along wall from corner** + **depth into room** (or clearances).
6. Transfer to scaled plan (¼" = 1' etc.) — software only after numbers exist.

## What RoomCraft does now (precision stack)

### 1. Field measure (default, highest precision without LiDAR)
- User enters W × L (tape).
- Per wall A–D: door / window / balcony as **from left corner (facing wall) + width**.
- Furniture: wall + center from left + depth + catalog size.
- Optional photo + **AI suggest** fills drafts — **user must verify with tape**.
- Compose is deterministic geometry (no freeform XY guess).

### 2. Wall photos + AI (assistive)
- One photo per wall; vision returns feet-along-wall + priors (door ~3 ft, etc.).
- **Facing-wall left→right** coordinate system (fixed bug vs plan CCW).
- Confidence filters; Review screen edits openings in feet.

### 3. Free photos / video (lowest accuracy)
- Multi-pass vision; size still locked to user measure.
- Expect wrong placement — prefer field measure.

### 4. Review
- Edit / add / delete openings with tape distances.
- Toggle furniture; open editor for final polish.

## Hard accuracy ceiling (honest)

Without **ARCore depth / plane hit-testing** or **external laser**, RoomCraft **cannot** auto-measure walls from camera to professional tolerance. Phase roadmap: ARCore wall length tools + optional laser import (magicplan-class).

## Capture tips (best results today)

1. Tape room W × L first — this is plan scale.
2. Use **Field measure**; for each wall stand facing it; measure left→openings.
3. Standard door ~2.5–3 ft; don’t accept AI whole-wall doors.
4. Balcony = large glazed opening, not a small window.
5. Furniture: catalog sizes + depth from wall; center from left corner.
6. In Review, fix any wrong opening before opening the editor.

## Sources (industry)

- magicplan: AR room scan, laser for 100% wall lock, LiDAR assist on supported devices
- Apple RoomPlan: LiDAR parametric walls/furniture; ~few % wall error in studies
- Designer field measure guides: clockwise wall chains, openings not trim, overall then detail
- ARCore Depth API: depth maps / hit tests for future Android measure (no RoomPlan equivalent yet)
