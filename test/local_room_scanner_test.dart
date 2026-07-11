import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:room_craft/domain/layout/auto_arrange.dart';
import 'package:room_craft/domain/local_room_scanner.dart';

void main() {
  test('local scanner builds plan from synthetic image', () async {
    final image = img.Image(width: 640, height: 480);
    img.fill(image, color: img.ColorRgb8(180, 180, 180));
    final bytes = Uint8List.fromList(img.encodeJpg(image));
    final dir = Directory.systemTemp.createTempSync('roomcraft_scan');
    final file = File('${dir.path}/room.jpg')..writeAsBytesSync(bytes);

    final result = await LocalRoomScanner.scan(
      images: [file],
      wallMeasurementsFt: {file: 14.0},
      preferredLayout: RoomLayoutType.bedroom,
    );

    expect(result.roomWidthFt, greaterThan(0));
    expect(result.walls.length, greaterThanOrEqualTo(4));
    expect(result.furniture, isNotEmpty);
    expect(result.warnings.any((w) => w.contains('Free offline')), isTrue);

    dir.deleteSync(recursive: true);
  });
}
