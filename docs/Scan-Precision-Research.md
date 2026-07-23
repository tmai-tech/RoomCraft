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

Without **ARCore depth / plane hit-testing** or **external laser**, RoomCraft **cannot** auto-measure walls from camera to professional tolerance. Phase roadmap: ARCore multi-dot tools (+123) + optional laser import (magicplan-class).

## Planner 5D room scan (research, +123)

Planner 5D ships **two** scan products (not one monocular photo → plan):

| Product | Platform | Input | How it works (public docs) |
|---------|----------|-------|----------------------------|
| **Scan Your Room** | iOS LiDAR Pro devices | Live AR walk | Point at bottom corner → move along floor & ceiling; Apple-class depth → layout / layout+furniture (cloud polish 3–10 min) |
| **Home Scan** | iOS + Android | Continuous video walk (10s–12 min) | Walk room(s) 1.5–2 m from walls, camera slightly down; **cloud** turns video into Basic (walls/structure) or Pro (catalog furniture, sockets, textures) plan |

Key UX truths from Planner 5D help (2026):

1. Lighting + open doors + **side-to-side motion** (not spinning in place).
2. Basic vs Pro share the same video input; Pro is denser reconstruction + catalog match.
3. They **do not** claim a single gallery photo equals a measured plan.

### Multi-dot / point-cloud mapping (what “good” looks like)

Industry pipeline (magicplan, RoomPlan, Matterport, Pointorama):

1. **Capture metric geometry** — LiDAR depth / ARCore hit-test / laser / multi-view SfM.
2. **Sparse or dense point set** on floors/walls (corners, plane inliers).
3. **Plane / wall segmentation** → polygon floor plan.
4. **Openings + furniture** as secondary labeling (vision or catalog).
5. **User verify** dimensions (tape/laser lock for pro accuracy).

RoomCraft **+123** implements the phone-grade step (1–3) as an **AR multi-dot floor map**: user marks 4 floor corners (sparse point cloud), reconstruct W×L from ordered opposite edges (`ArPolygonMap` / native `resolvePolygonMeters`). Metric scale is **ARCore world meters**, not photo guesswork.

### Python / open libraries for high-accuracy room mapping

| Library / stack | Role | Notes |
|-----------------|------|-------|
| **Open3D** | Plane RANSAC, room segmentation from point clouds | Best offline post-process if we export AR hits / depth |
| **RTAB-Map** | RGB-D SLAM + 2D occupancy | Android/ROS; heavier than in-app AR |
| **ORB-SLAM3 / OpenVSLAM** | Visual SLAM trajectories | Needs careful mobile packaging |
| **AliceVision Meshroom** | Photogrammetry dense cloud from video | Offline only; minutes–hours |
| **scipy.spatial / shapely** | Convex hull, polygon simplify of floor points | Matches our multi-dot math |
| **ARCore Depth API / Geospatial** | On-device depth frames | Optional denser dots without LiDAR |
| **Apple RoomPlan** (iOS only) | Parametric walls+furniture | No Android equivalent |

Practical RoomCraft path: **AR multi-dot primary** → optional photo inventory → Review edits. Full Meshroom/Open3D is colab/offline experiments (`experiments/colab`), not on-device MVP.

## Capture tips (best results today)

1. Prefer **AR Room Planner → 4-corner multi-dot** (or tape Field measure).
2. Good lighting; walk corners slowly; wait for floor grid / Tracking before Mark.
3. If AR camera stays black: update **Google Play Services for AR**, re-grant camera.
4. Standard door ~2.5–3 ft; don’t accept AI whole-wall doors on photo path.
5. Furniture: catalog sizes + depth from wall; center from left corner.
6. In Review, fix openings before opening the editor.

## Sources (industry)

- Planner 5D Home Scan / Scan Your Room help (video walk + LiDAR iOS)
- magicplan: AR room scan, laser for 100% wall lock, LiDAR assist on supported devices
- Apple RoomPlan: LiDAR parametric walls/furniture; ~few % wall error in studies
- Designer field measure guides: clockwise wall chains, openings not trim, overall then detail
- ARCore Instant Placement + horizontal planes: multi-dot floor hits without dense mesh
- Open3D / RTAB-Map / Meshroom: open pipelines for denser reconstruction offline
