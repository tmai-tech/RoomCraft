/// Shared multi-view layout prompts for free vision backends (Groq / HF / Gemini).
///
/// Tuned for **furniture recall**: list clearly visible major pieces.
/// Still forbid inventing whole room sets that are not in the photos.
class VisionLayoutPrompts {
  VisionLayoutPrompts._();

  static const furnitureTypes =
      'BED, WARDROBE, SOFA, TABLE, CHAIR, TV_UNIT, BOOKSHELF, NIGHTSTAND';

  /// System message for consumer easy scan (estimate size + full layout).
  static const consumerSystem = '''
You map real rooms from phone photos for a floor-plan app.
You are graded on matching the photos — not inventing a typical bedroom.

1. LIST only furniture clearly visible across the photos.
2. NEVER invent bed/sofa/TV unit if not in photos.
3. Sliding wardrobe/cupboard with storage doors = WARDROBE (often largest piece).
4. A tall MIRROR or glass reflection is NOT a wardrobe.
5. Computer desk / study table = TABLE. Monitors on a desk are NOT a TV_UNIT.
6. Mesh/glass full-height sliding = balcony opening.
7. wall + fromLeft + depth for every item. JSON only.
8. furniture: [] only if the room truly has no major furniture.
''';

  /// Pass 1: inventory only.
  static const inventorySystem = '''
Strict room inventory from photos. List what exists. Do not invent. Do not place. JSON only.
Mirror ≠ wardrobe. Desk monitors ≠ TV unit.
False negatives hurt more than false positives for wardrobe/desk/doors — if a
sliding cupboard or work desk is visible in ANY frame, set those flags true.
''';

  static String inventoryPass() => '''
Same room, multiple photos. Cross-check every frame. Return ONLY:

{
  "hasWardrobe": true,
  "hasDeskOrTable": true,
  "hasBed": false,
  "hasSofa": false,
  "hasTvUnit": false,
  "hasChair": false,
  "doorCount": 2,
  "hasMeshOrSlidingGlass": true,
  "hasWindow": false,
  "notes": "pink sliding wardrobe, desk with monitors, mesh doors, two openings"
}

Booleans MUST match photos.
- hasWardrobe TRUE for storage cupboard/wardrobe/sliding almirah (pink/white panels,
  overhead storage). NOT a tall mirror alone.
- hasDeskOrTable TRUE for desk/table/work surface (even with monitors on it).
- hasBed/hasSofa/hasTvUnit true ONLY if that object is clearly visible (do not invent).
- doorCount = number of walk-through door openings you can see (not wardrobe doors).
- hasMeshOrSlidingGlass TRUE for full-height mesh/glass balcony or partition doors.
- Prefer hasWardrobe/hasDeskOrTable true when unsure after multi-angle photos of a
  furnished room (missing them empties the plan).
''';

  /// Second-chance inventory when first pass is sparse (multi-wall photos).
  static String inventoryRecallPass() => '''
RECALL pass — look again carefully across ALL photos of ONE room.

Often missed: long sliding wardrobe/cupboard, computer desk with monitors,
interior door openings, full-height mesh/glass sliding doors.

Return ONLY the same inventory JSON as before:
{
  "hasWardrobe": true/false,
  "hasDeskOrTable": true/false,
  "hasBed": false,
  "hasSofa": false,
  "hasTvUnit": false,
  "hasChair": true/false,
  "doorCount": 0,
  "hasMeshOrSlidingGlass": true/false,
  "hasWindow": true/false,
  "notes": "what you see"
}

Rules: set hasWardrobe true if ANY sliding cupboard/wardrobe is visible.
Set hasDeskOrTable true if ANY desk/table is visible. Do NOT invent bed/sofa/TV.
Count real door openings (passages), not wardrobe shutter panels.
''';

  /// System for architecture-only pass.
  static const architectureSystem = '''
You are an interior architect surveying a room for a measured floor plan.
Report openings and wall features you can see (doors, windows, sliding doors,
French doors, large glazed balcony doors). Do NOT invent openings.
Do NOT list freestanding furniture. JSON only. Room size is fixed by the user.
''';

