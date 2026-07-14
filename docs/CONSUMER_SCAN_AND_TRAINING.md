# Consumer scan + accuracy training (RoomCraft)

**Goal:** A normal person uploads room **photos or a walkaround video** — no tape measure — and gets a **usable top-down plan** for furniture layout.

## Reality check (industry)

| Approach | Typical accuracy | Needs user skill |
|----------|------------------|------------------|
| Photo → generic LLM XY | Often meters off | Low |
| Photo + **object priors** (doors, beds) | Rough layout OK | Low |
| Multi-view / depth model | Better geometry | Low |
| ARCore depth / planes | magicplan-class | Low–medium |
| LiDAR (RoomPlan) | Best phone accuracy | Low |
| Tape / laser field measure | Survey-grade | Medium–high |

**Photos alone cannot match LiDAR.** RoomCraft’s consumer path optimizes for *layout usefulness*, then improves with data + AR.

## What ships now (Easy scan)

1. **Default mode = Easy** — record video or add photos; no size required.
2. **Multi-frame vision** — keyframes from video; architecture + furniture.
3. **Auto-scale** (`lib/domain/auto_scale.dart`)  
   - Vision estimates width × length  
   - **Door prior** (~2.75 ft) rescales the whole plan  
   - Furniture priors (bed/sofa) as secondary  
   - Optional “I know room size” locks measurements  
4. **Review** — edit openings, scale calibration, furniture toggles  
5. **Feedback chips** — Looks right / Close / Off → Firebase Analytics `scan_feedback` (training signal)

## Accuracy roadmap (train / improve)

### Phase A — prompt + priors (done / ongoing)
- Multi-view prompts, door scale lock, confidence UI, feedback analytics
- No custom model training yet — uses Groq vision + deterministic geometry

### Phase B — labeled feedback loop
1. Collect `scan_feedback` + corrected plans (after user edits in editor)
2. Export pairs: `{keyframes, model JSON, user-corrected plan}`
3. Measure: door width error, room size error, furniture IoU

### Phase C — specialized model (real training)
Options (pick one stack):
- Fine-tune a multimodal layout model on corrected RoomCraft data
- Or depth + layout: Depth Anything / ZoeDepth + room layout head
- Host inference on backend (rate-limited) — no client API key

**Data needed:** hundreds–thousands of rooms with:
- multi-angle photos/video  
- ground-truth size (tape or AR)  
- labeled openings + furniture  

### Phase D — ARCore (highest Android leap)
- Plane hit-tests + wall length tools while user walks  
- Still “upload-like” UX (guided camera), much better scale  
- Flutter plugin or thin Kotlin module

## UX principles

1. **Easy path first** — never block on measurements  
2. **Honest confidence** — show estimate %, not fake CAD  
3. **One-tap fix** — calibrate one wall if user knows one length  
4. **Learn from edits** — every corrected plan is gold for training  

## Metrics to watch

| Metric | Target (consumer) |
|--------|-------------------|
| Scan start → editor | ≥ 70% |
| Easy scan used | ≥ 80% of scans |
| Feedback “good” | trending up |
| Median room size error vs tape | &lt; 15% (Phase C) |
| Door placement usable | &gt; 80% after Review |

## Related code

- `lib/screens/scanner_screen.dart` — Easy default  
- `lib/services/free_vision_scanner.dart` — consumer multi-frame  
- `lib/domain/auto_scale.dart` — door/furniture scale  
- `lib/screens/scan_review_screen.dart` — feedback  
- `docs/Scan-Precision-Research.md` — why tape still wins for pros  

## ARCore guided measure (+15)

**Default scan mode on Android** when ARCore is available.

1. User opens **AR measure**
2. Phone tracks the floor plane (white grid)
3. Tap two ends of **width**, then two ends of **length**
4. Optional: add photos/video for furniture
5. Plan size is locked to AR meters→feet (higher confidence than photo priors)

Native code: `ArMeasureActivity.kt`, channel `com.logicrequire.room_craft/ar_measure`.

Next AR upgrades: wall-by-wall multi-segment chain, door hit-tests, continuous depth mesh.
