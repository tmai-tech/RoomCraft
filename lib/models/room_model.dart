import 'dart:ui';

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
  /// Optional floor outline in feet (plan space). Null = rectangle width×length.
  List<Offset>? floorPolygonFt;
  /// Storey index: 0 = ground, 1 = first floor, … (Planner multi-level free path).
  int floorLevel;
  /// Patio / outdoor plan (grass stage, outdoor catalog).
  bool isExterior;
  /// Interior wall height in feet (3D extrusion).
  double wallHeightFt;
  /// Optional project notes (client, address, style goals).
  String? notes;

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
    List<Offset>? floorPolygonFt,
    this.floorLevel = 0,
    this.isExterior = false,
    this.wallHeightFt = 8.0,
    this.notes,
  })  : strokes = List<StrokeModel>.from(strokes ?? const []),
        furniture = List<FurnitureItem>.from(furniture ?? const []),
        floorPolygonFt = floorPolygonFt == null
            ? null
            : List<Offset>.from(floorPolygonFt),
        updatedAt = updatedAt ?? DateTime.now();

  bool get isPolygonFloor =>
      floorPolygonFt != null && floorPolygonFt!.length >= 3;

  /// Human label for list cards / PDF (Ground, Floor 1, Exterior…).
  String get spaceLabel {
    if (isExterior) {
      return floorLevel == 0 ? 'Exterior' : 'Exterior · L$floorLevel';
    }
    if (floorLevel <= 0) return 'Ground';
    return 'Floor $floorLevel';
  }

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
      'floorLevel': floorLevel,
      'isExterior': isExterior,
      'wallHeightFt': wallHeightFt,
      if (notes != null && notes!.trim().isNotEmpty) 'notes': notes,
      if (floorPolygonFt != null)
        'floorPolygonFt': [
          for (final p in floorPolygonFt!)
            {'x': p.dx, 'y': p.dy},
        ],
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
      floorPolygonFt: _parsePolygon(map['floorPolygonFt']),
      floorLevel: (map['floorLevel'] as num?)?.toInt() ?? 0,
      isExterior: map['isExterior'] == true,
      wallHeightFt: (map['wallHeightFt'] as num?)?.toDouble() ?? 8.0,
      notes: map['notes'] as String?,
    );
  }

  static List<Offset>? _parsePolygon(dynamic raw) {
    if (raw is! List || raw.isEmpty) return null;
    final out = <Offset>[];
    for (final item in raw) {
      if (item is Map) {
        final x = (item['x'] as num?)?.toDouble() ??
            (item['dx'] as num?)?.toDouble();
        final y = (item['y'] as num?)?.toDouble() ??
            (item['dy'] as num?)?.toDouble();
        if (x != null && y != null) out.add(Offset(x, y));
      }
    }
    return out.length >= 3 ? out : null;
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
    List<Offset>? floorPolygonFt,
    bool clearFloorPolygon = false,
    int? floorLevel,
    bool? isExterior,
    double? wallHeightFt,
    String? notes,
    bool clearNotes = false,
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
      floorPolygonFt: clearFloorPolygon
          ? null
          : (floorPolygonFt ??
              (this.floorPolygonFt == null
                  ? null
                  : List<Offset>.from(this.floorPolygonFt!))),
      floorLevel: floorLevel ?? this.floorLevel,
      isExterior: isExterior ?? this.isExterior,
      wallHeightFt: wallHeightFt ?? this.wallHeightFt,
      notes: clearNotes ? null : (notes ?? this.notes),
    );
  }

  /// Search haystack for home filter (name, notes, space, shape).
  String get searchText {
    final parts = <String>[
      name,
      spaceLabel,
      if (notes != null) notes!,
      if (isPolygonFloor) 'l-shape polygon',
      if (isExterior) 'patio outdoor exterior',
    ];
    return parts.join(' ').toLowerCase();
  }
}

