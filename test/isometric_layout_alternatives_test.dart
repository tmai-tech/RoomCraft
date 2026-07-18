import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/domain/layout/auto_arrange.dart';
import 'package:room_craft/domain/layout/collision.dart';
import 'package:room_craft/domain/layout/isometric.dart';
import 'package:room_craft/domain/layout/layout_alternatives.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/room_model.dart';

void main() {
  group('Iso projection', () {
    test('project origin is zero', () {
      expect(Iso.project(0, 0), Offset.zero);
    });

    test('project increases screen y with both axes', () {
      final a = Iso.project(10, 0);
      final b = Iso.project(0, 10);
      final c = Iso.project(10, 10);
      expect(a.dx, greaterThan(0));
      expect(b.dx, lessThan(0));
      expect(c.dy, greaterThan(a.dy));
      expect(c.dy, greaterThan(b.dy));
    });

    test('height reduces screen y', () {
      final floor = Iso.project(5, 5, 0);
      final elevated = Iso.project(5, 5, 10);
      expect(elevated.dy, lessThan(floor.dy));
    });

    test('boxCorners returns 8 points', () {
      final pts = Iso.boxCorners(cx: 50, cy: 50, w: 20, d: 30, h: 15);
      expect(pts, hasLength(8));
      final bounds = Iso.boundsOf(pts);
      expect(bounds.width, greaterThan(0));
      expect(bounds.height, greaterThan(0));
    });
  });

  group('Layout alternatives', () {
    const pxf = 20.0;

    RoomModel sampleRoom() {
      return RoomModel(
        id: 'r',
        name: 'Alt test',
        widthInFeet: 14,
        lengthInFeet: 12,
        furniture: const [
          FurnitureItem(
            id: 'bed',
            type: FurnitureType.bed,
            position: Offset(80, 80),
            widthInFeet: 5,
            lengthInFeet: 6.5,
          ),
          FurnitureItem(
            id: 'wardrobe',
            type: FurnitureType.wardrobe,
            position: Offset(200, 60),
            widthInFeet: 4,
            lengthInFeet: 2,
          ),
          FurnitureItem(
            id: 'chair',
            type: FurnitureType.chair,
            position: Offset(120, 160),
            widthInFeet: 1.8,
            lengthInFeet: 1.8,
          ),
          FurnitureItem(
            id: 'table',
            type: FurnitureType.table,
            position: Offset(160, 140),
            widthInFeet: 3.5,
            lengthInFeet: 2,
          ),
        ],
      );
    }

    test('empty room yields no alternatives', () {
      final room = RoomModel(
        id: 'e',
        name: 'Empty',
        widthInFeet: 10,
        lengthInFeet: 10,
      );
      expect(
        LayoutAlternatives.generate(room: room, pixelsPerFoot: pxf),
        isEmpty,
      );
    });

    test('generates three scored styles', () {
      final alts = LayoutAlternatives.generate(
        room: sampleRoom(),
        pixelsPerFoot: pxf,
      );
      expect(alts, hasLength(3));
      final styles = alts.map((a) => a.style).toSet();
      expect(styles, containsAll(ArrangeStyle.values));
      for (final a in alts) {
        expect(a.furniture, hasLength(4));
        // Same piece ids preserved
        expect(a.furniture.map((f) => f.id).toSet(), {
          'bed',
          'wardrobe',
          'chair',
          'table',
        });
        expect(a.score, inInclusiveRange(0, 100));
        expect(a.letter, isIn(['A', 'B', 'C']));
      }
      // Sorted by score descending
      for (var i = 0; i < alts.length - 1; i++) {
        expect(alts[i].score, greaterThanOrEqualTo(alts[i + 1].score));
      }
    });

    test('each style places without hard overlap', () {
      final room = sampleRoom();
      for (final style in ArrangeStyle.values) {
        final items = AutoArrange.arrangeWithStyle(
          room: room,
          pixelsPerFoot: pxf,
          style: style,
        );
        expect(items, hasLength(4));
        final ids = Collision.overlappingIds(items, pxf, padding: 0);
        expect(ids, isEmpty, reason: 'style $style should not overlap');
      }
    });

    test('styles produce different placements for rich inventory', () {
      final room = sampleRoom();
      final a = AutoArrange.arrangeWithStyle(
        room: room,
        pixelsPerFoot: pxf,
        style: ArrangeStyle.spacious,
      );
      final b = AutoArrange.arrangeWithStyle(
        room: room,
        pixelsPerFoot: pxf,
        style: ArrangeStyle.conversation,
      );
      // At least one piece moved differently between spacious and conversation
      final moved = a.asMap().entries.any((e) {
        final other = b.firstWhere((f) => f.id == e.value.id);
        return (other.position - e.value.position).distance > 1;
      });
      expect(moved, isTrue);
    });
  });
}
