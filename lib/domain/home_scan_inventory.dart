import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../catalog/furniture_catalog.dart';
import '../models/furniture_item.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';
import 'accurate_scan.dart';
import 'opening_chain_fidelity.dart';
import 'photo_true_layout.dart';

/// User-reported room contents after AR size lock (+140–+143).
///
/// Home Scan cannot see furniture/openings from pose alone.
/// - Lounge: feedback 04919d14 (2 doors, French window, desk, table, bean bag)
/// - Study gold: feedback 32ffdc65 / e89c / +36 quality (wardrobe, dual doors, mesh, desk)
class HomeScanInventory {
  final int doors;
  final int windows;
  final bool frenchWindow;
  final bool desk;
  final bool table;
  final bool beanBag;
  final bool sofa;
  final bool bed;
  final bool chair;
  final bool wardrobe;

  const HomeScanInventory({
    this.doors = 0,
    this.windows = 0,
    this.frenchWindow = false,
    this.desk = false,
    this.table = false,
    this.beanBag = false,
    this.sofa = false,
    this.bed = false,
    this.chair = false,
    this.wardrobe = false,
  });

  /// Feedback 04919d14 / lounge-office.
  static const HomeScanInventory loungeOffice = HomeScanInventory(
    doors: 2,
    windows: 0,
    frenchWindow: true,
    desk: true,
    table: true,
    beanBag: true,
  );

  /// Feedback 32ffdc65 / e89c / build +36 photo-true gold study layout.
  static const HomeScanInventory studyGold = HomeScanInventory(
    doors: 2,
    windows: 0,
    frenchWindow: true,
    desk: true,
    table: true,
    chair: true,
    wardrobe: true,
  );

  bool get hasAnyFurniture =>
      desk || table || beanBag || sofa || bed || chair || wardrobe;

  bool get hasAnyOpenings => doors > 0 || windows > 0 || frenchWindow;

  /// Use dense Planner5D/study gold geometry (not sparse free-float lounge).
  ///
  /// +146: only when **wardrobe** is marked (or explicit study preset).
  /// Previously desk+table+2 doors alone triggered study gold and overwrote
  /// lounge-like rooms with a full-wall wardrobe (feedback b5fa46b8).
  bool get usesStudyGoldLayout =>
      wardrobe && !beanBag && !sofa && !bed;

  /// True when user has picked enough to build a plan (+146).
  bool get isReadyToPlace => hasAnyOpenings || hasAnyFurniture;

  /// Checklist lines for confirm UI (+146 Phase 2).
  List<String> matchChecklistLines() {
    final lines = <String>[];
    if (doors > 0) {
      lines.add('☐ $doors door${doors == 1 ? '' : 's'} on plan');
    }
    if (frenchWindow) lines.add('☐ French window (wide glazing)');
    if (windows > 0) {
      lines.add('☐ $windows window${windows == 1 ? '' : 's'}');
    }
    if (wardrobe) lines.add('☐ Wardrobe (study gold wall unit)');
    if (desk) lines.add('☐ Desk');
    if (table) lines.add('☐ Table (mid-room)');
    if (beanBag) lines.add('☐ Bean bag');
    if (sofa) lines.add('☐ Sofa');
    if (bed) lines.add('☐ Bed');
    if (chair) lines.add('☐ Chair');
    if (lines.isEmpty) {
      lines.add('☐ Pick a preset or mark openings / furniture');
    }
    return lines;
  }

  String get summaryLabel {
    final parts = <String>[];
    if (doors > 0) parts.add('$doors door${doors == 1 ? '' : 's'}');
    if (frenchWindow) parts.add('French window');
    if (windows > 0) parts.add('$windows window${windows == 1 ? '' : 's'}');
    if (wardrobe) parts.add('wardrobe');
    if (desk) parts.add('desk');
    if (table) parts.add('table');
    if (beanBag) parts.add('bean bag');
    if (sofa) parts.add('sofa');
    if (bed) parts.add('bed');
    if (chair) parts.add('chair');
    return parts.isEmpty ? 'empty (size only)' : parts.join(', ');
  }

  String get inventoryWarning {
    final bits = <String>['inventory:'];
    if (usesStudyGoldLayout) bits.add('study gold');
    if (doors >= 2) {
      bits.add('2 doors');
    } else if (doors == 1) {
      bits.add('1 door');
    }
    if (frenchWindow) bits.add('french window');
    if (windows > 0) bits.add('$windows window');
    if (wardrobe) bits.add('wardrobe');
    if (desk) bits.add('desk');
    if (table) bits.add('table');
    if (beanBag) bits.add('bean bag');
    if (sofa) bits.add('sofa');
    if (bed) bits.add('bed');
    if (chair) bits.add('chair');
    return bits.join(' ');
  }

