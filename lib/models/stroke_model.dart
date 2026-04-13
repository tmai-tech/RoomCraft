import 'package:flutter/material.dart';

enum StrokeType { wall, door, window, balcony }

class StrokeModel {
  final String id;
  final StrokeType type;
  final List<Offset> points;

  StrokeModel({
    required this.id,
    required this.type,
    required this.points,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type.name,
      'points': points.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
    };
  }

  factory StrokeModel.fromMap(Map<String, dynamic> map) {
    return StrokeModel(
      id: map['id'],
      type: StrokeType.values.firstWhere((e) => e.name == map['type']),
      points: (map['points'] as List).map((p) => Offset(p['dx'], p['dy'])).toList(),
    );
  }
}
