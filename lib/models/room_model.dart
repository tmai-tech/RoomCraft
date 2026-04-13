import 'stroke_model.dart';
import 'furniture_item.dart';

class RoomModel {
  final String id;
  String name;
  double lengthInFeet;
  double widthInFeet;
  List<StrokeModel> strokes;
  List<FurnitureItem> furniture;
  String? userId;

  RoomModel({
    required this.id,
    required this.name,
    required this.lengthInFeet,
    required this.widthInFeet,
    this.strokes = const [],
    this.furniture = const [],
    this.userId,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'lengthInFeet': lengthInFeet,
      'widthInFeet': widthInFeet,
      'strokes': strokes.map((x) => x.toMap()).toList(),
      'furniture': furniture.map((x) => x.toMap()).toList(),
      'userId': userId,
    };
  }

  factory RoomModel.fromMap(Map<String, dynamic> map) {
    return RoomModel(
      id: map['id'],
      name: map['name'],
      lengthInFeet: map['lengthInFeet']?.toDouble() ?? 0.0,
      widthInFeet: map['widthInFeet']?.toDouble() ?? 0.0,
      strokes: List<StrokeModel>.from(map['strokes']?.map((x) => StrokeModel.fromMap(x)) ?? []),
      furniture: List<FurnitureItem>.from(map['furniture']?.map((x) => FurnitureItem.fromMap(x)) ?? []),
      userId: map['userId'],
    );
  }
}