  HomeScanInventory copyWith({
    int? doors,
    int? windows,
    bool? frenchWindow,
    bool? desk,
    bool? table,
    bool? beanBag,
    bool? sofa,
    bool? bed,
    bool? chair,
    bool? wardrobe,
  }) {
    return HomeScanInventory(
      doors: doors ?? this.doors,
      windows: windows ?? this.windows,
      frenchWindow: frenchWindow ?? this.frenchWindow,
      desk: desk ?? this.desk,
      table: table ?? this.table,
      beanBag: beanBag ?? this.beanBag,
      sofa: sofa ?? this.sofa,
      bed: bed ?? this.bed,
      chair: chair ?? this.chair,
      wardrobe: wardrobe ?? this.wardrobe,
    );
  }
}

/// Compose metric openings + catalog furniture from [HomeScanInventory].
class HomeScanInventoryComposer {
  HomeScanInventoryComposer._();

  static ScanResult compose({
    required double widthFt,
    required double lengthFt,
    required HomeScanInventory inventory,
    double accuracyScore = 0.92,
  }) {
    final w = widthFt >= lengthFt ? widthFt : lengthFt;
    final l = widthFt >= lengthFt ? lengthFt : widthFt;

    // +143/+144: study gold layout = +36 quality (32ffdc65 / e89c), not sparse lounge
    if (inventory.usesStudyGoldLayout) {
      var plan = PhotoTrueLayout.composeStudyGold(
        widthFt: w,
        lengthFt: l,
        includeChair: inventory.chair || inventory.beanBag,
        warnings: [
          inventory.inventoryWarning,
          'Contents: ${inventory.summaryLabel}',
          'Study gold layout (+144): wardrobe + dual doors + mesh + desk '
              '(build +36 photo-true quality, size from AR confirm)',
          'Home Scan inventory plan (+144)',
        ],
      );
      plan = OpeningChainFidelity.ensure(plan);
      plan = PhotoTrueLayout.clearDoorBlockedFurniture(plan);
      plan = PhotoTrueLayout.cleanStudyDeskAndDoors(plan);
      // Density guard (be325971 “worse than +36”): never return thin plan
      final n = plan.furniture.where((f) => f.included).length;
      if (n < 3 ||
          !plan.furniture.any((f) => f.included && f.type == FurnitureType.wardrobe)) {
        plan = PhotoTrueLayout.composeStudyGold(
          widthFt: w,
          lengthFt: l,
          includeChair: true,
          warnings: [
            ...plan.warnings,
            'Study gold density restore (+144)',
          ],
        );
        plan = OpeningChainFidelity.ensure(plan);
        plan = PhotoTrueLayout.cleanStudyDeskAndDoors(plan);
      }
      return plan.copyWith(
        accuracyScore: math.max(plan.accuracyScore ?? 0.9, 0.96),
        warnings: [
          ...plan.warnings,
          'Inventory study gold match (+144)',
        ],
      );
    }

    final openings = _openings(w, l, inventory);
    final furniture = _furniture(w, l, inventory);

    var plan = AccurateScan.enforce(
      widthFt: w,
      lengthFt: l,
      openings: openings,
      furniture: furniture,
      inventDefaultOpenings: false,
      accuracyScore: accuracyScore,
      sourceLabel: 'Home Scan inventory plan (+143)',
      warnings: [
        inventory.inventoryWarning,
        'Contents: ${inventory.summaryLabel}',
        'Size locked by AR walk + confirm; openings/furniture from your inventory',
        'Not photo-detected — edit freely if placement is off',
      ],
    );

    // Opening chain only — do NOT run FurniturePositionMap free-float→wall.
    plan = OpeningChainFidelity.ensure(plan);
    plan = PhotoTrueLayout.clearDoorBlockedFurniture(plan);
    plan = _nudgeAwayFromDoors(plan);

    if (plan.furniture.where((f) => f.included).isEmpty &&
        inventory.hasAnyFurniture) {
      plan = plan.copyWith(furniture: furniture);
    }

    final report = matchReport(plan, inventory);
    if (report.fullMatch) {
      plan = plan.copyWith(
        accuracyScore: math.max(plan.accuracyScore ?? 0.9, 0.96),
        warnings: [
          ...plan.warnings,
          'Inventory match (+146): ${report.summary}',
        ],
      );
    } else {
      plan = plan.copyWith(
        warnings: [
          ...plan.warnings,
          'Inventory partial (+146): ${report.summary}',
        ],
      );
    }

    return plan;
  }

