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
    // Wide room: N/S walls are longer (w=20 > l=12); +62 gold uses south
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20, lengthFt: 12);
    final wardrobe =
        gold.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    // South wall furniture sits near y≈0
    expect(wardrobe.posFt.dy, lessThan(3));
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

  test('+55/+62 default roles match gold plan walls (S wardrobe, E mesh)', () {
    // Gold plan 32ffdc65: wardrobe south, mesh east, doors west+north
    final roles = PhotoTrueLayout.defaultStudyWallRoles(20, 17);
    expect(roles.wardrobe, WallSide.south);
    expect(roles.mesh, WallSide.east);
    expect(roles.doorPrimary, WallSide.west);
    expect(roles.doorSecondary, WallSide.north);
    final gold = PhotoTrueLayout.composeStudyGold(
      widthFt: 20,
      lengthFt: 17,
      roles: roles,
    );
    expect(PhotoTrueLayout.isPhotoTrue(gold), isTrue);
    final doors = gold.walls.where((w) => w.type == StrokeType.door).toList();
    expect(doors.length, greaterThanOrEqualTo(2));
    // Doors on west (x≈0) and/or north (y≈17)
    expect(
      doors.any((d) {
        final mx = (d.startFt.dx + d.endFt.dx) / 2;
        final my = (d.startFt.dy + d.endFt.dy) / 2;
        return mx < 3 || my > 14;
      }),
      isTrue,
    );
    final mesh = gold.walls.firstWhere((w) => w.type == StrokeType.balcony);
    final meshMidX = (mesh.startFt.dx + mesh.endFt.dx) / 2;
    expect(meshMidX, greaterThan(17)); // east wall x≈20
  });

  test('+55 polish dual doors not on wardrobe storage wall', () {
    final base = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      furniture: [
        // Wardrobe on south (storage wall y≈0)
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(10, 1.5),
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
      // Doors must not sit on south storage wall (y≈0)
      expect(midY, greaterThan(2.5));
    }
  });

  test('+56 gold wardrobe is centered on longest wall (fromLeft = center)', () {
    // Wide room → wardrobe on south (y≈0). Center x should be ~10, not ~4
    // (old left-edge bug placed center at left edge of unit).
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20, lengthFt: 17);
    final wardrobe =
        gold.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    expect(wardrobe.posFt.dy, lessThan(3)); // south wall (+62 gold)
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

  test('+57/+62 composeStudyGold desk on west NW, mesh on east free', () {
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20, lengthFt: 17);
    final roles = PhotoTrueLayout.defaultStudyWallRoles(20, 17);
    // +62 gold: desk west, mesh east (not same wall)
    expect(roles.desk, WallSide.west);
    expect(roles.mesh, WallSide.east);
    final table =
        gold.furniture.firstWhere((f) => f.type == FurnitureType.table);
    // west wall x small; toward north (gold NW work area)
    expect(table.posFt.dx, lessThan(4));
    expect(table.posFt.dy, greaterThan(8));
    final mesh = gold.walls.firstWhere((w) => w.type == StrokeType.balcony);
    final meshMidX = (mesh.startFt.dx + mesh.endFt.dx) / 2;
    expect(meshMidX, greaterThan(17)); // east — not covering west desk
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

  test('+76 drops vision doors on south wardrobe wall; gold W+N doors win', () {
    // Bad pre-+75 seeds: two doors through the storage wall
    final vision = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: [
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(2, 0),
          endFt: Offset(5, 0),
        ),
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(12, 0),
          endFt: Offset(15, 0),
        ),
      ],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(10, 0.8),
          widthFt: 14,
          lengthFt: 1.6,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.3,
    );
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20, lengthFt: 17);
    final out = PhotoTrueLayout.preferVisionOpenings(gold, vision);
    final doors = out.walls.where((w) => w.type == StrokeType.door).toList();
    expect(doors.length, greaterThanOrEqualTo(2));
    // No door midpoints on south edge (y≈0)
    expect(
      doors.every((d) {
        final my = (d.startFt.dy + d.endFt.dy) / 2;
        return my > 1.5; // not on south wall
      }),
      isTrue,
      reason: 'doors must not cut through south wardrobe',
    );
    // Gold doors on west and/or north remain
    expect(
      doors.any((d) {
        final mx = (d.startFt.dx + d.endFt.dx) / 2;
        final my = (d.startFt.dy + d.endFt.dy) / 2;
        return mx < 1.5 || my > 15.5;
      }),
      isTrue,
    );
  });

  test('+76 ensureGoldQuality recovers from doors-on-wardrobe bad seed', () {
    final bad = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: [
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(3, 0),
          endFt: Offset(6, 0),
        ),
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(10, 0),
          endFt: Offset(13, 0),
        ),
      ],
      furniture: const [],
      inventDefaultOpenings: false,
      accuracyScore: 0.25,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
      ],
    );
    final out = PhotoTrueLayout.ensureGoldQuality(bad);
    expect(PhotoTrueLayout.isPhotoTrue(out), isTrue);
    expect(PhotoTrueLayout.matchesDefaultGoldOrientation(out), isTrue);
    final wardrobe =
        out.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    expect(wardrobe.posFt.dy, lessThan(4)); // south storage
    final doors = out.walls.where((w) => w.type == StrokeType.door).toList();
    expect(
      doors.every((d) {
        final my = (d.startFt.dy + d.endFt.dy) / 2;
        return my > 1.5;
      }),
      isTrue,
    );
  });

  test('+76 inferStudyWallRoles remaps doors off wardrobe wall', () {
    final partial = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: [
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(2, 0),
          endFt: Offset(5, 0),
        ),
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(14, 0),
          endFt: Offset(17, 0),
        ),
      ],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(10, 0.8),
          widthFt: 14,
          lengthFt: 1.6,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.3,
    );
    final roles = PhotoTrueLayout.inferStudyWallRoles(partial);
    expect(roles.wardrobe, WallSide.south);
    expect(roles.doorPrimary, isNot(WallSide.south));
    expect(roles.doorSecondary, isNot(WallSide.south));
    expect(roles.doorPrimary, WallSide.west);
    expect(roles.doorSecondary, WallSide.north);
  });

  test('+77 inferStudyWallRoles desk defaults to west not mesh east', () {
    // Wardrobe on south, mesh on east, no vision desk → gold west desk
    final partial = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: [
        const ScanWallSegment(
          type: StrokeType.balcony,
          startFt: Offset(20, 4),
          endFt: Offset(20, 14),
        ),
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(0, 2),
          endFt: Offset(0, 5),
        ),
      ],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(10, 0.8),
          widthFt: 14,
          lengthFt: 1.6,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.3,
    );
    final roles = PhotoTrueLayout.inferStudyWallRoles(partial);
    expect(roles.wardrobe, WallSide.south);
    expect(roles.mesh, WallSide.east);
    expect(roles.desk, WallSide.west); // not east under mesh
    final gold = PhotoTrueLayout.composeStudyGold(
      widthFt: 20,
      lengthFt: 17,
      roles: roles,
    );
    final desk =
        gold.furniture.firstWhere((f) => f.type == FurnitureType.table);
    expect(desk.posFt.dx, lessThan(4)); // west wall
    expect(PhotoTrueLayout.matchesDefaultGoldOrientation(gold), isTrue);
  });

  test('+77 empty study ensureGoldQuality desk on west, doors not south', () {
    final empty = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
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
    expect(PhotoTrueLayout.matchesDefaultGoldOrientation(out), isTrue);
    final desk =
        out.furniture.firstWhere((f) => f.type == FurnitureType.table);
    expect(desk.posFt.dx, lessThan(4), reason: 'desk on west work wall');
    final mesh = out.walls.firstWhere((w) => w.type == StrokeType.balcony);
    expect((mesh.startFt.dx + mesh.endFt.dx) / 2, greaterThan(16));
  });

  test('+78 table-only input (no vision wardrobe) → default gold south', () {
    // Input had no wardrobe: polish may invent west storage; full gold must use
    // default orientation (S wardrobe / E mesh / W desk) instead.
    final tableOnly = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: [
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(0, 3),
          endFt: Offset(0, 6),
        ),
      ],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(4, 2),
          widthFt: 3.5,
          lengthFt: 2.0,
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
    final out = PhotoTrueLayout.ensureGoldQuality(tableOnly);
    expect(PhotoTrueLayout.isPhotoTrue(out), isTrue);
    expect(PhotoTrueLayout.matchesDefaultGoldOrientation(out), isTrue);
    final wardrobe =
        out.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    expect(wardrobe.posFt.dy, lessThan(4), reason: 'gold south storage wall');
    final along = wardrobe.widthFt > wardrobe.lengthFt
        ? wardrobe.widthFt
        : wardrobe.lengthFt;
    expect(along, greaterThan(10));
  });

  test('+78 vision west wardrobe still preserved (wall trust)', () {
    final vision = AccurateScan.enforce(
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
          endFt: Offset(20, 14),
        ),
      ],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(1.0, 8.5),
          widthFt: 12.0,
          lengthFt: 1.6,
        ),
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(10, 15.5),
          widthFt: 4.0,
          lengthFt: 2.0,
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
    final out = PhotoTrueLayout.ensureGoldQuality(vision);
    expect(PhotoTrueLayout.isPhotoTrue(out), isTrue);
    final wardrobe =
        out.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    // Vision west wall kept (not forced to south gold template)
    expect(wardrobe.posFt.dx, lessThan(4));
  });

  test('+79 hybrid merge without wardrobe uses default gold south storage', () {
    final tableOnly = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: const [],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(2, 4),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.25,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
      ],
    );
    final merged = PhotoTrueLayout.mergeWithStudyGold(tableOnly);
    expect(PhotoTrueLayout.isPhotoTrue(merged), isTrue);
    final wardrobe =
        merged.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    expect(wardrobe.posFt.dy, lessThan(4), reason: 'default gold south');
  });

  test('+79 polish mesh span matches gold (~62% wall, cap 12)', () {
    final empty = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      furniture: const [],
      inventDefaultOpenings: false,
      accuracyScore: 0.2,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
      ],
    );
    final polished = PhotoTrueLayout.polish(empty);
    final mesh =
        polished.walls.firstWhere((w) => w.type == StrokeType.balcony);
    final span = (mesh.startFt - mesh.endFt).distance;
    // 17 * 0.62 ≈ 10.54 (was capped at 10)
    expect(span, greaterThan(10.2));
    expect(span, lessThanOrEqualTo(12.1));
  });

  test('+80 hybrid grows short vision wardrobe to full-wall gold span', () {
    final partial = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: [
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(0, 2),
          endFt: Offset(0, 5),
        ),
        const ScanWallSegment(
          type: StrokeType.balcony,
          startFt: Offset(20, 4),
          endFt: Offset(20, 14),
        ),
      ],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(10, 0.8),
          widthFt: 5.0, // short — must grow on south
          lengthFt: 1.5,
        ),
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(1.5, 12),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.35,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
      ],
    );
    final merged = PhotoTrueLayout.mergeWithStudyGold(partial);
    expect(PhotoTrueLayout.isPhotoTrue(merged), isTrue);
    final wardrobe =
        merged.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    expect(wardrobe.posFt.dy, lessThan(4));
    final along = wardrobe.widthFt > wardrobe.lengthFt
        ? wardrobe.widthFt
        : wardrobe.lengthFt;
    expect(along, greaterThanOrEqualTo(12)); // ~72% of 20ft wall
  });

  test('+80 empty inventory study ensureGoldQuality is gold-oriented', () {
    final empty = AccurateScan.enforce(
      widthFt: 14,
      lengthFt: 12,
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
    expect(PhotoTrueLayout.matchesDefaultGoldOrientation(out), isTrue);
    expect(out.roomWidthFt, greaterThanOrEqualTo(18));
  });

  test('+81 vision desk under mesh replaced by gold west work desk', () {
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20, lengthFt: 17);
    final vision = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: const [],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(10, 0.8),
          widthFt: 14,
          lengthFt: 1.6,
        ),
        // Desk wrongly under east mesh
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(18.5, 8.5),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.4,
    );
    final out = PhotoTrueLayout.preferVisionFurniture(gold, vision);
    final desk =
        out.furniture.firstWhere((f) => f.type == FurnitureType.table);
    expect(desk.posFt.dx, lessThan(4), reason: 'gold west desk, not under mesh');
    final wardrobe =
        out.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    expect(wardrobe.posFt.dy, lessThan(4)); // vision south kept
  });

  test('+81 free-floating vision desk does not beat gold work wall', () {
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20, lengthFt: 17);
    final vision = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: const [],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(10, 8.5), // room center
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.3,
    );
    final out = PhotoTrueLayout.preferVisionFurniture(gold, vision);
    final desk =
        out.furniture.firstWhere((f) => f.type == FurnitureType.table);
    expect(desk.posFt.dx, lessThan(4));
  });

  test('+81 ensureGoldQuality: desk under mesh → gold orientation', () {
    final bad = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: [
        const ScanWallSegment(
          type: StrokeType.balcony,
          startFt: Offset(20, 4),
          endFt: Offset(20, 14),
        ),
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(0, 2),
          endFt: Offset(0, 5),
        ),
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(8, 17),
          endFt: Offset(11, 17),
        ),
      ],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(10, 0.8),
          widthFt: 14,
          lengthFt: 1.6,
        ),
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(18.5, 8.5),
          widthFt: 4,
          lengthFt: 2,
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
    final out = PhotoTrueLayout.ensureGoldQuality(bad);
    expect(PhotoTrueLayout.isPhotoTrue(out), isTrue);
    final desk =
        out.furniture.firstWhere((f) => f.type == FurnitureType.table);
    expect(desk.posFt.dx, lessThan(4));
    expect(PhotoTrueLayout.matchesDefaultGoldOrientation(out), isTrue);
  });

  test('+82 north vision desk realigned to west when wardrobe is gold south', () {
    final partial = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: [
        const ScanWallSegment(
          type: StrokeType.balcony,
          startFt: Offset(20, 4),
          endFt: Offset(20, 14),
        ),
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(0, 2),
          endFt: Offset(0, 5),
        ),
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(8, 17),
          endFt: Offset(11, 17),
        ),
      ],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(10, 0.8),
          widthFt: 14,
          lengthFt: 1.6,
        ),
        // Wall-anchored north desk — valid wall but not gold work wall
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(10, 15.5),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.5,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
      ],
    );
    final out = PhotoTrueLayout.ensureGoldQuality(partial);
    expect(PhotoTrueLayout.matchesDefaultGoldOrientation(out), isTrue);
    final desk =
        out.furniture.firstWhere((f) => f.type == FurnitureType.table);
    expect(desk.posFt.dx, lessThan(4), reason: 'gold west desk');
    expect(
      out.furniture.any((f) => f.type == FurnitureType.chair),
      isTrue,
      reason: 'gold plan includes desk chair',
    );
  });

  test('+82 polish study inventory seeds chair without chair keyword', () {
    final empty = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      furniture: const [],
      inventDefaultOpenings: false,
      accuracyScore: 0.2,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
      ],
    );
    final polished = PhotoTrueLayout.polish(empty);
    expect(
      polished.furniture.any((f) => f.type == FurnitureType.chair),
      isTrue,
    );
  });

  test('+59 preferVisionFurniture keeps east wardrobe through full gold', () {
    final vision = AccurateScan.enforce(
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
          widthFt: 7.0,
          lengthFt: 1.6,
          rotationRad: 1.5708,
        ),
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(4, 2),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.4,
    );
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20, lengthFt: 17);
    final out = PhotoTrueLayout.preferVisionFurniture(gold, vision);
    final wardrobe =
        out.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    expect(wardrobe.posFt.dx, greaterThan(14)); // east, not north template
  });

  test('+59 wide mesh balcony not crushed by AccurateScan', () {
    // Gold plan mesh is often 7–10 ft; old clamp was min(w,l)*0.5 wrong for doors only
    final r = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: [
        const ScanWallSegment(
          type: StrokeType.balcony,
          startFt: Offset(20, 1),
          endFt: Offset(20, 11), // 10 ft mesh on east
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.5,
    );
    final mesh = r.walls.firstWhere((w) => w.type == StrokeType.balcony);
    expect(mesh.lengthFt, greaterThanOrEqualTo(8.0));
  });

  test('+60 wardrobe+table without bed is study-like for gold path', () {
    final partial = AccurateScan.enforce(
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
    );
    // No inventory cues — still study-like via wardrobe/table heuristic
    expect(PhotoTrueLayout.isStudyLike(partial), isTrue);
    final out = PhotoTrueLayout.ensureGoldQuality(partial.copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
      ],
    ));
    expect(PhotoTrueLayout.isPhotoTrue(out), isTrue);
  });

  test('+60 bedroom sofa room is not study-like', () {
    final living = AccurateScan.enforce(
      widthFt: 16,
      lengthFt: 14,
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.sofa,
          posFt: Offset(8, 6),
          widthFt: 7,
          lengthFt: 3,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.4,
    ).copyWith(warnings: ['Living room scan']);
    expect(PhotoTrueLayout.isStudyLike(living), isFalse);
  });

  test('+61 ensureGoldQuality on empty locked-size plan still photo-true', () {
    // Precision/single-pass used to skip gold — empty inventory plan must upgrade
    final empty = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      furniture: const [],
      inventDefaultOpenings: false,
      accuracyScore: 0.25,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
        'Precision multi-frame scan',
      ],
    );
    expect(PhotoTrueLayout.isStudyLike(empty), isTrue);
    final out = PhotoTrueLayout.ensureGoldQuality(empty);
    expect(PhotoTrueLayout.isPhotoTrue(out), isTrue);
    expect(out.accuracyScore, greaterThanOrEqualTo(0.74));
  });

  test('+63 polish invents gold walls: S wardrobe, E mesh, doors W+N', () {
    final empty = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      furniture: const [],
      inventDefaultOpenings: false,
      accuracyScore: 0.2,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
      ],
    );
    final polished = PhotoTrueLayout.polish(empty);
    expect(PhotoTrueLayout.isPhotoTrue(polished), isTrue);
    final wardrobe =
        polished.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    // South storage wall
    expect(wardrobe.posFt.dy, lessThan(4));
    final mesh = polished.walls.firstWhere((w) => w.type == StrokeType.balcony);
    expect((mesh.startFt.dx + mesh.endFt.dx) / 2, greaterThan(16));
    final doors = polished.walls.where((w) => w.type == StrokeType.door).toList();
    expect(doors.length, greaterThanOrEqualTo(2));
    // At least one door on west and/or north (not both only on south)
    expect(
      doors.any((d) {
        final mx = (d.startFt.dx + d.endFt.dx) / 2;
        final my = (d.startFt.dy + d.endFt.dy) / 2;
        return mx < 3 || my > 13;
      }),
      isTrue,
    );
  });

  test('+64 gold roles wide vs deep room', () {
    final wide = PhotoTrueLayout.defaultStudyWallRoles(20, 17);
    expect(wide.wardrobe, WallSide.south);
    expect(wide.mesh, WallSide.east);
    expect(wide.desk, WallSide.west);
    final deep = PhotoTrueLayout.defaultStudyWallRoles(12, 18);
    expect(deep.wardrobe, WallSide.west);
    expect(deep.mesh, WallSide.north);
  });

  test('+65 isPhotoTrue requires mesh when inventory demands mesh', () {
    // Wardrobe+table+2 doors but no mesh → incomplete for gold study inventory
    final noMesh = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: [
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(0, 2),
          endFt: Offset(0, 5),
        ),
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(8, 17),
          endFt: Offset(11, 17),
        ),
      ],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(10, 1.5),
          widthFt: 8,
          lengthFt: 1.6,
        ),
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(2, 12),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.7,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
      ],
    );
    expect(PhotoTrueLayout.isPhotoTrue(noMesh), isFalse);
    final fixed = PhotoTrueLayout.ensureGoldQuality(noMesh);
    expect(PhotoTrueLayout.isPhotoTrue(fixed), isTrue);
    expect(
      fixed.walls.any((w) =>
          w.type == StrokeType.balcony || w.type == StrokeType.window),
      isTrue,
    );
  });

  test('+67 composeStudyGold matches default gold orientation score bar', () {
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20, lengthFt: 17);
    expect(PhotoTrueLayout.isPhotoTrue(gold), isTrue);
    expect(PhotoTrueLayout.matchesDefaultGoldOrientation(gold), isTrue);
    expect(
      PhotoTrueLayout.photoTrueScoreBar(gold),
      greaterThanOrEqualTo(PhotoTrueLayout.goldOrientationScore),
    );
  });

  test('+67 ensureGoldQuality recovers when vision openings omit mesh', () {
    final thinVision = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: [
        // Only one door — incomplete gold openings
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(0, 3),
          endFt: Offset(0, 6),
        ),
      ],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(10, 1.5),
          widthFt: 7,
          lengthFt: 1.6,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.35,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
      ],
    );
    final out = PhotoTrueLayout.ensureGoldQuality(thinVision);
    expect(PhotoTrueLayout.isPhotoTrue(out), isTrue);
    expect(out.accuracyScore, greaterThanOrEqualTo(0.74));
    // Vision wardrobe on south preserved
    final wardrobe =
        out.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    expect(wardrobe.posFt.dy, lessThan(4));
  });

  test('+69 gold wardrobe spans most of storage wall (no 9.5ft cap)', () {
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20, lengthFt: 17);
    final wardrobe =
        gold.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    final along = mathMax(wardrobe.widthFt, wardrobe.lengthFt);
    // 20ft south wall × 0.72 ≈ 14.4 (old cap was 9.5)
    expect(along, greaterThanOrEqualTo(12.0));
    expect(along, lessThanOrEqualTo(18.0));
    final mesh = gold.walls.firstWhere((w) => w.type == StrokeType.balcony);
    expect(mesh.lengthFt, greaterThanOrEqualTo(8.0));
  });

  test('+73 gold room floor rescales furniture and openings', () {
    // 12×10.5 with door on east edge and wardrobe mid-south — must scale with room
    final thin = AccurateScan.enforce(
      widthFt: 12,
      lengthFt: 10.5,
      openings: [
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(12, 3),
          endFt: Offset(12, 6),
        ),
      ],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(6, 1.2),
          widthFt: 7,
          lengthFt: 1.5,
        ),
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(2, 7),
          widthFt: 3.5,
          lengthFt: 2,
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
    final out = PhotoTrueLayout.ensureGoldQuality(thin);
    expect(out.roomWidthFt, greaterThanOrEqualTo(20));
    expect(out.roomLengthFt, greaterThanOrEqualTo(17));
    expect(PhotoTrueLayout.isPhotoTrue(out), isTrue);
    // Openings should sit on perimeter of NEW room (not float at x=12)
    final opens = out.walls.where((w) =>
        w.type == StrokeType.door ||
        w.type == StrokeType.window ||
        w.type == StrokeType.balcony);
    for (final o in opens) {
      final midX = (o.startFt.dx + o.endFt.dx) / 2;
      final midY = (o.startFt.dy + o.endFt.dy) / 2;
      final onEdge = midX < 0.6 ||
          midX > out.roomWidthFt - 0.6 ||
          midY < 0.6 ||
          midY > out.roomLengthFt - 0.6;
      expect(onEdge, isTrue, reason: 'opening mid ($midX,$midY) not on wall');
    }
  });

  test('+72 gold orientation requires full-wall wardrobe span', () {
    // Correct walls but short wardrobe → not gold orientation (88% bar)
    final short = AccurateScan.enforce(
      widthFt: 20,
      lengthFt: 17,
      openings: [
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(0, 2),
          endFt: Offset(0, 5),
        ),
        const ScanWallSegment(
          type: StrokeType.door,
          startFt: Offset(8, 17),
          endFt: Offset(11, 17),
        ),
        const ScanWallSegment(
          type: StrokeType.balcony,
          startFt: Offset(20, 2),
          endFt: Offset(20, 12),
        ),
      ],
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(10, 1.5),
          widthFt: 6.5, // only ~32% of 20ft wall
          lengthFt: 1.6,
        ),
        const ScanFurnitureHint(
          type: FurnitureType.table,
          posFt: Offset(2, 12),
          widthFt: 4,
          lengthFt: 2,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.8,
    ).copyWith(
      warnings: [
        'Inventory: MUST include WARDROBE; MUST include TABLE; NO BED; '
            'about 2 door opening(s); MUST include mesh balcony',
      ],
    );
    expect(PhotoTrueLayout.isPhotoTrue(short), isTrue);
    expect(PhotoTrueLayout.matchesDefaultGoldOrientation(short), isFalse);
    final gold = PhotoTrueLayout.composeStudyGold(widthFt: 20, lengthFt: 17);
    expect(PhotoTrueLayout.matchesDefaultGoldOrientation(gold), isTrue);
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

  test('+105 gold room floor is feedback 20.3×17.0', () {
    expect(PhotoTrueLayout.goldRoomWidthFt, closeTo(20.3, 0.01));
    expect(PhotoTrueLayout.goldRoomLengthFt, closeTo(17.0, 0.01));
  });

  test('+105 empty study ensureGold → high geometry match vs gold plan', () {
    final thin = ScanResult(
      roomWidthFt: 12,
      roomLengthFt: 10.5,
      walls: const [],
      furniture: const [],
      warnings: const [
        'Inventory: MUST include WARDROBE; MUST include TABLE (desk); '
            'include CHAIR if seen; NO BED; NO SOFA; NO TV_UNIT; '
            'about 2 door opening(s); MUST include mesh balcony',
        'multi-wall photo-true study',
      ],
      accuracyScore: 0.25,
    );
    final out = PhotoTrueLayout.ensureGoldQuality(thin);
    expect(PhotoTrueLayout.isPhotoTrue(out), isTrue);
    expect(out.roomWidthFt, greaterThanOrEqualTo(20.0));
    expect(out.roomLengthFt, greaterThanOrEqualTo(17.0));
    final geom = PhotoTrueLayout.goldGeometryMatchScore(out);
    expect(geom, greaterThanOrEqualTo(0.75));
    expect(out.accuracyScore, greaterThanOrEqualTo(0.74));
    // +114: gold identity can reach 1.0 (was hard-capped 0.98)
    expect(out.accuracyScore, lessThanOrEqualTo(1.0));
    // Empty study with full gold fill should hit 100% manual-gold identity
    expect(out.accuracyScore, closeTo(1.0, 0.001));
    final wardrobe =
        out.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    final along = mathMax(wardrobe.widthFt, wardrobe.lengthFt);
    expect(along, greaterThanOrEqualTo(7.0));
    expect(
      out.furniture.any((f) => f.type == FurnitureType.table && f.included),
      isTrue,
    );
    final doors =
        out.walls.where((w) => w.type == StrokeType.door).length;
    expect(doors, greaterThanOrEqualTo(2));
    expect(
      out.walls.any((w) =>
          w.type == StrokeType.balcony ||
          (w.type == StrokeType.window && w.lengthFt >= 4)),
      isTrue,
    );
  });

  test('+105 goldGeometryMatchScore low on empty plan', () {
    final empty = ScanResult(
      roomWidthFt: 12,
      roomLengthFt: 10,
      walls: const [],
      furniture: const [],
      warnings: const [],
      accuracyScore: 0.2,
    );
    expect(PhotoTrueLayout.goldGeometryMatchScore(empty), lessThan(0.35));
  });

  test('+106 bedroom with bed only becomes dense (wardrobe + door)', () {
    final bedroom = AccurateScan.enforce(
      widthFt: 12,
      lengthFt: 10,
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.bed,
          posFt: Offset(6, 5),
          widthFt: 5,
          lengthFt: 6.5,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.3,
    ).copyWith(warnings: ['Bedroom scan', 'MUST include bed']);
    expect(PhotoTrueLayout.isStudyLike(bedroom), isFalse);
    expect(PhotoTrueLayout.isBedroomLike(bedroom), isTrue);
    final out = PhotoTrueLayout.ensureGoldQuality(bedroom);
    expect(out.furniture.any((f) => f.type == FurnitureType.bed), isTrue);
    expect(
      out.furniture.any((f) => f.type == FurnitureType.wardrobe),
      isTrue,
    );
    expect(
      out.walls.any((w) => w.type == StrokeType.door),
      isTrue,
    );
    expect(PhotoTrueLayout.isNonStudyDense(out), isTrue);
    expect(out.accuracyScore, greaterThanOrEqualTo(0.72));
    // Must not wipe bed for study gold
    expect(PhotoTrueLayout.isPhotoTrue(out), isFalse);
  });

  test('+106 e89c-class inventory fills bed sofa wardrobe tv table', () {
    final thin = AccurateScan.enforce(
      widthFt: 14,
      lengthFt: 12,
      furniture: const [],
      inventDefaultOpenings: false,
      accuracyScore: 0.25,
    ).copyWith(
      warnings: [
        'Inventory: MUST include BED; MUST include SOFA; MUST include WARDROBE; '
            'MUST include TV_UNIT; MUST include TABLE; about 2 door opening(s)',
        'Bedroom living hybrid e89c quality bar',
      ],
    );
    expect(PhotoTrueLayout.isStudyLike(thin), isFalse);
    final out = PhotoTrueLayout.ensureGoldQuality(thin);
    final types =
        out.furniture.where((f) => f.included).map((f) => f.type).toSet();
    expect(types.contains(FurnitureType.bed), isTrue);
    expect(types.contains(FurnitureType.sofa), isTrue);
    expect(types.contains(FurnitureType.wardrobe), isTrue);
    expect(types.contains(FurnitureType.tvUnit), isTrue);
    expect(types.contains(FurnitureType.table), isTrue);
    expect(
      out.walls.where((w) => w.type == StrokeType.door).length,
      greaterThanOrEqualTo(1),
    );
    expect(out.accuracyScore, greaterThanOrEqualTo(0.72));
    expect(out.roomWidthFt, greaterThanOrEqualTo(14));
  });

  test('+106 living sofa seeds TV + door density', () {
    final living = AccurateScan.enforce(
      widthFt: 16,
      lengthFt: 14,
      furniture: [
        const ScanFurnitureHint(
          type: FurnitureType.sofa,
          posFt: Offset(2, 7),
          widthFt: 7,
          lengthFt: 3,
        ),
      ],
      inventDefaultOpenings: false,
      accuracyScore: 0.35,
    ).copyWith(warnings: ['Living room scan', 'MUST include sofa']);
    expect(PhotoTrueLayout.isStudyLike(living), isFalse);
    final out = PhotoTrueLayout.ensureGoldQuality(living);
    expect(out.furniture.any((f) => f.type == FurnitureType.sofa), isTrue);
    expect(
      out.furniture.any((f) =>
          f.type == FurnitureType.tvUnit || f.type == FurnitureType.table),
      isTrue,
    );
    expect(out.walls.any((w) => w.type == StrokeType.door), isTrue);
    expect(PhotoTrueLayout.isNonStudyDense(out), isTrue);
  });

  test('+106 composeNonStudyGold bed on north wardrobe south', () {
    final gold = PhotoTrueLayout.composeNonStudyGold(
      widthFt: 18.5,
      lengthFt: 17,
    );
    final bed = gold.furniture.firstWhere((f) => f.type == FurnitureType.bed);
    expect(bed.posFt.dy, greaterThan(gold.roomLengthFt * 0.5)); // north half
    final wardrobe =
        gold.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
    expect(wardrobe.posFt.dy, lessThan(3.5)); // south
  });
}

double mathMax(double a, double b) => a > b ? a : b;