  /// System for furniture-only pass.
  static const furnitureSystem = '''
You document freestanding furniture for a top-down layout app.
List EVERY clearly visible major piece. Wardrobe and desk are critical when present.
Do NOT invent bed/sofa/TV if not visible. One entry per object. JSON only.
''';

  /// Hint when user uploads ~4 wall photos (designer multi-view method).
  static String multiWallPhotoHint(int frameCount) {
    if (frameCount < 2) {
      return 'Only $frameCount photo — coverage is limited; do not invent unseen walls.';
    }
    if (frameCount >= 3 && frameCount <= 6) {
      return '''
MULTI-WALL PHOTOS ($frameCount frames): treat as the SAME room from different walls.
- Assign a consistent orientation: south/north/east/west for the whole plan.
- Furniture seen on one wall stays on that wall (do not scatter randomly).
- Cross-check: if wardrobe appears in 2+ frames, it is real — MUST place WARDROBE.
- If desk/table appears in any frame, MUST place TABLE.
- Do not invent bed/sofa/TV just because rooms often have them.
''';
    }
    return 'Use all $frameCount frames of the same room; keep positions consistent.';
  }

  /// Consumer: size + openings + furniture in one pass.
  /// Prefer wall-anchored fields (stable) over free XY (random).
  static String consumerLayout({
    String inventoryHint = '',
    int frameCount = 1,
  }) => '''
Map this room from phone photos/video into a top-down plan in FEET.
Cross-check the SAME room across all frames.
${multiWallPhotoHint(frameCount)}
${inventoryHint.isEmpty ? '' : '\nINVENTORY CONSTRAINT (from pass 1 — respect exactly):\n$inventoryHint\n'}

Scale cues: interior door ≈ 2.5–3.0 ft; wardrobe depth ≈ 1.5–2.5 ft;
desk/table depth ≈ 1.5–2.5 ft; queen bed ≈ 5×6.5 ft.

CRITICAL: place every opening and furniture piece ON A WALL using wall + fromLeft
(do NOT invent free floating XY). This matches how floor plans are drawn.

Wall names (pick one consistent orientation for the whole plan):
- south = near wall in plan (y=0)
- north = far wall (y=roomLength)
- west = left wall (x=0)
- east = right wall (x=roomWidth)
fromLeft = feet from the LEFT corner while facing that wall from inside the room.
depth = how far the furniture center sits into the room from that wall face.

Return ONLY JSON:
{
  "roomWidth": 12.0,
  "roomLength": 14.0,
  "sizeConfidence": 0.65,
  "openings": [
    {
      "type": "door",
      "wall": "south",
      "fromLeft": 1.0,
      "width": 2.8,
      "confidence": 0.9,
      "evidence": "entry door"
    },
    {
      "type": "balcony",
      "wall": "east",
      "fromLeft": 1.0,
      "width": 7.0,
      "confidence": 0.85,
      "evidence": "full-height mesh sliding doors"
    }
  ],
  "furniture": [
    {
      "type": "WARDROBE",
      "wall": "north",
      "fromLeft": 4.0,
      "depth": 1.2,
      "dim": {"w": 8.0, "l": 2.0},
      "confidence": 0.9,
      "evidence": "long sliding wardrobe along wall"
    },
    {
      "type": "TABLE",
      "wall": "east",
      "fromLeft": 3.0,
      "depth": 1.5,
      "dim": {"w": 4.0, "l": 2.0},
      "confidence": 0.85,
      "evidence": "desk with computers"
    }
  ]
}

Rules:
1. List ALL clearly visible major pieces. Empty furniture [] only if room is empty.
2. Types: $furnitureTypes (desk→TABLE, closet/sliding wardrobe→WARDROBE, couch→SOFA).
3. openings: door | window | balcony. Wide mesh/glass sliding → type "balcony".
4. EVERY furniture item MUST include wall + fromLeft + depth + dim.
5. EVERY opening MUST include wall + fromLeft + width.
6. confidence ≥ 0.55 when clearly visible.
7. Rectangular outer bounds only.
8. NEVER invent bed/sofa/TV if not in photos.
9. Put the long wardrobe on ONE wall (fromLeft near 0 if it fills most of the wall).
10. Desk against a wall near monitors; openings on walls where door frames appear.
11. Keep relative positions consistent across frames (same corner relations).
''';