  /// Phase 2 match report — counts vs inventory chips.
  static ({
    bool fullMatch,
    int doors,
    int windows,
    int furniture,
    int expectDoors,
    int expectWindows,
    int expectFurniture,
    String summary,
    List<String> missing,
  }) matchReport(ScanResult plan, HomeScanInventory inventory) {
    final doors =
        plan.walls.where((s) => s.type == StrokeType.door).length;
    final wins = plan.walls
        .where((s) =>
            s.type == StrokeType.window || s.type == StrokeType.balcony)
        .length;
    final furnN = plan.furniture.where((f) => f.included).length;
    final expectFurn = [
      inventory.desk,
      inventory.table,
      inventory.beanBag,
      inventory.sofa,
      inventory.bed,
      inventory.chair,
      inventory.wardrobe,
    ].where((x) => x).length;
    final expectDoors = inventory.doors;
    final expectWin =
        (inventory.frenchWindow ? 1 : 0) + inventory.windows;
    final missing = <String>[];
    if (doors < expectDoors) {
      missing.add('${expectDoors - doors} door(s)');
    }
    if (wins < expectWin) {
      missing.add('${expectWin - wins} window(s)');
    }
    if (furnN < expectFurn) {
      missing.add('${expectFurn - furnN} furniture');
    }
    final invented = plan.furniture.any((f) =>
        f.included &&
        ((f.type == FurnitureType.bed && !inventory.bed) ||
            (f.type == FurnitureType.sofa && !inventory.sofa) ||
            (f.type == FurnitureType.wardrobe && !inventory.wardrobe)));
    if (invented) missing.add('unexpected bed/sofa/wardrobe');
    final match = missing.isEmpty &&
        doors >= expectDoors &&
        wins >= expectWin &&
        furnN >= expectFurn;
    return (
      fullMatch: match,
      doors: doors,
      windows: wins,
      furniture: furnN,
      expectDoors: expectDoors,
      expectWindows: expectWin,
      expectFurniture: expectFurn,
      summary:
          '$doors/$expectDoors doors · $wins/$expectWin windows · $furnN/$expectFurn furniture'
          '${missing.isEmpty ? '' : ' · missing ${missing.join(", ")}'}',
      missing: missing,
    );
  }

  static ScanResult _nudgeAwayFromDoors(ScanResult plan) {
    final w = plan.roomWidthFt;
    final l = plan.roomLengthFt;
    if (w <= 0 || l <= 0) return plan;
    final out = <ScanFurnitureHint>[];
    var moved = false;
    for (final f in plan.furniture) {
      if (!f.included) {
        out.add(f);
        continue;
      }
      if (!PhotoTrueLayout.furnitureBlocksDoorKeepOut(f, plan)) {
        out.add(f);
        continue;
      }
      final candidates = <Offset>[
        Offset(w * 0.5, l * 0.42),
        Offset(w * 0.55, l * 0.55),
        Offset(w * 0.35, l * 0.5),
        Offset(w * 0.72, l * 0.55),
        Offset(w * 0.5, l * 0.28),
      ];
      Offset? best;
      for (final c in candidates) {
        final cx = c.dx.clamp(f.widthFt / 2 + 0.3, w - f.widthFt / 2 - 0.3);
        final cy =
            c.dy.clamp(f.lengthFt / 2 + 0.3, l - f.lengthFt / 2 - 0.3);
        final at = Offset(cx, cy);
        if (!PhotoTrueLayout.furnitureBlocksDoorKeepOut(f, plan, atPos: at)) {
          best = at;
          break;
        }
      }
      if (best != null) {
        moved = true;
        out.add(f.copyWith(posFt: best));
      } else {
        out.add(f);
      }
    }
    if (!moved) return plan;
    return plan.copyWith(
      furniture: out,
      warnings: [
        ...plan.warnings,
        'Inventory (+143): nudged furniture clear of door swing',
      ],
    );
  }

