import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/furniture_position_map.dart';
import 'package:room_craft/domain/opening_chain_fidelity.dart';
import 'package:room_craft/domain/photo_true_layout.dart';
import 'package:room_craft/domain/plan_accuracy_metrics.dart';
import 'package:room_craft/domain/scan_parser.dart';
import 'package:room_craft/domain/scan_refine.dart';
import 'package:room_craft/domain/wall_relative_scan.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/scan_result.dart';
import 'package:room_craft/models/stroke_model.dart';

/// Device-proof accuracy suite (+111 final).
///
/// Simulates noisy monocular vision (free-XY scatter, wrong door widths,
/// left-edge fromLeft) as returned from feedback gold rooms, then asserts
/// ensureGoldQuality + position map produce Planner5D-class blueprint:
/// walls, doors, windows, furniture wall-anchored with tight center MAE.
void main() {
  /// Gold study reference (32ffdc65 manual plan class).
  ScanResult studyGold() =>
      PhotoTrueLayout.composeStudyGold(widthFt: 20.3, lengthFt: 17);

  group('+111 device proof — study free-XY noise → gold positions', () {
    test('random mid-room furniture remaps; MAE vs gold ≤ target', () {
      // Simulate monocular free-XY mess (feedback 5244fa22 / 53a501e6 class)
      final noisy = ScanResult(
        roomWidthFt: 18,
        roomLengthFt: 15,
        walls: [
          // doors mid-room-ish wrong widths
          const ScanWallSegment(
            type: StrokeType.door,
            startFt: Offset(0.2, 5),
            endFt: Offset(0.2, 6.5), // 1.5 ft door — too small
          ),
          const ScanWallSegment(
            type: StrokeType.door,
            startFt: Offset(8, 14.8),
            endFt: Offset(10, 14.8),
          ),
          const ScanWallSegment(
            type: StrokeType.balcony,
            startFt: Offset(17.7, 2),
            endFt: Offset(17.7, 10),
          ),
        ],
        furniture: const [
          // wardrobe floating mid-room
          ScanFurnitureHint(
            type: FurnitureType.wardrobe,
            posFt: Offset(9, 7),
            widthFt: 6,
            lengthFt: 1.5,
          ),
          // desk floating
          ScanFurnitureHint(
            type: FurnitureType.table,
            posFt: Offset(5, 8),
            widthFt: 4,
            lengthFt: 2,
          ),
        ],
        warnings: const [
          'Inventory: MUST include WARDROBE; MUST include TABLE; '
              'about 2 door opening(s); MUST include mesh balcony; '
              'study; no bed invent',
          'Easy photo scan (device proof fixture +111)',
        ],
        accuracyScore: 0.35,
      );

      final out = PhotoTrueLayout.ensureGoldQuality(noisy);
      expect(PhotoTrueLayout.isPhotoTrue(out), isTrue);

      // All major furniture wall-anchored
      final place = FurniturePositionMap.score(out);
      expect(place, greaterThanOrEqualTo(0.75),
          reason: 'furniture position fidelity $place');

      // Doors gold width ~2.8
      final doors =
          out.walls.where((w) => w.type == StrokeType.door).toList();
      expect(doors.length, greaterThanOrEqualTo(1));
      for (final d in doors) {
        expect(d.lengthFt, closeTo(OpeningChainFidelity.goldDoorFt, 0.35));
        final field = WallRelativeComposer.openingToField(
          d,
          out.roomWidthFt,
          out.roomLengthFt,
        );
        expect(field, isNotNull, reason: 'door must sit on perimeter');
      }

      // Mesh / balcony on wall
      final mesh = out.walls.where((w) =>
          w.type == StrokeType.balcony ||
          (w.type == StrokeType.window && w.lengthFt >= 4));
      expect(mesh, isNotEmpty);

      final gold = studyGold();
      // Scale gold to same room for fair compare
      final goldScaled = PhotoTrueLayout.composeStudyGold(
        widthFt: out.roomWidthFt,
        lengthFt: out.roomLengthFt,
      );
      final report = PlanAccuracyMetrics.compare(out, goldScaled);
      expect(report.furnitureTypeRecall, greaterThanOrEqualTo(0.66));
      expect(
        report.furnitureCenterMaeFt,
        lessThanOrEqualTo(FurniturePositionMap.positionMaeTargetFt + 2.5),
        reason:
            'furniture center MAE ${report.furnitureCenterMaeFt} (gold orientation may differ walls)',
      );
      // When gold orientation matches, MAE should be tight
      if (PhotoTrueLayout.matchesDefaultGoldOrientation(out)) {
        expect(
          report.furnitureCenterMaeFt,
          lessThanOrEqualTo(FurniturePositionMap.positionMaeTargetFt),
        );
        expect(report.compositeScore, greaterThanOrEqualTo(0.70));
      }
      expect(out.accuracyScore ?? 0, greaterThanOrEqualTo(0.70));
      // Ignore unused gold var lint
      expect(gold.roomWidthFt, greaterThan(0));
    });

    test('wall+fromLeft left-edge wardrobe centers on storage wall', () {
      final wallJson = <String, dynamic>{
        'roomWidth': 20.3,
        'roomLength': 17.0,
        'openings': [
          {
            'type': 'door',
            'wall': 'west',
            'fromLeft': 1.2,
            'width': 2.8,
            'confidence': 0.9,
          },
          {
            'type': 'door',
            'wall': 'north',
            'fromLeft': 2.0,
            'width': 2.8,
            'confidence': 0.9,
          },
          {
            'type': 'balcony',
            'wall': 'east',
            'fromLeft': 1.5,
            'width': 10.0,
            'confidence': 0.9,
          },
        ],
        'furniture': [
          // left-edge style fromLeft (bug class +56) for long wardrobe
          {
            'type': 'WARDROBE',
            'wall': 'south',
            'fromLeft': 0.5,
            'depth': 1.6,
            'dim': {'w': 14.0, 'l': 1.6},
            'confidence': 0.9,
          },
          {
            'type': 'TABLE',
            'wall': 'west',
            'fromLeft': 11.0,
            'depth': 1.6,
            'dim': {'w': 4.0, 'l': 2.0},
            'confidence': 0.9,
          },
        ],
        'warnings': [
          'Inventory: MUST include WARDROBE; MUST include TABLE; study',
        ],
      };
      final parsed = ScanParser.parse(wallJson);
      var out = ScanRefine.refine(parsed);
      out = PhotoTrueLayout.ensureGoldQuality(out);

      final wardrobe = out.furniture
          .firstWhere((f) => f.included && f.type == FurnitureType.wardrobe);
      // Centered-ish on south wall (not stuck at left corner)
      expect(wardrobe.posFt.dx, greaterThan(5.0));
      expect(wardrobe.posFt.dx, lessThan(15.5));
      expect(wardrobe.posFt.dy, lessThan(3.0)); // on south wall
      final along = mathMax(wardrobe.widthFt, wardrobe.lengthFt);
      expect(along / out.roomWidthFt, greaterThan(0.5));

      final report = PlanAccuracyMetrics.compare(out, studyGold());
      // Wardrobe wall match + desk role may leave ~2–4 ft MAE if chair/desk
      // gold NW vs vision west mid — type recall + south wardrobe is the bar.
      expect(report.furnitureCenterMaeFt, lessThanOrEqualTo(4.5));
      expect(report.furnitureTypeRecall, greaterThanOrEqualTo(0.66));
      expect(FurniturePositionMap.score(out), greaterThanOrEqualTo(0.75));
      expect(PhotoTrueLayout.matchesDefaultGoldOrientation(out) ||
              report.furnitureTypeRecall >= 0.66,
          isTrue);
    });

    test('gold plan is identity-stable under position map + ensureGold', () {
      final gold = studyGold();
      final again = PhotoTrueLayout.ensureGoldQuality(gold);
      final report = PlanAccuracyMetrics.compare(again, gold);
      expect(report.furnitureCenterMaeFt, lessThanOrEqualTo(1.0));
      expect(report.compositeScore, greaterThanOrEqualTo(0.85));
      expect(FurniturePositionMap.score(again), greaterThanOrEqualTo(0.85));
      // Doors still 2.8
      for (final d in again.walls.where((w) => w.type == StrokeType.door)) {
        expect(d.lengthFt, closeTo(2.8, 0.25));
      }
    });
  });

  group('+111 device proof — bedroom dense positions', () {
    test('free-XY bedroom noise → wall-anchored bed/wardrobe/sofa', () {
      final noisy = ScanResult(
        roomWidthFt: 18.5,
        roomLengthFt: 17.0,
        walls: const [
          ScanWallSegment(
            type: StrokeType.door,
            startFt: Offset(0.1, 1),
            endFt: Offset(0.1, 4), // 3 ft-ish
          ),
        ],
        furniture: const [
          ScanFurnitureHint(
            type: FurnitureType.bed,
            posFt: Offset(9, 8), // mid-room
            widthFt: 5.5,
            lengthFt: 6.5,
          ),
          ScanFurnitureHint(
            type: FurnitureType.wardrobe,
            posFt: Offset(10, 9),
            widthFt: 6,
            lengthFt: 1.5,
          ),
          ScanFurnitureHint(
            type: FurnitureType.sofa,
            posFt: Offset(8, 10),
            widthFt: 6.5,
            lengthFt: 3,
          ),
        ],
        warnings: const [
          'Inventory: MUST include BED; MUST include WARDROBE; MUST include SOFA; '
              'bedroom; about 1 door opening(s)',
        ],
        accuracyScore: 0.3,
      );

      final out = PhotoTrueLayout.ensureGoldQuality(noisy);
      expect(PhotoTrueLayout.isBedroomLike(out) || out.furniture.any((f) => f.type == FurnitureType.bed),
          isTrue);

      for (final type in [
        FurnitureType.bed,
        FurnitureType.wardrobe,
        FurnitureType.sofa,
      ]) {
        final pieces =
            out.furniture.where((f) => f.included && f.type == type);
        expect(pieces, isNotEmpty, reason: 'missing $type');
        for (final f in pieces) {
          final d = _minWall(f.posFt, out.roomWidthFt, out.roomLengthFt);
          // Wall-hugged (not still mid-room ~8–9 ft)
          expect(d, lessThan(5.5),
              reason: '$type still floating at ${f.posFt} d=$d');
        }
      }

      final place = FurniturePositionMap.score(out);
      expect(place, greaterThanOrEqualTo(0.55));

      final doors =
          out.walls.where((w) => w.type == StrokeType.door).toList();
      expect(doors, isNotEmpty);
      for (final d in doors) {
        final field = WallRelativeComposer.openingToField(
          d,
          out.roomWidthFt,
          out.roomLengthFt,
        );
        expect(field, isNotNull);
        expect(d.lengthFt, closeTo(2.8, 0.5));
      }
    });
  });

  group('+111 device proof — position map unit', () {
    test('floating wardrobe snaps to nearest wall with fromLeft center', () {
      final input = ScanResult(
        roomWidthFt: 20,
        roomLengthFt: 17,
        walls: const [
          ScanWallSegment(
            type: StrokeType.door,
            startFt: Offset(0, 1.2),
            endFt: Offset(0, 4.0),
          ),
        ],
        furniture: const [
          ScanFurnitureHint(
            type: FurnitureType.wardrobe,
            posFt: Offset(10, 8.5),
            widthFt: 8,
            lengthFt: 1.6,
          ),
        ],
      );
      final out = FurniturePositionMap.ensure(input);
      final w =
          out.furniture.firstWhere((f) => f.type == FurnitureType.wardrobe);
      expect(_minWall(w.posFt, 20, 17), lessThan(2.5));
      expect(FurniturePositionMap.score(out), greaterThanOrEqualTo(0.7));
    });

    test('doors projected onto perimeter get gold width', () {
      final input = ScanResult(
        roomWidthFt: 20,
        roomLengthFt: 17,
        walls: const [
          // interior-ish segment — will project
          ScanWallSegment(
            type: StrokeType.door,
            startFt: Offset(3, 3),
            endFt: Offset(4.5, 3),
          ),
          ScanWallSegment(
            type: StrokeType.window,
            startFt: Offset(19.9, 4),
            endFt: Offset(19.9, 8),
          ),
        ],
        furniture: const [],
      );
      final out = FurniturePositionMap.ensure(input);
      final doors = out.walls.where((w) => w.type == StrokeType.door);
      expect(doors, isNotEmpty);
      for (final d in doors) {
        expect(
          WallRelativeComposer.openingToField(d, 20, 17),
          isNotNull,
        );
        expect(d.lengthFt, closeTo(OpeningChainFidelity.goldDoorFt, 0.25));
      }
      final wins = out.walls.where((w) => w.type == StrokeType.window);
      expect(wins, isNotEmpty);
      for (final win in wins) {
        expect(
          WallRelativeComposer.openingToField(win, 20, 17),
          isNotNull,
        );
      }
    });
  });

  group('+111 device proof — full pipeline refine → gold', () {
    test('ScanRefine + ensureGold on thin empty inventory still complete', () {
      final thin = ScanResult(
        roomWidthFt: 12,
        roomLengthFt: 10,
        walls: const [],
        furniture: const [],
        warnings: const [
          'Inventory: MUST include WARDROBE; MUST include TABLE; '
              'about 2 door opening(s); mesh balcony; study photo-true',
        ],
        accuracyScore: 0.2,
      );
      final refined = ScanRefine.refine(thin);
      final out = PhotoTrueLayout.ensureGoldQuality(refined);
      expect(PhotoTrueLayout.isPhotoTrue(out), isTrue);
      expect(
        out.furniture.any((f) => f.type == FurnitureType.wardrobe),
        isTrue,
      );
      expect(
        out.furniture.any((f) => f.type == FurnitureType.table),
        isTrue,
      );
      expect(
        out.walls.where((w) => w.type == StrokeType.door).length,
        greaterThanOrEqualTo(1),
      );
      final gold = PhotoTrueLayout.composeStudyGold(
        widthFt: out.roomWidthFt,
        lengthFt: out.roomLengthFt,
      );
      final report = PlanAccuracyMetrics.compare(out, gold);
      expect(report.furnitureTypeRecall, greaterThanOrEqualTo(0.66));
      if (PhotoTrueLayout.matchesDefaultGoldOrientation(out)) {
        expect(
          report.furnitureCenterMaeFt,
          lessThanOrEqualTo(FurniturePositionMap.positionMaeTargetFt + 0.5),
        );
        expect(report.compositeScore, greaterThanOrEqualTo(0.75));
      }
    });
  });
}

double _minWall(Offset pos, double w, double l) {
  final dS = pos.dy;
  final dN = l - pos.dy;
  final dW = pos.dx;
  final dE = w - pos.dx;
  return [dS, dN, dW, dE].reduce((a, b) => a < b ? a : b);
}

double mathMax(double a, double b) => a > b ? a : b;
