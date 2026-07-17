import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/accurate_scan.dart';
import 'package:room_craft/domain/auto_scale.dart';
import 'package:room_craft/domain/photo_true_layout.dart';
import 'package:room_craft/domain/scan_refine.dart';
import 'package:room_craft/domain/wall_relative_scan.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/scan_result.dart';
import 'package:room_craft/models/stroke_model.dart';

void main() {
  test('+39 polish yields photo-true gold score ~74%', () {
    final base = AccurateScan.enforce(
      widthFt: 16,
      lengthFt: 14,
      openings: [
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(1, 0),
          endFt: Offset(4, 0),
        ),
        const ScanWallSegment(
          type: StrokeType.balcony,
          startFt: Offset(16, 2),
          endFt: Offset(16, 8),
        ),
      ],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(1.2, 7),
          widthFt: 6.7,
          lengthFt: 1.5,
        ),
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(8, 2),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.4,
    );

    final polished = PhotoTrueLayout.polish(base);
    expect(PhotoTrueLayout.isPhotoTrue(polished), isTrue);
    expect(polished.accuracyScore, greaterThanOrEqualTo(0.74));
    final wardrobe = polished.furniture
        .firstWhere((f) => f.type == FurnitureType.wardrobe);
    expect(
      wardrobe.widthFt > wardrobe.lengthFt
          ? wardrobe.widthFt
          : wardrobe.lengthFt,
      greaterThanOrEqualTo(5.5),
    );
  });

  test('+39 refine keeps photo-true score bar', () {
    final base = AccurateScan.enforce(
      widthFt: 16,
      lengthFt: 14,
      openings: [
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(2, 0),
          endFt: Offset(5, 0),
        ),
      ],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(1, 6),
          widthFt: 6.5,
          lengthFt: 1.5,
        ),
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(6, 2),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.74,
    );
    final refined = ScanRefine.refine(base);
    expect(refined.accuracyScore, greaterThanOrEqualTo(0.74));
  });

  test('+39 dense min room for wardrobe+mesh', () {
    final min = AutoScale.ensurePhotoTrueMinSize(
      widthFt: 12,
      lengthFt: 10.5,
      inventoryHint:
          'MUST include WARDROBE; MUST include mesh balcony; about 2 door opening(s)',
    );
    // +53 dense floor matches gold-plan ~20×17
    expect(min.widthFt, greaterThanOrEqualTo(20));
    expect(min.lengthFt, greaterThanOrEqualTo(17));
  });

  test('+41 caps confidence when plan is table-only (feedback 443cf0c3)', () {
    final thin = AccurateScan.enforce(
      widthFt: 16,
      lengthFt: 14,
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(8, 2),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.74, // falsely high from older builds
    );
    final polished = PhotoTrueLayout.polish(thin);
    // Without inventory MUST wardrobe in warnings, polish may still seed if
    // table-only — table-only without wardrobe must not stay at 74%.
    if (!PhotoTrueLayout.isPhotoTrue(polished)) {
      expect(
        polished.accuracyScore ?? 0,
        lessThanOrEqualTo(PhotoTrueLayout.incompleteScoreCap),
      );
    } else {
      // If warnings/seed made it photo-true, wardrobe must be large and visible
      final w = polished.furniture
          .firstWhere((f) => f.type == FurnitureType.wardrobe);
      expect(mathMax(w.widthFt, w.lengthFt), greaterThanOrEqualTo(5.0));
      expect(polished.accuracyScore, greaterThanOrEqualTo(0.74));
    }
  });

  test('+41 inventory MUST in warnings yields wardrobe+table+openings', () {
    final base = AccurateScan.enforce(
      widthFt: 16,
      lengthFt: 14,
      furniture: const [],
      inventDefaultOpenings: false,
      accuracyScore: 0.3,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE (desk); '
            'NO BED; NO SOFA; NO TV_UNIT; MUST include mesh balcony; '
            'about 2 door opening(s)',
      ],
    );
    final polished = PhotoTrueLayout.polish(base);
    expect(PhotoTrueLayout.isPhotoTrue(polished), isTrue);
    expect(polished.accuracyScore, greaterThanOrEqualTo(0.74));
    final types = polished.furniture.map((f) => f.type).toSet();
    expect(types, contains(FurnitureType.wardrobe));
    expect(types, contains(FurnitureType.table));
    expect(
      polished.walls.any((w) =>
          w.type == StrokeType.door ||
          w.type == StrokeType.window ||
          w.type == StrokeType.balcony),
      isTrue,
    );
  });

  test('+52 bedroom with bed is not wiped by study gold', () {
    final bedroom = AccurateScan.enforce(
      widthFt: 14,
      lengthFt: 12,
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.bed,
          posFt: Offset(7, 6),
          widthFt: 5,
          lengthFt: 6.5,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.5,
    ).copyWith(warnings: ['Bedroom scan']);
    expect(PhotoTrueLayout.isStudyLike(bedroom), isFalse);
    final out = PhotoTrueLayout.ensureGoldQuality(bedroom);
    expect(
      out.furniture.any((f) => f.type == FurnitureType.bed),
      isTrue,
    );
    // Must not force study-only (no bed)
    expect(PhotoTrueLayout.isPhotoTrue(out), isFalse);
  });

  test('+52 composeStudyGold puts wardrobe on longest wall', () {
    // Wide room: N/S walls are longer (w=20 > l=12)
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20, lengthFt: 12);
    final wardrobe =
        gold.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    // North wall furniture sits near y≈length
    expect(wardrobe.posFt.dy, greaterThan(12 - 3));
  });

  test('+53 ensureGoldQuality upgrades 12×10.5 thin plan to gold density', () {
    // Feedback 32ffdc65/443cf0c3: tiny room + empty/thin plan must become gold-like
    final thin = AccurateScan.enforce(
      widthFt: 12,
      lengthFt: 10.5,
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(3, 2),
          widthFt: 3,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.74,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
        'Multi-wall study inventory',
      ],
    );
    final out = PhotoTrueLayout.ensureGoldQuality(thin);
    expect(out.roomWidthFt, greaterThanOrEqualTo(20));
    expect(out.roomLengthFt, greaterThanOrEqualTo(17));
    expect(PhotoTrueLayout.isPhotoTrue(out), isTrue);
    expect(out.accuracyScore, greaterThanOrEqualTo(0.74));
    final wardrobe =
        out.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    expect(
      mathMax(wardrobe.widthFt, wardrobe.lengthFt),
      greaterThanOrEqualTo(6.5),
    );
    final opens = out.walls
        .where((w) =>
            w.type == StrokeType.door ||
            w.type == StrokeType.window ||
            w.type == StrokeType.balcony)
        .length;
    expect(opens, greaterThanOrEqualTo(2));
  });

  test('+53 isPhotoTrue rejects single-opening or short wardrobe', () {
    final weak = AccurateScan.enforce(
      widthFt: 16,
      lengthFt: 14,
      openings: [
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(1, 0),
          endFt: Offset(4, 0),
        ),
      ],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(1, 7),
          widthFt: 5.2,
          lengthFt: 1.5,
        ),
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(8, 2),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.7,
    );
    expect(PhotoTrueLayout.isPhotoTrue(weak), isFalse);
  });

  test('+54 vision east wardrobe wall is preserved through ensureGoldQuality', () {
    // Feedback gold mismatch: vision found east wardrobe — must not force north
    final partial = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: [
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(2, 0),
          endFt: Offset(5, 0),
        ),
      ],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(18.5, 8.5),
          widthFt: 4.0, // short — must grow on east, not relocate
          lengthFt: 1.5,
          rotationRad: 1.5708,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.4,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
      ],
    );
    final roles = PhotoTrueLayout.inferStudyWallRoles(partial);
    expect(roles.wardrobe, WallSide.east);
    final out = PhotoTrueLayout.ensureGoldQuality(partial);
    expect(PhotoTrueLayout.isPhotoTrue(out), isTrue);
    final wardrobe =
        out.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    // Still on east half (vision wall)
    expect(wardrobe.posFt.dx, greaterThan(14));
    expect(mathMax(wardrobe.widthFt, wardrobe.lengthFt), greaterThanOrEqualTo(6.5));
  });

  test('+54 composeStudyGold honors vision wall roles', () {
    final roles = const StudyWallRoles(
      wardrobe: WallSide.east,
      desk: WallSide.south,
      mesh: WallSide.north,
      doorPrimary: WallSide.west,
      doorSecondary: WallSide.south,
    );
    final gold = PhotoTrueLayout.composeStudyGold(
      widthFt: 20,
      lengthFt: 17,
      roles: roles,
    );
    final wardrobe =
        gold.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    expect(wardrobe.posFt.dx, greaterThan(16)); // east wall
  });

  test('+55 default roles: dual doors on entry, mesh adjacent wardrobe', () {
    // Wide room → wardrobe north, mesh west (clockwise), entry south
    final roles = PhotoTrueLayout.defaultStudyWallRoles(20, 17);
    expect(roles.wardrobe, WallSide.north);
    expect(roles.mesh, WallSide.west);
    expect(roles.doorPrimary, WallSide.south);
    expect(roles.doorSecondary, WallSide.south);
    final gold = PhotoTrueLayout.composeStudyGold(
      widthFt: 20,
      lengthFt: 17,
      roles: roles,
    );
    expect(PhotoTrueLayout.isPhotoTrue(gold), isTrue);
    final doors = gold.walls.where((w) => w.type == StrokeType.door).toList();
    expect(doors.length, greaterThanOrEqualTo(2));
    // Both doors near south (y≈0)
    for (final d in doors) {
      final midY = (d.startFt.dy + d.endFt.dy) / 2;
      expect(midY, lessThan(3.0));
    }
    final mesh = gold.walls.firstWhere((w) => w.type == StrokeType.balcony);
    final meshMidX = (mesh.startFt.dx + mesh.endFt.dx) / 2;
    expect(meshMidX, lessThan(3.0)); // west wall x≈0
  });

  test('+55 polish dual doors not on wardrobe storage wall', () {
    final base = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(10, 15.5),
          widthFt: 8,
          lengthFt: 1.6,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.3,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
      ],
    );
    final polished = PhotoTrueLayout.polish(base);
    final doors = polished.walls.where((w) => w.type == StrokeType.door);
    for (final d in doors) {
      final midY = (d.startFt.dy + d.endFt.dy) / 2;
      // Doors must not sit on north storage wall (y≈17)
      expect(midY, lessThan(14));
    }
  });

  test('+56 gold wardrobe is centered on longest wall (fromLeft = center)', () {
    // Wide room → wardrobe on north (y≈17). Center x should be ~10, not ~4
    // (old left-edge bug placed center at left edge of unit).
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20, lengthFt: 17);
    final wardrobe =
        gold.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    expect(wardrobe.posFt.dy, greaterThan(14)); // north wall
    expect(wardrobe.posFt.dx, closeTo(10.0, 2.5));
    expect(
      mathMax(wardrobe.widthFt, wardrobe.lengthFt),
      greaterThanOrEqualTo(6.5),
    );
  });

  test('+56 polish preserves east wardrobe center after grow', () {
    final base = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: [
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(2, 0),
          endFt: Offset(5, 0),
        ),
        const ScanWallSegment(
          type: StrokeType.balcony,
          startFt: Offset(20, 4),
          endFt: Offset(20, 11),
        ),
      ],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(18.5, 8.5),
          widthFt: 7.0,
          lengthFt: 1.6,
          rotationRad: 1.5708,
        ),
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(8, 2),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.5,
    );
    final polished = PhotoTrueLayout.polish(base);
    final wardrobe =
        polished.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    expect(wardrobe.posFt.dx, greaterThan(16)); // still east
    // Along east wall, y-center should stay near mid room (~8.5)
    expect(wardrobe.posFt.dy, closeTo(8.5, 3.0));
  });

  test('+57 resolveWallClearances moves desk off door span', () {
    // Desk centered on south wall covering a door → must slide off
    final conflict = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: [
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(8, 0),
          endFt: Offset(11, 0),
        ),
        const ScanWallSegment(
          type: StrokeType.balcony,
          startFt: Offset(20, 4),
          endFt: Offset(20, 11),
        ),
      ],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(10, 15.5),
          widthFt: 8,
          lengthFt: 1.6,
        ),
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(9.5, 1.5), // overlaps south door mid
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.74,
    );
    final out = PhotoTrueLayout.resolveWallClearances(conflict);
    final table =
        out.furniture.firstWhere((f) => f.type == FurnitureType.table);
    // Table center should leave door mid x=9.5
    expect((table.posFt.dx - 9.5).abs(), greaterThan(1.5));
    // Still on south wall (low y)
    expect(table.posFt.dy, lessThan(4));
  });

  test('+57 composeStudyGold desk near wardrobe-mesh corner not over mesh mid', () {
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20, lengthFt: 17);
    final roles = PhotoTrueLayout.defaultStudyWallRoles(20, 17);
    // desk wall == mesh wall (west)
    expect(roles.desk, roles.mesh);
    final table =
        gold.furniture.firstWhere((f) => f.type == FurnitureType.table);
    // west wall x small; wardrobe corner = north → higher y after mesh span
    expect(table.posFt.dx, lessThan(4));
    expect(table.posFt.dy, greaterThan(9));
    // Mesh should not cover table y-band
    final mesh = gold.walls.firstWhere((w) => w.type == StrokeType.balcony);
    final meshMidY = (mesh.startFt.dy + mesh.endFt.dy) / 2;
    expect((table.posFt.dy - meshMidY).abs(), greaterThan(2.0));
  });

  test('+58 preferVisionOpenings keeps vision door positions', () {
    final vision = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: [
        // Vision found a door on east wall (unusual for template)
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(20, 2),
          endFt: Offset(20, 5),
        ),
      ],
      furniture: const [],
      inventDefaultOpenings: false,
      accuracyScore: 0.3,
    );
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20, lengthFt: 17);
    final out = PhotoTrueLayout.preferVisionOpenings(gold, vision);
    final doors = out.walls.where((w) => w.type == StrokeType.door).toList();
    expect(doors.length, greaterThanOrEqualTo(1));
    // At least one door still near east (x≈20)
    expect(
      doors.any((d) {
        final mx = (d.startFt.dx + d.endFt.dx) / 2;
        return mx > 18;
      }),
      isTrue,
    );
    // Still dense enough for photo-true after gold furniture
    expect(out.furniture.any((f) => f.type == FurnitureType.wardrobe), isTrue);
  });

  test('+51 ensureGoldQuality upgrades empty multi-wall plan', () {
    final empty = AccurateScan.enforce(
      widthFt: 18,
      lengthFt: 16,
      furniture: const [],
      inventDefaultOpenings: false,
      accuracyScore: 0.2,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
      ],
    );
    final out = PhotoTrueLayout.ensureGoldQuality(empty);
    expect(PhotoTrueLayout.isPhotoTrue(out), isTrue);
    expect(out.accuracyScore, greaterThanOrEqualTo(0.74));
  });

  test('+50 merge keeps east wardrobe and fills openings', () {
    final partial = AccurateScan.enforce(
      widthFt: 18,
      lengthFt: 16,
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(16.5, 8),
          widthFt: 6.5,
          lengthFt: 1.5,
          rotationRad: 1.5708,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.4,
    );
    final merged = PhotoTrueLayout.mergeWithStudyGold(partial);
    expect(PhotoTrueLayout.isPhotoTrue(merged), isTrue);
    final wardrobe =
        merged.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    // Vision east placement preserved (not reset to north template only)
    expect(wardrobe.posFt.dx, greaterThan(10));
    expect(
      merged.furniture.any((f) => f.type == FurnitureType.table),
      isTrue,
    );
    expect(
      merged.walls.any((w) =>
          w.type == StrokeType.door || w.type == StrokeType.balcony),
      isTrue,
    );
  });

  test('+49 composeStudyGold is photo-true dense gold layout', () {
    final gold = PhotoTrueLayout.composeStudyGold(
      widthFt: 18.5,
      lengthFt: 17.2,
    );
    expect(PhotoTrueLayout.isPhotoTrue(gold), isTrue);
    expect(gold.accuracyScore, greaterThanOrEqualTo(0.74));
    final types = gold.furniture.map((f) => f.type).toSet();
    expect(types, contains(FurnitureType.wardrobe));
    expect(types, contains(FurnitureType.table));
    expect(types, contains(FurnitureType.chair));
    expect(types, isNot(contains(FurnitureType.bed)));
    expect(types, isNot(contains(FurnitureType.sofa)));
    final wardrobe =
        gold.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    expect(
      mathMax(wardrobe.widthFt, wardrobe.lengthFt),
      greaterThanOrEqualTo(6.0),
    );
    final opens = gold.walls
        .where((w) =>
            w.type == StrokeType.door || w.type == StrokeType.balcony)
        .length;
    expect(opens, greaterThanOrEqualTo(2));
  });

  test('+47 multi openings land on more than one wall', () {
    final base = AccurateScan.enforce(
      widthFt: 18,
      lengthFt: 16,
      furniture: const [],
      inventDefaultOpenings: false,
      accuracyScore: 0.3,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
      ],
    );
    final polished = PhotoTrueLayout.polish(base);
    final opens = polished.walls
        .where((w) =>
            w.type == StrokeType.door ||
            w.type == StrokeType.window ||
            w.type == StrokeType.balcony)
        .toList();
    expect(opens.length, greaterThanOrEqualTo(2));
    // At least two distinct perimeter edges (different midpoints)
    final mids = opens
        .map((o) => Offset(
              (o.startFt.dx + o.endFt.dx) / 2,
              (o.startFt.dy + o.endFt.dy) / 2,
            ))
        .toList();
    var distinct = 0;
    for (var i = 0; i < mids.length; i++) {
      var unique = true;
      for (var j = 0; j < i; j++) {
        if ((mids[i] - mids[j]).distance < 1.0) unique = false;
      }
      if (unique) distinct++;
    }
    expect(distinct, greaterThanOrEqualTo(2));
  });

  test('+46 second polish from forced inventory reaches photo-true', () {
    // Simulates weak wall-by-wall then forced inventory second pass (+46)
    final weak = AccurateScan.enforce(
      widthFt: 18,
      lengthFt: 16,
      furniture: const [],
      inventDefaultOpenings: false,
      accuracyScore: 0.3,
    );
    final first = PhotoTrueLayout.polish(weak);
    expect(PhotoTrueLayout.isPhotoTrue(first), isFalse);
    final second = PhotoTrueLayout.polish(first.copyWith(
      warnings: [
        ...first.warnings,
        'Inventory: MUST include WARDROBE; MUST include TABLE (desk); '
            'include CHAIR if seen; NO BED; NO SOFA; NO TV_UNIT; '
            'about 2 door opening(s); MUST include mesh balcony',
        'Forced photo-true second polish (+46)',
      ],
    ));
    expect(PhotoTrueLayout.isPhotoTrue(second), isTrue);
    expect(second.accuracyScore, greaterThanOrEqualTo(0.74));
    final types = second.furniture.map((f) => f.type).toSet();
    expect(types, contains(FurnitureType.wardrobe));
    expect(types, contains(FurnitureType.table));
    expect(
      second.walls.any((w) =>
          w.type == StrokeType.door || w.type == StrokeType.balcony),
      isTrue,
    );
  });

  test('+44 seeds chair at desk when inventory has chair', () {
    final base = AccurateScan.enforce(
      widthFt: 16,
      lengthFt: 14,
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(8, 2),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.3,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE (desk); '
            'include CHAIR if seen; NO BED; about 2 door opening(s); '
            'MUST include mesh balcony',
      ],
    );
    final polished = PhotoTrueLayout.polish(base);
    final types = polished.furniture.map((f) => f.type).toSet();
    expect(types, contains(FurnitureType.wardrobe));
    expect(types, contains(FurnitureType.table));
    expect(types, contains(FurnitureType.chair));
    expect(
      polished.walls.any((w) =>
          w.type == StrokeType.door || w.type == StrokeType.balcony),
      isTrue,
    );
  });

  test('+43 keeps wardrobe on east wall (does not force west)', () {
    final base = AccurateScan.enforce(
      widthFt: 16,
      lengthFt: 14,
      openings: [
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(2, 0),
          endFt: Offset(5, 0),
        ),
      ],
      furniture: [
        // Against east wall (x near 16)
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(14.5, 7),
          widthFt: 6.5,
          lengthFt: 1.5,
          rotationRad: 1.5708,
        ),
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(8, 2),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.5,
    );
    final polished = PhotoTrueLayout.polish(base);
    expect(PhotoTrueLayout.isPhotoTrue(polished), isTrue);
    final wardrobe =
        polished.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    // Still on east half of room (not forced to west x≈1)
    expect(wardrobe.posFt.dx, greaterThan(10));
  });
}

double mathMax(double a, double b) => a > b ? a : b;