  static List<ScanWallSegment> _openings(
    double w,
    double l,
    HomeScanInventory inv,
  ) {
    final out = <ScanWallSegment>[];
    final doorLen = math.min(2.8, math.min(w, l) * 0.32).clamp(2.4, 3.0);

    // Dual doors like gold study: primary south entry + secondary west
    if (inv.doors >= 1) {
      final cx = (w * 0.22).clamp(doorLen / 2 + 0.5, w - doorLen / 2 - 0.5);
      out.add(ScanWallSegment(
        type: StrokeType.door,
        startFt: Offset(cx - doorLen / 2, l),
        endFt: Offset(cx + doorLen / 2, l),
      ));
    }
    if (inv.doors >= 2) {
      final cy = (l * 0.35).clamp(doorLen / 2 + 0.5, l - doorLen / 2 - 0.5);
      out.add(ScanWallSegment(
        type: StrokeType.door,
        startFt: Offset(0, cy - doorLen / 2),
        endFt: Offset(0, cy + doorLen / 2),
      ));
    }
    if (inv.doors >= 3) {
      final cy = (l * 0.55).clamp(doorLen / 2 + 0.5, l - doorLen / 2 - 0.5);
      out.add(ScanWallSegment(
        type: StrokeType.door,
        startFt: Offset(w, cy - doorLen / 2),
        endFt: Offset(w, cy + doorLen / 2),
      ));
    }

    // French window: wide glazing on north (long) wall
    if (inv.frenchWindow) {
      final winLen =
          math.min(7.0, math.max(w * 0.42, 5.5)).clamp(5.0, w * 0.75);
      final cx = w / 2;
      out.add(ScanWallSegment(
        type: StrokeType.window,
        startFt: Offset(cx - winLen / 2, 0),
        endFt: Offset(cx + winLen / 2, 0),
      ));
    }

    var extra = inv.windows;
    if (extra > 0 && !inv.frenchWindow) {
      final winLen = math.min(4.0, w * 0.3).clamp(2.5, 4.5);
      out.add(ScanWallSegment(
        type: StrokeType.window,
        startFt: Offset((w - winLen) / 2, 0),
        endFt: Offset((w + winLen) / 2, 0),
      ));
      extra--;
    }
    if (extra > 0) {
      final winLen = math.min(3.5, l * 0.35).clamp(2.5, 4.0);
      final cy = l * 0.7;
      out.add(ScanWallSegment(
        type: StrokeType.window,
        startFt: Offset(w, cy - winLen / 2),
        endFt: Offset(w, cy + winLen / 2),
      ));
    }

    return out;
  }

  static List<ScanFurnitureHint> _furniture(
    double w,
    double l,
    HomeScanInventory inv,
  ) {
    final out = <ScanFurnitureHint>[];

    ScanFurnitureHint? fromCatalog(
      String id,
      Offset center, {
      double rot = 0,
    }) {
      final e = FurnitureCatalog.byId(id);
      if (e == null) return null;
      final wf = e.defaultWidthFt;
      final lf = e.defaultLengthFt;
      final cx = center.dx.clamp(wf / 2 + 0.35, w - wf / 2 - 0.35);
      final cy = center.dy.clamp(lf / 2 + 0.35, l - lf / 2 - 0.35);
      return ScanFurnitureHint(
        type: e.type,
        posFt: Offset(cx, cy),
        widthFt: wf,
        lengthFt: lf,
        rotationRad: rot,
        included: true,
        catalogId: id,
      );
    }

    // Wardrobe full south wall (storage) when marked
    if (inv.wardrobe) {
      final along = math.min(w * 0.72, 12.0).clamp(6.5, w * 0.88);
      final h = fromCatalog(
        'wardrobe_wide',
        Offset(w / 2, l - 0.9),
      );
      if (h != null) {
        out.add(h.copyWith(widthFt: along, lengthFt: 1.6));
      } else {
        final e = FurnitureCatalog.entryFor(FurnitureType.wardrobe);
        out.add(ScanFurnitureHint(
          type: FurnitureType.wardrobe,
          posFt: Offset(w / 2, l - 0.9),
          widthFt: along,
          lengthFt: 1.6,
          included: true,
          catalogId: e.id,
        ));
      }
    }

    // Desk: west work wall (gold NW style) — denser than sparse east-only
    if (inv.desk) {
      final h = fromCatalog(
        'desk',
        Offset(1.3, l * 0.62),
        rot: math.pi / 2,
      );
      if (h != null) out.add(h);
    }

    // Coffee / work table mid-room under French window
    if (inv.table) {
      final h = fromCatalog(
        'coffee_table',
        Offset(w * 0.50, l * 0.40),
      );
      if (h != null) out.add(h);
    }

    if (inv.beanBag) {
      final h = fromCatalog(
        'bean_bag',
        Offset(w * 0.78, l * 0.72),
      );
      if (h != null) out.add(h);
    }

    if (inv.sofa) {
      final h = fromCatalog(
        'sofa_3',
        Offset(w * 0.28, 1.6),
      );
      if (h != null) out.add(h);
    }

    if (inv.bed) {
      final h = fromCatalog(
        'queen_bed',
        Offset(w * 0.5, l * 0.38),
      );
      if (h != null) out.add(h);
    }

    if (inv.chair) {
      final h = fromCatalog(
        'dining_chair',
        Offset(w * 0.28, l * 0.55),
      );
      if (h != null) out.add(h);
    }

    return out;
  }
}
