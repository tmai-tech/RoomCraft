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
You map real rooms from phone photos/video for a floor-plan app.
Estimate a realistic top-down plan in feet using multi-view cues and standard
object sizes (doors ~2.5–3 ft, queen bed ~5×6.5 ft, sofa ~6–8 ft long).

LIST every clearly visible major piece of furniture (bed, sofa, wardrobe, TV unit,
table, chairs, nightstands, bookshelf). Missing visible furniture is a failure.
Do NOT invent pieces that are not in any frame. Prefer a complete real inventory
over an empty list. JSON only.
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
List EVERY clearly visible major piece (bed, sofa, wardrobe, TV stand/unit, table,
desk, chairs, nightstands, bookshelf). Missing a bed or sofa that is in the photos
is a failure. One entry per physical object (merge multi-view of the same piece).
Never invent a full room set that is not visible. JSON only.
''';

  /// Consumer: size + openings + furniture in one pass.
  static String consumerLayout() => '''
Map this room from phone photos/video. The user may not know measurements.
Estimate a realistic top-down plan in FEET.

Cross-check the SAME room across all frames. Use standard sizes as a ruler:
- Interior door clear width ≈ 2.5–3.0 ft (primary scale cue)
- Queen bed ≈ 5.0 × 6.5–7.0 ft, twin ≈ 3.2 × 6.5 ft
- 3-seat sofa ≈ 6.5–8.0 ft long; wardrobe depth ≈ 1.5–2.5 ft
- TV unit / media console often along a wall ≈ 4–7 ft wide

Return ONLY JSON:
{
  "roomWidth": 18.0,
  "roomLength": 17.0,
  "sizeConfidence": 0.6,
  "scaleCues": [
    {"type": "door", "widthFt": 2.8, "note": "main door visible"}
  ],
  "openings": [
    {
      "type": "door",
      "start": {"x": 1.0, "y": 0},
      "end": {"x": 3.8, "y": 0},
      "confidence": 0.85,
      "evidence": "door on near wall"
    }
  ],
  "furniture": [
    {
      "type": "BED",
      "pos": {"x": 5.0, "y": 4.0},
      "dim": {"w": 5.0, "l": 6.5},
      "rot": 0,
      "confidence": 0.85,
      "evidence": "bed against wall in multiple frames"
    },
    {
      "type": "SOFA",
      "pos": {"x": 10.0, "y": 12.0},
      "dim": {"w": 7.0, "l": 3.0},
      "rot": 0,
      "confidence": 0.8,
      "evidence": "sofa facing TV wall"
    },
    {
      "type": "TV_UNIT",
      "pos": {"x": 10.0, "y": 1.0},
      "dim": {"w": 5.0, "l": 1.5},
      "rot": 0,
      "confidence": 0.8,
      "evidence": "media unit under TV"
    }
  ]
}

Coordinate system:
- roomWidth = X (left–right), roomLength = Y (near–far)
- Origin (0,0) = one corner of the rectangle
- Openings ON outer walls (y=0, y=roomLength, x=0, or x=roomWidth)
- furniture pos = CENTER of piece in feet; dim = footprint feet; rot degrees

Rules:
1. furniture MUST list all clearly visible major pieces. Empty [] only if the
   room truly has no freestanding furniture.
2. Types: $furnitureTypes
   (desk→TABLE, couch→SOFA, dresser/closet→WARDROBE, tv stand→TV_UNIT).
3. openings: door | window | balcony. Max ~2 doors, ~4 windows, 1 balcony.
4. confidence 0–1. Include items at confidence ≥ 0.55 when clearly visible.
5. sizeConfidence 0–1 honesty about room size estimate.
6. Place large furniture against walls when photos show that (not floating).
7. Prefer clean rectangle outer bounds.
8. Never invent a balcony unless outdoor railing is clearly visible.
''';

  static String architecture(double w, double l) => '''
Survey this room like an interior architect preparing a floor plan.

ROOM SIZE IS FIXED (never change):
- roomWidth = $w feet (X axis)
- roomLength = $l feet (Y axis)
Origin (0,0) = one corner; +x = width; +y = length.

Images/video frames show the SAME room from multiple angles.
Cross-check corners, doors, and windows across frames.

Return ONLY JSON:
{
  "roomWidth": $w,
  "roomLength": $l,
  "openings": [
    {
      "type": "door",
      "start": {"x": 1.0, "y": 0},
      "end": {"x": 3.5, "y": 0},
      "confidence": 0.9,
      "evidence": "door on near wall in frame"
    }
  ]
}

Rules:
1. openings types: door | window | balcony only.
2. Place each opening ON the perimeter (y=0, y=$l, x=0, or x=$w).
3. Estimate position along the wall from what you see.
4. Only report openings you can see. Empty openings: [] is valid.
5. Sliding / French doors → type "door".
6. confidence 0–1; omit under 0.55.
7. No freestanding furniture in this pass.
''';

  static String furniture(double w, double l) => '''
Document freestanding furniture for a top-down layout plan.

ROOM SIZE FIXED:
- roomWidth = $w ft, roomLength = $l ft
- Origin (0,0); pos is CENTER of each piece in feet.

Use ALL frames: same object from two angles = one entry (best position).

Return ONLY JSON with a COMPLETE inventory of visible major furniture:
{
  "roomWidth": $w,
  "roomLength": $l,
  "furniture": [
    {
      "type": "BED",
      "pos": {"x": 4.0, "y": 5.0},
      "dim": {"w": 5.0, "l": 6.5},
      "rot": 0,
      "confidence": 0.85,
      "evidence": "bed against wall, visible in multiple frames"
    },
    {
      "type": "WARDROBE",
      "pos": {"x": 1.0, "y": 8.0},
      "dim": {"w": 6.0, "l": 2.0},
      "rot": 90,
      "confidence": 0.75,
      "evidence": "wardrobe along side wall"
    },
    {
      "type": "TABLE",
      "pos": {"x": 8.0, "y": 9.0},
      "dim": {"w": 3.0, "l": 2.0},
      "rot": 0,
      "confidence": 0.7,
      "evidence": "table in open floor area"
    }
  ]
}

Rules:
1. List ALL clearly visible major pieces. Empty [] ONLY if none visible.
2. Types: $furnitureTypes
   (desk→TABLE, couch→SOFA, dresser→WARDROBE, tv stand→TV_UNIT).
3. Place relative to walls using multi-view cues.
4. confidence ≥ 0.55 when clearly visible; include evidence string.
5. dim = realistic footprint in feet; rot degrees (0/90/180/270 preferred).
6. Do not invent a full bedroom/living set that is not in the photos.
7. Prefer 3–10 real items over an empty list when the room is furnished.
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
