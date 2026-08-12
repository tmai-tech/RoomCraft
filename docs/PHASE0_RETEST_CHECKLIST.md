# Phase 0 — Field retest checklist (+145)

**Goal:** Decide if AR size + inventory plans are good enough before more polish.  
**Build under test:** `1.0.0-beta.1+146` (Phase 1 size + Phase 2 inventory).  
**Reference rooms:** feedback packs under `data/feedback/`.

---

## Before you start

1. Install the latest beta from Firebase App Distribution (not an older +13x APK).
2. Confirm Settings shows **Build +145** (or higher).
3. Have a **tape measure** for at least one room (ground truth).
4. Good lighting; open doors; walk **1.5–2 m from walls**, camera slightly down (Planner5D tip).

---

## Path A — Photos study gold (`32ffdc65` / +36 quality)

| Step | Action | Pass? |
|------|--------|-------|
| A1 | Home → **Photos** (or FAB → Photos) | |
| A2 | Multi-select the same study wall photos as gold pack | |
| A3 | Review / plan: dual doors, wardrobe, desk NW, mesh | |
| A4 | Desk **not** in front of a door; north-up (desk top of screen) | |
| A5 | Density similar to manual gold / build +36 (not sparse empty room) | |

**Fail if:** sparse plan, table-in-door, missing wardrobe, score/layout random.

---

## Path B — AR walk + lounge inventory (`04919d14`)

| Step | Action | Pass? |
|------|--------|-------|
| B1 | Home → **Scan the room** (AR walk) | |
| B2 | Live camera (not black). Walk full loop until size shows | |
| B3 | Tap Done → **Confirm size & contents** | |
| B4 | Note AR proposed W×L: ______ × ______ ft (must **not** stay ~29 ft without tape — +146 caps) | |
| B5 | If “AR raw size looked large” banner: tape one wall **or** Study gold 20.3×17 | |
| B6 | Tap **Lounge (bean bag)** — checklist shows 2 doors, French window, desk, table, bean bag | |
| B7 | Create plan — snackbar should say inventory match | |
| B8 | Blueprint: 2 doors + French window + desk + mid-room table + bean bag | |
| B9 | Table **not** glued to a door; whole plan **fits on screen** | |

**Fail if:** wrong piece counts, AI bed/sofa instead of inventory, 10×10 incomplete, 30+ ft drift without warning.

---

## Path C — AR walk + study gold preset (`be325971`)

| Step | Action | Pass? |
|------|--------|-------|
| C1 | Scan the room → full wall loop → Done | |
| C2 | Confirm size (tape one wall if AR looks wrong) | |
| C3 | Tap **Study gold (+36 layout)** | |
| C4 | Create plan: wardrobe + dual doors + desk + dense study layout | |

**Fail if:** “worse than 36” sparse plan with only 1–2 pieces.

---

## Path D — Tape ground truth (size accuracy)

| Room | Tape W×L (ft) | App after confirm (ft) | \|Error\| % | Notes |
|------|---------------|------------------------|------------|-------|
| 1 | | | | |
| 2 | | | | |
| 3 | | | | |

**Target (Phase 1 exit):** median |error| ≤ **10%** after confirm / one-wall calibrate.  
**Hard floor:** no silent |error| > 25% without large-size or incomplete-walk warning.

---

## AR camera health

| Check | Pass? |
|-------|-------|
| Camera live within ~3 s | |
| If black: Play Services for AR updated + retry works | |
| Cover % / coach text appears while walking | |

---

## Decision

| Outcome | Next |
|---------|------|
| A+B+C pass, D median ≤10% | Phase 2 (openings/inventory polish) |
| Size still bad | Stay Phase 1 (wall-lock / coverage) |
| Size OK, pieces wrong | Phase 2 immediately |
| AR camera broken | Hotfix native camera path |

**Tester notes / feedback ID after retest:** _______________________
