import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:room_craft/domain/layout/auto_arrange.dart';
import 'package:room_craft/domain/local_room_scanner.dart';

void main() {
  late Directory dir;
  late File file;

  setUp(() {
    final image = img.Image(width: 640, height: 480);
    img.fill(image, color: img.ColorRgb8(180, 180, 180));
    final bytes = Uint8List.fromList(img.encodeJpg(image));
    dir = Directory.systemTemp.createTempSync('roomcraft_scan');
    file = File('${dir.path}/room.jpg')..writeAsBytesSync(bytes);
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  test('exact 10×10 stays 10×10 and does not invent furniture', () async {
    final result = await LocalRoomScanner.scan(
      images: [file],
      roomWidthFt: 10,
      roomLengthFt: 10,
      preferredLayout: RoomLayoutType.empty,
    );

    expect(result.roomWidthFt, 10);
    expect(result.roomLengthFt, 10);
    expect(result.walls.length, greaterThanOrEqualTo(4));
    expect(result.furniture, isEmpty);
  });

  test('photo aspect does not warp explicit dimensions', () async {
    // Wide photo would previously force ~14 × ~10.5 or similar.
    final result = await LocalRoomScanner.scan(
      images: [file],
      roomWidthFt: 10,
      roomLengthFt: 10,
    );

    expect(result.roomWidthFt, 10);
    expect(result.roomLengthFt, 10);
  });

  test('preset layout only when user chooses bedroom', () async {
    final result = await LocalRoomScanner.scan(
      images: [file],
      roomWidthFt: 12,
      roomLengthFt: 14,
      preferredLayout: RoomLayoutType.bedroom,
    );

    expect(result.roomWidthFt, 12);
    expect(result.roomLengthFt, 14);
    expect(result.furniture, isNotEmpty);
  });

  test('resolveDimensions prefers explicit W×L over wall map', () {
    final dims = LocalRoomScanner.resolveDimensions(
      roomWidthFt: 10,
      roomLengthFt: 10,
      wallMeasurementsFt: {file: 6},
    );
    expect(dims.widthFt, 10);
    expect(dims.lengthFt, 10);
  });

  test('two wall measurements map to width and length', () {
    final file2 = File('${dir.path}/room2.jpg')..writeAsBytesSync(file.readAsBytesSync());
    final dims = LocalRoomScanner.resolveDimensions(
      wallMeasurementsFt: {file: 11, file2: 9},
    );
    expect(dims.widthFt, 11);
    expect(dims.lengthFt, 9);
  });

  test('default without size is 10×10 square', () {
    final dims = LocalRoomScanner.resolveDimensions();
    expect(dims.widthFt, 10);
    expect(dims.lengthFt, 10);
  });
}
