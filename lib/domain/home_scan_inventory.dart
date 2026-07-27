import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../catalog/furniture_catalog.dart';
import '../models/furniture_item.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';
import 'accurate_scan.dart';
import 'opening_chain_fidelity.dart';
import 'photo_true_layout.dart';

/// User-reported room contents after AR size lock (+140 / +141).
///
/// Home Scan cannot see furniture/openings from pose alone. Feedback 04919d14
/// (2 doors, French window, desk, table, bean bag) requires an explicit inventory
/// so the plan is not a random AI living-room fill.
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
  });

  /// Feedback 04919d14 / typical lounge-office scan target.
  static const HomeScanInventory loungeOffice = HomeScanInventory(
    doors: 2,
    windows: 0,
    frenchWindow: true,
    desk: true,
    table: true,
    beanBag: true,
  );

  bool get hasAnyFurniture =>
      desk || table || beanBag || sofa || bed || chair;

  bool get hasAnyOpenings => doors > 0 || windows > 0 || frenchWindow;

  String get summaryLabel {
    final parts = <String>[];
    if (doors > 0) parts.add('$doors door${doors == 1 ? '' : 's'}');
    if (frenchWindow) parts.add('French window');
    if (windows > 0) parts.add('$windows window${windows == 1 ? '' : 's'}');
    if (desk) parts.add('desk');
    if (table) parts.add('table');
    if (beanBag) parts.add('bean bag');
    if (sofa) parts.add('sofa');
    if (bed) parts.add('bed');
    if (chair) parts.add('chair');
    return parts.isEmpty ? 'empty (size only)' : parts.join(', ');
  }

  /// Warning blob for OpeningChainFidelity / diagnostics.
  String get inventoryWarning {
    final bits = <String>['inventory:'];
    if (doors >= 2) {
      bits.add('2 doors');
    } else if (doors == 1) {
      bits.add('1 door');
    }
    if (frenchWindow) bits.add('french window');
    if (windows > 0) bits.add('$windows window');
    if (desk) bits.add('desk');
    if (table) bits.add('table');
    if (beanBag) bits.add('bean bag');
    if (sofa) bits.add('sofa');
    if (bed) bits.add('bed');
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
    final openings = _openings(w, l, inventory);
    final furniture = _furniture(w, l, inventory);

    var plan = AccurateScan.enforce(
      widthFt: w,
      lengthFt: l,
      openings: openings,
      furniture: furniture,
      inventDefaultOpenings: false,
      accuracyScore: accuracyScore,
      sourceLabel: 'Home Scan inventory plan (+141)',
      warnings: [
        inventory.inventoryWarning,
        'Contents: ${inventory.summaryLabel}',
        'Size locked by AR walk + confirm; openings/furniture from your inventory',
        'Not photo-detected — edit freely if placement is off',
      ],
    );

    // Opening chain only — do NOT run FurniturePositionMap free-float→wall.
    // That pass dragged coffee tables / bean bags onto walls next to doors
    // (feedback 04919d14: inventory pieces no longer matched the scan result).
    plan = OpeningChainFidelity.ensure(plan);
    plan = PhotoTrueLayout.clearDoorBlockedFurniture(plan);
    // Soft re-place any piece still in door swing (keep inventory types)
    plan = _nudgeAwayFromDoors(plan);

    // Re-assert furniture if chain pass stripped (rare)
    if (plan.furniture.where((f) => f.included).isEmpty &&
        inventory.hasAnyFurniture) {
      plan = plan.copyWith(furniture: furniture);
    }

    // Exact inventory count = high confidence (user marked contents)
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
    ].where((x) => x).length;
    final expectDoors = inventory.doors;
    final expectWin =
        (inventory.frenchWindow ? 1 : 0) + inventory.windows;
    final match = doors >= expectDoors &&
        wins >= expectWin &&
        furnN >= expectFurn &&
        !plan.furniture.any((f) =>
            f.included &&
            (f.type == FurnitureType.bed && !inventory.bed ||
                f.type == FurnitureType.sofa && !inventory.sofa));
    if (match) {
      plan = plan.copyWith(
        accuracyScore: math.max(plan.accuracyScore ?? 0.9, 0.96),
        warnings: [
          ...plan.warnings,
          'Inventory match (+141): $doors doors · $wins windows · '
              '$furnN furniture (no invented bed/sofa)',
        ],
      );
    }

    return plan;
  }

  /// Push free pieces out of door swing without wall-remapping majors.
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
      // Prefer center of room (coffee table / bean bag)
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
        'Inventory (+141): nudged furniture clear of door swing',
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

    // Door 1: long south wall, left of center (entry)
    if (inv.doors >= 1) {
      final cx = (w * 0.28).clamp(doorLen / 2 + 0.5, w - doorLen / 2 - 0.5);
      out.add(ScanWallSegment(
        type: StrokeType.door,
        startFt: Offset(cx - doorLen / 2, l),
        endFt: Offset(cx + doorLen / 2, l),
      ));
    }
    // Door 2: short west wall (second entry) — feedback wants 2 doors
    if (inv.doors >= 2) {
      final cy = (l * 0.45).clamp(doorLen / 2 + 0.5, l - doorLen / 2 - 0.5);
      out.add(ScanWallSegment(
        type: StrokeType.door,
        startFt: Offset(0, cy - doorLen / 2),
        endFt: Offset(0, cy + doorLen / 2),
      ));
    }
    // Door 3 rare: east wall
    if (inv.doors >= 3) {
      final cy = (l * 0.55).clamp(doorLen / 2 + 0.5, l - doorLen / 2 - 0.5);
      out.add(ScanWallSegment(
        type: StrokeType.door,
        startFt: Offset(w, cy - doorLen / 2),
        endFt: Offset(w, cy + doorLen / 2),
      ));
    }

    // French window: wide glazing on north (long) wall — not a mesh door
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

    // Extra regular windows on remaining free walls
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
      // Keep fully inside room
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

    // Desk: east work wall, north of center so clear of south entry door
    if (inv.desk) {
      final deskDeep = 2.2;
      final h = fromCatalog(
        'desk',
        Offset(w - deskDeep / 2 - 0.2, l * 0.32),
        rot: math.pi / 2,
      );
      if (h != null) out.add(h);
    }

    // Coffee table: mid-room under French window (NOT wall-hugged — lounge center)
    if (inv.table) {
      final h = fromCatalog(
        'coffee_table',
        Offset(w * 0.50, l * 0.42),
      );
      if (h != null) out.add(h);
    }

    // Bean bag: SE lounge corner, clear of west + south doors
    if (inv.beanBag) {
      final h = fromCatalog(
        'bean_bag',
        Offset(w * 0.78, l * 0.72),
      );
      if (h != null) out.add(h);
    }

    // Sofa: north wall under / beside French window span
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
        Offset(w * 0.38, l * 0.55),
      );
      if (h != null) out.add(h);
    }

    return out;
  }
}
