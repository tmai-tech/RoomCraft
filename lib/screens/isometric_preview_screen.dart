import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/layout/isometric.dart';
import '../domain/units.dart';
import '../models/furniture_item.dart';
import '../models/room_model.dart';
import '../painters/isometric_painter.dart';
import '../services/export_service.dart';

/// Interactive isometric 3D view — select, rotate, delete furniture.
///
/// Not a mesh CAD engine (Planner 5D paid HD) but real **edit-in-3D** path
/// on free CustomPainter + projection hit-test.
class IsometricPreviewScreen extends StatefulWidget {
  final RoomModel room;
  final double pixelsPerFoot;
  final UnitSystem unitSystem;
  /// When set, edits are written back on pop via this callback.
  final ValueChanged<List<FurnitureItem>>? onFurnitureChanged;

  const IsometricPreviewScreen({
    super.key,
    required this.room,
    required this.pixelsPerFoot,
    this.unitSystem = UnitSystem.feet,
    this.onFurnitureChanged,
  });

  @override
  State<IsometricPreviewScreen> createState() => _IsometricPreviewScreenState();
}

class _IsometricPreviewScreenState extends State<IsometricPreviewScreen> {
  late List<FurnitureItem> _furniture;
  double _yaw = 0;
  double _pitch = 0.35;
  bool _perspective = true;
  double _walkX = 0;
  double _walkY = 0;
  String? _selectedId;
  bool _dirty = false;
  SceneLighting _lighting = SceneLighting.day;

  @override
  void initState() {
    super.initState();
    _furniture = List<FurnitureItem>.from(widget.room.furniture);
  }

  RoomModel get _viewRoom => widget.room.copyWith(furniture: _furniture);

  double get _wallH => 7.0 + _pitch * 3;

  void _commit() {
    widget.onFurnitureChanged?.call(List<FurnitureItem>.from(_furniture));
  }

  void _pop() {
    if (_dirty) _commit();
    Navigator.pop(context, _dirty ? _furniture : null);
  }

  FurnitureItem? get _selected {
    if (_selectedId == null) return null;
    try {
      return _furniture.firstWhere((f) => f.id == _selectedId);
    } catch (_) {
      return null;
    }
  }

  void _rotateSelected({double degrees = 45}) {
    final sel = _selected;
    if (sel == null) return;
    setState(() {
      _furniture = [
        for (final f in _furniture)
          if (f.id == sel.id)
            f.copyWith(rotationAngle: f.rotationAngle + degrees * math.pi / 180)
          else
            f,
      ];
      _dirty = true;
    });
  }

  void _deleteSelected() {
    final sel = _selected;
    if (sel == null) return;
    setState(() {
      _furniture = _furniture.where((f) => f.id != sel.id).toList();
      _selectedId = null;
      _dirty = true;
    });
  }

  void _nudgeSelected(Offset deltaPx) {
    final sel = _selected;
    if (sel == null) return;
    setState(() {
      _furniture = [
        for (final f in _furniture)
          if (f.id == sel.id)
            f.copyWith(position: f.position + deltaPx)
          else
            f,
      ];
      _dirty = true;
    });
  }

  /// Hit-test furniture by nearest projected center (screen space).
  void _selectAt(Offset local, Size size) {
    final room = _viewRoom;
    final w = room.widthInFeet * widget.pixelsPerFoot;
    final d = room.lengthInFeet * widget.pixelsPerFoot;
    final sample = <Offset>[];
    for (final c in [const Offset(0, 0), Offset(w, 0), Offset(w, d), Offset(0, d)]) {
      sample.add(_project(c.dx, c.dy, 0, w, d));
      sample.add(_project(c.dx, c.dy, _wallH * widget.pixelsPerFoot * 0.55, w, d));
    }
    final bounds = Iso.boundsOf(sample);
    if (bounds.width <= 0 || bounds.height <= 0) return;
    const pad = 28.0;
    final s = math.min(
      (size.width - pad * 2) / bounds.width,
      (size.height - pad * 2) / bounds.height,
    );
    Offset map(Offset p) => Offset(
          size.width / 2 + (p.dx - bounds.center.dx) * s,
          size.height / 2 + (p.dy - bounds.center.dy) * s,
        );

    String? bestId;
    var bestDist = 48.0; // px threshold
    for (final f in _furniture) {
      final h = f.type.defaultHeightFt * widget.pixelsPerFoot * 0.55;
      final p = map(_project(f.position.dx, f.position.dy, h * 0.5, w, d));
      final dist = (p - local).distance;
      if (dist < bestDist) {
        bestDist = dist;
        bestId = f.id;
      }
    }
    setState(() => _selectedId = bestId);
  }

