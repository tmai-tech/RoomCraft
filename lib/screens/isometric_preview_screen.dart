import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/units.dart';
import '../models/room_model.dart';
import '../painters/isometric_painter.dart';

/// Full-screen isometric 3D preview (free CustomPainter, no 3D engine).
class IsometricPreviewScreen extends StatefulWidget {
  final RoomModel room;
  final double pixelsPerFoot;
  final UnitSystem unitSystem;

  const IsometricPreviewScreen({
    super.key,
    required this.room,
    required this.pixelsPerFoot,
    this.unitSystem = UnitSystem.feet,
  });

  @override
  State<IsometricPreviewScreen> createState() => _IsometricPreviewScreenState();
}

class _IsometricPreviewScreenState extends State<IsometricPreviewScreen> {
  double _yaw = 0;
  double _pitch = 0.35; // scales wall extrusion height

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('3D preview'),
        actions: [
          IconButton(
            tooltip: 'Reset view',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {
              _yaw = 0;
              _pitch = 0.3;
            }),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              'Drag horizontally to orbit · same plan as 2D editor',
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onHorizontalDragUpdate: (d) {
                setState(() {
                  _yaw += d.delta.dx * 0.01;
                  // Keep in range
                  if (_yaw > math.pi * 2) _yaw -= math.pi * 2;
                  if (_yaw < -math.pi * 2) _yaw += math.pi * 2;
                });
              },
              child: CustomPaint(
                painter: IsometricPainter(
                  room: widget.room,
                  pixelsPerFoot: widget.pixelsPerFoot,
                  unitSystem: widget.unitSystem,
                  yaw: _yaw,
                  wallHeightFt: 7.0 + _pitch * 3,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.threed_rotation, size: 18),
                  Expanded(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Text('Orbit', style: TextStyle(fontSize: 11)),
                            Expanded(
                              child: Slider(
                                value: _yaw,
                                min: -math.pi,
                                max: math.pi,
                                onChanged: (v) => setState(() => _yaw = v),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            const Text('Height', style: TextStyle(fontSize: 11)),
                            Expanded(
                              child: Slider(
                                value: _pitch,
                                min: 0,
                                max: 1,
                                onChanged: (v) => setState(() => _pitch = v),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back to 2D'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
