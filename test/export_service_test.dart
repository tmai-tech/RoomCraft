import 'package:flutter_test/flutter_test.dart';
import 'package:room_craft/models/furniture_item.dart';
import 'package:room_craft/models/room_model.dart';
import 'package:room_craft/models/stroke_model.dart';
import 'package:room_craft/services/export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renderPng produces non-empty bytes', () async {
    final room = RoomModel(
      id: 'export-test',
      name: 'Export Room',
      widthInFeet: 12,
      lengthInFeet: 10,
      strokes: [
        StrokeModel(
          id: 'w1',
          type: StrokeType.wall,
          points: const [Offset(0, 0), Offset(240, 0)],
        ),
      ],
      furniture: const [
        FurnitureItem(
          id: 'f1',
          type: FurnitureType.bed,
          position: Offset(100, 100),
          widthInFeet: 5,
          lengthInFeet: 6.5,
        ),
      ],
    );

    final bytes = await ExportService.renderPng(room);
    expect(bytes.length, greaterThan(100));
    // PNG signature
    expect(bytes[0], 0x89);
    expect(bytes[1], 0x50);
    expect(bytes[2], 0x4E);
    expect(bytes[3], 0x47);
  });
}
