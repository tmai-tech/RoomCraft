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

1. LIST only furniture clearly visible.
2. NEVER invent bed/sofa/TV unit if not in photos.
3. Sliding wardrobe/cupboard = WARDROBE (often the largest piece).
4. Computer desk = TABLE. Mesh/glass full-height sliding = balcony.
5. wall + fromLeft + depth for every item. JSON only.
''';

  /// Pass 1: inventory only.
  static const inventorySystem = '''
Strict room inventory from photos. List what exists. Do not invent. Do not place. JSON only.
''';

  static String inventoryPass() => '''
Same room, multiple photos. Return ONLY:

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

Booleans MUST match photos. hasBed/hasSofa/hasTvUnit true only if clearly visible.
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

  /// Consumer: size + openings + furniture in one pass.
  /// Prefer wall-anchored fields (stable) over free XY (random).
  static String consumerLayout({String inventoryHint = ''}) => '''
Map this room from phone photos/video into a top-down plan in FEET.
Cross-check the SAME room across all frames.
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
  static String lockedSinglePass(double roomWidthFt, double roomLengthFt) => '''
You produce a top-down floor plan assist for a measured room.

ROOM SIZE IS FIXED (do not change):
- roomWidth = $roomWidthFt feet
- roomLength = $roomLengthFt feet

List every clearly visible major furniture piece and any clear doors/windows.
Missing a bed/sofa/TV unit that appears in the photos is a failure.
Do not invent a typical furniture set that is not visible.

Return ONLY JSON (no markdown):
{
  "roomWidth": $roomWidthFt,
  "roomLength": $roomLengthFt,
  "walls": [
    {"type": "wall", "start": {"x": 0, "y": 0}, "end": {"x": $roomWidthFt, "y": 0}},
    {"type": "wall", "start": {"x": $roomWidthFt, "y": 0}, "end": {"x": $roomWidthFt, "y": $roomLengthFt}},
    {"type": "wall", "start": {"x": $roomWidthFt, "y": $roomLengthFt}, "end": {"x": 0, "y": $roomLengthFt}},
    {"type": "wall", "start": {"x": 0, "y": $roomLengthFt}, "end": {"x": 0, "y": 0}}
  ],
  "openings": [
    {"type": "door", "start": {"x": 1, "y": 0}, "end": {"x": 3.5, "y": 0}, "confidence": 0.85, "evidence": "entry door"}
  ],
  "furniture": [
    {"type": "BED", "pos": {"x": 4, "y": 5}, "dim": {"w": 5, "l": 6.5}, "rot": 0, "confidence": 0.85, "evidence": "bed visible"},
    {"type": "SOFA", "pos": {"x": 10, "y": 12}, "dim": {"w": 7, "l": 3}, "rot": 0, "confidence": 0.8, "evidence": "sofa visible"}
  ]
}

Rules:
- ALWAYS keep roomWidth=$roomWidthFt and roomLength=$roomLengthFt.
- Types only: $furnitureTypes.
- Include furniture at confidence ≥ 0.55 when clearly visible.
- pos is CENTER in feet; rot in degrees.
- openings types: door | window | balcony on perimeter walls.
- Empty furniture [] only if the room has no freestanding furniture.
''';
}