  Offset _project(double x, double y, double z, double roomW, double roomD) {
    final cx = roomW / 2;
    final cy = roomD / 2;
    final dx = x - cx;
    final dy = y - cy;
    final cos = math.cos(_yaw);
    final sin = math.sin(_yaw);
    final rx = dx * cos - dy * sin + cx;
    final ry = dx * sin + dy * cos + cy;
    return Iso.project(rx, ry, z);
  }

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_dirty ? '3D editor · edited' : '3D room editor'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _pop,
          ),
          actions: [
            IconButton(
              key: const Key('iso_lighting_btn'),
              tooltip: 'Lighting: ${_lighting.name}',
              icon: Icon(switch (_lighting) {
                SceneLighting.day => Icons.wb_sunny_outlined,
                SceneLighting.evening => Icons.wb_twilight,
                SceneLighting.night => Icons.nights_stay_outlined,
              }),
              onPressed: () => setState(() {
                _lighting = switch (_lighting) {
                  SceneLighting.day => SceneLighting.evening,
                  SceneLighting.evening => SceneLighting.night,
                  SceneLighting.night => SceneLighting.day,
                };
              }),
            ),
            IconButton(
              key: const Key('iso_hd_snapshot'),
              tooltip: 'Share HD 3D snapshot',
              icon: const Icon(Icons.photo_camera_outlined),
              onPressed: () async {
                try {
                  await ExportService.share3dPng(
                    _viewRoom,
                    pixelsPerFoot: widget.pixelsPerFoot,
                    unitSystem: widget.unitSystem,
                    lighting: _lighting,
                  );
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('3D snapshot failed: $e')),
                    );
                  }
                }
              },
            ),
            IconButton(
              tooltip: 'Reset view',
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() {
                _yaw = 0;
                _pitch = 0.35;
                _walkX = 0;
                _walkY = 0;
                _lighting = SceneLighting.day;
              }),
            ),
            if (_dirty)
              TextButton(
                key: const Key('iso_apply_btn'),
                onPressed: () {
                  _commit();
                  setState(() => _dirty = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('3D edits applied to plan')),
                  );
                },
                child: const Text('Apply'),
              ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                'Select a piece · drag to orbit · rotate / delete / nudge · Apply',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ),
            if (_furniture.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                child: DropdownButtonFormField<String>(
                  key: const Key('iso_furniture_picker'),
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Select furniture',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  value: _selectedId != null &&
                          _furniture.any((f) => f.id == _selectedId)
                      ? _selectedId
                      : null,
                  items: [
                    for (final f in _furniture)
                      DropdownMenuItem(
                        value: f.id,
                        child: Text(
                          '${f.type.shortLabel}'
                          '${f.catalogId != null ? ' · ${f.catalogId}' : ''} '
                          '(${f.widthInFeet.toStringAsFixed(1)}×${f.lengthInFeet.toStringAsFixed(1)})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (id) => setState(() => _selectedId = id),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  FilterChip(
                    key: const Key('iso_perspective_chip'),
                    label: Text(_perspective ? 'Perspective 3D' : 'Isometric'),
                    selected: _perspective,
                    onSelected: (v) => setState(() => _perspective = v),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  return GestureDetector(
                    onTapUp: (d) => _selectAt(d.localPosition, size),
                    onHorizontalDragUpdate: (d) {
                      setState(() {
                        _yaw += d.delta.dx * 0.01;
                      });
                    },
                    child: CustomPaint(
                      painter: IsometricPainter(
                        room: _viewRoom,
                        pixelsPerFoot: widget.pixelsPerFoot,
                        unitSystem: widget.unitSystem,
                        yaw: _yaw,
                        wallHeightFt: _wallH,
                        selectedId: _selectedId,
                        perspective: _perspective,
                        walkX: _walkX,
                        walkY: _walkY,
                        lighting: _lighting,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  );
                },
              ),
            ),
            if (sel != null)
              Material(
                elevation: 2,
                color: Colors.amber.shade50,
                child: ListTile(
                  leading: Icon(Icons.view_in_ar, color: Colors.amber.shade900),
                  title: Text(
                    '${sel.type.shortLabel}'
                    '${sel.catalogId != null ? ' · ${sel.catalogId}' : ''}',
                  ),
                  subtitle: Text(
                    '${sel.widthInFeet.toStringAsFixed(1)}×${sel.lengthInFeet.toStringAsFixed(1)} ft',
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        key: const Key('iso_rotate_btn'),
                        tooltip: 'Rotate 45°',
                        icon: const Icon(Icons.rotate_right),
                        onPressed: () => _rotateSelected(degrees: 45),
                      ),
                      IconButton(
                        key: const Key('iso_delete_btn'),
                        tooltip: 'Delete',
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: _deleteSelected,
                      ),
                    ],
                  ),
                ),
              ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const SizedBox(
                          width: 52,
                          child: Text('Orbit', style: TextStyle(fontSize: 11)),
                        ),
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
                        const SizedBox(
                          width: 52,
                          child: Text('Height', style: TextStyle(fontSize: 11)),
                        ),
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
                    // Walkthrough explore (first-person camera in room)
                    if (_perspective)
                      Row(
                        key: const Key('iso_walk_pad'),
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Walk', style: TextStyle(fontSize: 11)),
                          IconButton(
                            key: const Key('iso_walk_left'),
                            onPressed: () => setState(() => _walkX -= 12),
                            icon: const Icon(Icons.arrow_back),
                          ),
                          IconButton(
                            key: const Key('iso_walk_fwd'),
                            onPressed: () => setState(() => _walkY -= 12),
                            icon: const Icon(Icons.arrow_upward),
                          ),
                          IconButton(
                            key: const Key('iso_walk_back'),
                            onPressed: () => setState(() => _walkY += 12),
                            icon: const Icon(Icons.arrow_downward),
                          ),
                          IconButton(
                            key: const Key('iso_walk_right'),
                            onPressed: () => setState(() => _walkX += 12),
                            icon: const Icon(Icons.arrow_forward),
                          ),
                        ],
                      ),
                    if (sel != null)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: () => _nudgeSelected(const Offset(-10, 0)),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          IconButton(
                            onPressed: () => _nudgeSelected(const Offset(0, -10)),
                            icon: const Icon(Icons.expand_less),
                          ),
                          IconButton(
                            onPressed: () => _nudgeSelected(const Offset(0, 10)),
                            icon: const Icon(Icons.expand_more),
                          ),
                          IconButton(
                            onPressed: () => _nudgeSelected(const Offset(10, 0)),
                            icon: const Icon(Icons.chevron_right),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Nudge selected',
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
