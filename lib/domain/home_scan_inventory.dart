import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../catalog/furniture_catalog.dart';
import '../models/scan_result.dart';
import '../models/stroke_model.dart';
import 'accurate_scan.dart';
import 'furniture_position_map.dart';
import 'opening_chain_fidelity.dart';
import 'photo_true_layout.dart';

/// User-reported room contents after AR size lock (+140).
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
      sourceLabel: 'Home Scan inventory plan (+140)',
      warnings: [
        inventory.inventoryWarning,
        'Contents: ${inventory.summaryLabel}',
        'Size locked by AR walk + confirm; openings/furniture from your inventory',
        'Not photo-detected — edit freely if placement is off',
      ],
    );

    plan = OpeningChainFidelity.ensure(plan);
    plan = FurniturePositionMap.ensure(plan);
    plan = PhotoTrueLayout.clearDoorBlockedFurniture(plan);

    // Re-assert furniture if chain pass stripped (rare)
    if (plan.furniture.where((f) => f.included).isEmpty &&
        inventory.hasAnyFurniture) {
      plan = plan.copyWith(furniture: furniture);
    }

    return plan;
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
    final margin = 1.6;

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
      final cx = center.dx.clamp(wf / 2 + 0.3, w - wf / 2 - 0.3);
      final cy = center.dy.clamp(lf / 2 + 0.3, l - lf / 2 - 0.3);
      return ScanFurnitureHint(
        type: e.type,
        posFt: Offset(cx, cy),
        widthFt: wf,
        lengthFt: lf,
        rotationRad: rot,
        included: true,
      );
    }

    // Desk against east wall (work surface)
    if (inv.desk) {
      final h = fromCatalog(
        'desk',
        Offset(w - margin, l * 0.38),
        rot: math.pi / 2,
      );
      if (h != null) out.add(h);
    }

    // Table toward room center / south of french window
    if (inv.table) {
      final h = fromCatalog(
        'coffee_table',
        Offset(w * 0.48, l * 0.48),
      );
      if (h != null) out.add(h);
    }

    // Bean bag lounge corner (away from doors)
    if (inv.beanBag) {
      final h = fromCatalog(
        'bean_bag',
        Offset(w * 0.72, l * 0.78),
      );
      if (h != null) out.add(h);
    }

    if (inv.sofa) {
      final h = fromCatalog(
        'sofa_3',
        Offset(w * 0.5, margin + 1.2),
      );
      if (h != null) out.add(h);
    }

    if (inv.bed) {
      final h = fromCatalog(
        'queen_bed',
        Offset(w * 0.5, l * 0.35),
      );
      if (h != null) out.add(h);
    }

    if (inv.chair) {
      final h = fromCatalog(
        'dining_chair',
        Offset(w * 0.35, l * 0.55),
      );
      if (h != null) out.add(h);
    }

    return out;
  }
}
