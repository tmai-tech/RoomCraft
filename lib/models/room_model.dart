import 'package:room_craft/config/app_config.dart';
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
  int schemaVersion;
  DateTime? updatedAt;

  RoomModel({
    required this.id,
    required this.name,
    required this.lengthInFeet,
    required this.widthInFeet,
    List<StrokeModel>? strokes,
    List<FurnitureItem>? furniture,
    this.userId,
    this.schemaVersion = AppConfig.storageSchemaVersion,
    DateTime? updatedAt,
  })  : strokes = List<StrokeModel>.from(strokes ?? const []),
        furniture = List<FurnitureItem>.from(furniture ?? const []),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'schemaVersion': schemaVersion,
      'id': id,
      'name': name,
      'lengthInFeet': lengthInFeet,
      'widthInFeet': widthInFeet,
      'strokes': strokes.map((x) => x.toMap()).toList(),
      'furniture': furniture.map((x) => x.toMap()).toList(),
      'userId': userId,
      'updatedAt': (updatedAt ?? DateTime.now()).toIso8601String(),
    };
  }

  /// Safe parse — returns null if required fields are missing/corrupt.
  static RoomModel? tryFromMap(Map<String, dynamic> map) {
    try {
      return RoomModel.fromMap(map);
    } catch (_) {
      return null;
    }
  }

  factory RoomModel.fromMap(Map<String, dynamic> map) {
    final id = map['id'] as String?;
    final name = map['name'] as String?;
    if (id == null || name == null) {
      throw const FormatException('Room missing id or name');
    }

    DateTime? updatedAt;
    final rawUpdated = map['updatedAt'];
    if (rawUpdated is String) {
      updatedAt = DateTime.tryParse(rawUpdated);
    }

    return RoomModel(
      id: id,
      name: name,
      lengthInFeet: (map['lengthInFeet'] as num?)?.toDouble() ?? 0.0,
      widthInFeet: (map['widthInFeet'] as num?)?.toDouble() ?? 0.0,
      strokes: _parseStrokes(map['strokes']),
      furniture: _parseFurniture(map['furniture']),
      userId: map['userId'] as String?,
      schemaVersion:
          (map['schemaVersion'] as num?)?.toInt() ?? AppConfig.storageSchemaVersion,
      updatedAt: updatedAt,
    );
  }

  static List<StrokeModel> _parseStrokes(dynamic raw) {
    if (raw is! List) return <StrokeModel>[];
    final out = <StrokeModel>[];
    for (final item in raw) {
      try {
        if (item is Map<String, dynamic>) {
          out.add(StrokeModel.fromMap(item));
        } else if (item is Map) {
          out.add(StrokeModel.fromMap(Map<String, dynamic>.from(item)));
        }
      } catch (_) {
        // skip corrupt stroke
      }
    }
    return out;
  }

  static List<FurnitureItem> _parseFurniture(dynamic raw) {
    if (raw is! List) return <FurnitureItem>[];
    final out = <FurnitureItem>[];
    for (final item in raw) {
      try {
        if (item is Map<String, dynamic>) {
          out.add(FurnitureItem.fromMap(item));
        } else if (item is Map) {
          out.add(FurnitureItem.fromMap(Map<String, dynamic>.from(item)));
        }
      } catch (_) {
        // skip corrupt furniture
      }
    }
    return out;
  }

  RoomModel copyWith({
    String? id,
    String? name,
    double? lengthInFeet,
    double? widthInFeet,
    List<StrokeModel>? strokes,
    List<FurnitureItem>? furniture,
    String? userId,
    int? schemaVersion,
    DateTime? updatedAt,
  }) {
    return RoomModel(
      id: id ?? this.id,
      name: name ?? this.name,
      lengthInFeet: lengthInFeet ?? this.lengthInFeet,
      widthInFeet: widthInFeet ?? this.widthInFeet,
      strokes: strokes ?? List<StrokeModel>.from(this.strokes),
      furniture: furniture ?? List<FurnitureItem>.from(this.furniture),
      userId: userId ?? this.userId,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