  static String architecture(double w, double l) => '''
Survey this room for a measured floor plan.

ROOM SIZE FIXED: roomWidth = $w ft, roomLength = $l ft.

Return openings with wall + fromLeft (feet from left while facing wall):
{
  "roomWidth": $w,
  "roomLength": $l,
  "openings": [
    {
      "type": "door",
      "wall": "south",
      "fromLeft": 1.0,
      "width": 2.8,
      "confidence": 0.9,
      "evidence": "entry door"
    }
  ]
}

Rules:
1. types: door | window | balcony only (wide mesh glass → balcony).
2. wall: south|north|east|west. fromLeft + width in feet.
3. Only openings you can see. Empty [] is valid.
4. confidence ≥ 0.55. No freestanding furniture in this pass.
''';

  static String furniture(double w, double l) => '''
Document freestanding furniture for a top-down layout plan.

ROOM SIZE FIXED: roomWidth = $w ft, roomLength = $l ft.

Use ALL frames. Place each piece ON A WALL (wall + fromLeft + depth).
fromLeft = feet from left corner while facing that wall from inside.

Return ONLY JSON:
{
  "roomWidth": $w,
  "roomLength": $l,
  "furniture": [
    {
      "type": "WARDROBE",
      "wall": "north",
      "fromLeft": 4.0,
      "depth": 1.2,
      "dim": {"w": 8.0, "l": 2.0},
      "confidence": 0.9,
      "evidence": "sliding wardrobe full wall"
    },
    {
      "type": "TABLE",
      "wall": "east",
      "fromLeft": 3.0,
      "depth": 1.5,
      "dim": {"w": 4.0, "l": 2.0},
      "confidence": 0.85,
      "evidence": "desk with monitors"
    }
  ]
}

Rules:
1. List ALL clearly visible major pieces. Empty [] ONLY if none visible.
2. Types: $furnitureTypes (desk→TABLE, closet→WARDROBE, couch→SOFA).
3. EVERY item MUST have wall (south|north|east|west), fromLeft, depth, dim.
4. confidence ≥ 0.55 when clearly visible.
5. Do not invent furniture not in the photos.
''';

  /// Single-pass locked-size prompt (Gemini / simple path).
  /// Wall-anchored (+28) — free XY examples caused random layouts.
  static String lockedSinglePass(double roomWidthFt, double roomLengthFt) => '''
You produce a top-down floor plan assist for a measured room from multi-wall photos.

ROOM SIZE IS FIXED (do not change):
- roomWidth = $roomWidthFt feet
- roomLength = $roomLengthFt feet

List every clearly visible major furniture piece and clear doors/windows.
Do NOT invent bed/sofa/TV if not in photos. Mirror ≠ wardrobe. Desk monitors ≠ TV_UNIT.

Return ONLY JSON (no markdown):
{
  "roomWidth": $roomWidthFt,
  "roomLength": $roomLengthFt,
  "openings": [
    {"type": "door", "wall": "south", "fromLeft": 1.0, "width": 2.8, "confidence": 0.85, "evidence": "entry door"}
  ],
  "furniture": [
    {"type": "WARDROBE", "wall": "west", "fromLeft": 0.5, "depth": 1.2, "dim": {"w": 6.0, "l": 2.0}, "confidence": 0.9, "evidence": "sliding wardrobe"},
    {"type": "TABLE", "wall": "south", "fromLeft": 3.0, "depth": 1.5, "dim": {"w": 4.0, "l": 2.0}, "confidence": 0.85, "evidence": "desk"}
  ]
}

Rules:
- ALWAYS keep roomWidth=$roomWidthFt and roomLength=$roomLengthFt.
- Types only: $furnitureTypes.
- EVERY furniture item: wall (north|south|east|west) + fromLeft + depth + dim.
- EVERY opening: wall + fromLeft + width. Types: door | window | balcony.
- confidence ≥ 0.55 when clearly visible.
- Empty furniture [] only if the room has no freestanding furniture.
''';
}
