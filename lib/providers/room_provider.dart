import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../domain/units.dart';
import '../models/furniture_item.dart';
import '../models/room_model.dart';
import '../models/stroke_model.dart';
import '../domain/layout/auto_arrange.dart';
import '../domain/layout/clearances.dart';
import '../domain/layout/furniture_bounds.dart';
import '../domain/layout/layout_score.dart';
import '../domain/layout/snap.dart';

/// Editor tools. [pan] pans/zooms the canvas; [select] moves furniture; others draw.
enum ToolMode { pan, select, wall, door, window, erase, balcony }

class RoomState {
  final RoomModel room;
  final StrokeModel? currentStroke;
  final ToolMode currentTool;
  final double pixelsPerFoot;
  final String? selectedFurnitureId;
  /// Multi-select set (includes [selectedFurnitureId] when non-null).
  final Set<String> selectedFurnitureIds;
  final bool multiSelectMode;
  final bool isDraggingFurniture;
  final UnitSystem unitSystem;
  final bool canUndo;
  final bool canRedo;
  final Set<String> collisionIds;
  final int layoutScore;
  final List<LayoutTip> layoutTips;
  final RoomLayoutType layoutType;

  RoomState({
    required this.room,
    this.currentStroke,
    this.currentTool = ToolMode.select,
    this.pixelsPerFoot = AppConfig.defaultPixelsPerFoot,
    this.selectedFurnitureId,
    this.selectedFurnitureIds = const {},
    this.multiSelectMode = false,
    this.isDraggingFurniture = false,
    this.unitSystem = UnitSystem.feet,
    this.canUndo = false,
    this.canRedo = false,
    this.collisionIds = const {},
    this.layoutScore = 100,
    this.layoutTips = const [],
    this.layoutType = RoomLayoutType.bedroom,
  });

  bool get isDrawTool =>
      currentTool == ToolMode.wall ||
      currentTool == ToolMode.door ||
      currentTool == ToolMode.window ||
      currentTool == ToolMode.balcony;

  bool get hasSelection =>
      selectedFurnitureId != null || selectedFurnitureIds.isNotEmpty;

  Set<String> get effectiveSelection {
    if (selectedFurnitureIds.isNotEmpty) return selectedFurnitureIds;
    if (selectedFurnitureId != null) return {selectedFurnitureId!};
    return {};
  }

  bool get canvasPanEnabled =>
      currentTool == ToolMode.pan ||
      (currentTool == ToolMode.select &&
          !isDraggingFurniture &&
          !hasSelection);

  RoomState copyWith({
    RoomModel? room,
    StrokeModel? currentStroke,
    ToolMode? currentTool,
    double? pixelsPerFoot,
    String? selectedFurnitureId,
    Set<String>? selectedFurnitureIds,
    bool? multiSelectMode,
    bool? isDraggingFurniture,
    UnitSystem? unitSystem,
    bool? canUndo,
    bool? canRedo,
    Set<String>? collisionIds,
    int? layoutScore,
    List<LayoutTip>? layoutTips,
    RoomLayoutType? layoutType,
    bool clearStroke = false,
    bool clearSelected = false,
  }) {
    return RoomState(
      room: room ?? this.room,
      currentStroke: clearStroke ? null : (currentStroke ?? this.currentStroke),
      currentTool: currentTool ?? this.currentTool,
      pixelsPerFoot: pixelsPerFoot ?? this.pixelsPerFoot,
      selectedFurnitureId:
          clearSelected ? null : (selectedFurnitureId ?? this.selectedFurnitureId),
      selectedFurnitureIds: clearSelected
          ? const {}
          : (selectedFurnitureIds ?? this.selectedFurnitureIds),
      multiSelectMode: multiSelectMode ?? this.multiSelectMode,
      isDraggingFurniture: isDraggingFurniture ?? this.isDraggingFurniture,
      unitSystem: unitSystem ?? this.unitSystem,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      collisionIds: collisionIds ?? this.collisionIds,
      layoutScore: layoutScore ?? this.layoutScore,
      layoutTips: layoutTips ?? this.layoutTips,
      layoutType: layoutType ?? this.layoutType,
    );
  }
}

class _HistoryEntry {
  final RoomModel room;
  final String? selectedFurnitureId;

  _HistoryEntry(this.room, this.selectedFurnitureId);
}

class RoomNotifier extends Notifier<RoomState> {
  final _uuid = const Uuid();
  final List<_HistoryEntry> _undoStack = [];
  final List<_HistoryEntry> _redoStack = [];
  static const int _maxHistory = 50;

  /// Skip pushing history while mid-drag; push once on drag end.
  bool _draggingFurniture = false;
  RoomModel? _roomBeforeDrag;

  @override
  RoomState build() {
    return RoomState(
      room: RoomModel(
        id: _uuid.v4(),
        name: 'New Room',
        lengthInFeet: AppConfig.defaultRoomLengthFt,
        widthInFeet: AppConfig.defaultRoomWidthFt,
      ),
    );
  }

  void setUnitSystem(UnitSystem unit) {
    state = state.copyWith(unitSystem: unit);
  }

  void setTool(ToolMode tool) {
    state = state.copyWith(
      currentTool: tool,
      clearSelected: true,
      isDraggingFurniture: false,
      clearStroke: true,
    );
  }

  void _pushHistory() {
    _undoStack.add(_HistoryEntry(
      state.room.copyWith(
        strokes: List.of(state.room.strokes),
        furniture: List.of(state.room.furniture),
      ),
      state.selectedFurnitureId,
    ));
    if (_undoStack.length > _maxHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
    state = state.copyWith(canUndo: true, canRedo: false);
  }

  void _syncHistoryFlags() {
    state = state.copyWith(
      canUndo: _undoStack.isNotEmpty,
      canRedo: _redoStack.isNotEmpty,
    );
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_HistoryEntry(
      state.room.copyWith(
        strokes: List.of(state.room.strokes),
        furniture: List.of(state.room.furniture),
      ),
      state.selectedFurnitureId,
    ));
    final prev = _undoStack.removeLast();
    state = state.copyWith(
      room: prev.room,
      selectedFurnitureId: prev.selectedFurnitureId,
      clearSelected: prev.selectedFurnitureId == null,
      clearStroke: true,
      isDraggingFurniture: false,
      canUndo: _undoStack.isNotEmpty,
      canRedo: true,
    );
    _refreshLayout();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_HistoryEntry(
      state.room.copyWith(
        strokes: List.of(state.room.strokes),
        furniture: List.of(state.room.furniture),
      ),
      state.selectedFurnitureId,
    ));
    final next = _redoStack.removeLast();
    state = state.copyWith(
      room: next.room,
      selectedFurnitureId: next.selectedFurnitureId,
      clearSelected: next.selectedFurnitureId == null,
      clearStroke: true,
      isDraggingFurniture: false,
      canUndo: true,
      canRedo: _redoStack.isNotEmpty,
    );
    _refreshLayout();
  }

  void startStroke(Offset position) {
    if (!state.isDrawTool) return;

    StrokeType type = StrokeType.wall;
    if (state.currentTool == ToolMode.door) type = StrokeType.door;
    if (state.currentTool == ToolMode.window) type = StrokeType.window;
    if (state.currentTool == ToolMode.balcony) type = StrokeType.balcony;

    var snapped = _snapToGrid(position);
    // Openings prefer the room perimeter so left/top edges are easy to hit.
    if (type == StrokeType.door ||
        type == StrokeType.window ||
        type == StrokeType.wall) {
      snapped = _snapToRoomEdge(snapped, thresholdPx: state.pixelsPerFoot * 0.6);
    }

    state = state.copyWith(
      currentStroke: StrokeModel(
        id: _uuid.v4(),
        type: type,
        points: [snapped],
      ),
    );
  }

  void updateStroke(Offset position) {
    if (state.currentStroke == null) return;
    final start = state.currentStroke!.points.first;
    final gridSnapped = _snapToGrid(position);
    // Walls/doors/windows stay orthogonal; balcony can be free diagonal.
    var snapped = state.currentTool == ToolMode.balcony
        ? gridSnapped
        : _orthogonalSnap(start, gridSnapped);

    final t = state.currentStroke!.type;
    if (t == StrokeType.door || t == StrokeType.window) {
      // Keep both ends on the same perimeter wall once started near an edge.
      snapped = _projectOpeningOntoWall(start, snapped);
    } else if (t == StrokeType.wall) {
      snapped = _snapToRoomEdge(snapped, thresholdPx: state.pixelsPerFoot * 0.45);
    }

    final updatedPoints = List<Offset>.from(state.currentStroke!.points);
    if (updatedPoints.length == 1) {
      updatedPoints.add(snapped);
    } else {
      updatedPoints[updatedPoints.length - 1] = snapped;
    }

    state = state.copyWith(
      currentStroke: StrokeModel(
        id: state.currentStroke!.id,
        type: state.currentStroke!.type,
        points: updatedPoints,
      ),
    );
  }

  void endStroke() {
    if (state.currentStroke == null) return;
    if (state.currentStroke!.points.length < 2) {
      state = state.copyWith(clearStroke: true);
      return;
    }

    final p0 = state.currentStroke!.points.first;
    final p1 = state.currentStroke!.points.last;
    if ((p0 - p1).distance < state.pixelsPerFoot * 0.25) {
      state = state.copyWith(clearStroke: true);
      return;
    }

    _pushHistory();
    final updatedRoom = state.room.copyWith(
      strokes: [...state.room.strokes, state.currentStroke!],
      updatedAt: DateTime.now(),
    );

    state = state.copyWith(
      room: updatedRoom,
      clearStroke: true,
    );
    _syncHistoryFlags();
    _refreshLayout();
  }

  void clearRoom() {
    _pushHistory();
    state = state.copyWith(
      room: state.room.copyWith(
        strokes: [],
        furniture: [],
        updatedAt: DateTime.now(),
      ),
      clearSelected: true,
      isDraggingFurniture: false,
    );
    _syncHistoryFlags();
    _refreshLayout();
  }

  void addFurniture(
    FurnitureType type,
    Offset position,
    double width,
    double length,
  ) {
    _pushHistory();
    final roomR = FurnitureBounds.roomRect(
      state.room.widthInFeet,
      state.room.lengthInFeet,
      state.pixelsPerFoot,
    );
    // Place where user asked — soft clamp only (no auto-shove for "flexibility")
    var newItem = FurnitureItem(
      id: _uuid.v4(),
      type: type,
      position: position,
      widthInFeet: width,
      lengthInFeet: length,
    );
    newItem = newItem.copyWith(
      position: FurnitureBounds.clampCenterInRoom(
        newItem,
        state.pixelsPerFoot,
        roomR,
        margin: 1,
      ),
    );
    state = state.copyWith(
      room: state.room.copyWith(
        furniture: [...state.room.furniture, newItem],
        updatedAt: DateTime.now(),
      ),
      selectedFurnitureId: newItem.id,
      selectedFurnitureIds: {newItem.id},
      currentTool: ToolMode.select,
    );
    _syncHistoryFlags();
    _refreshLayout();
  }

  void setMultiSelectMode(bool enabled) {
    state = state.copyWith(multiSelectMode: enabled);
  }

  void selectFurnitureAt(Offset position) {
    if (state.currentTool != ToolMode.select) return;

    // Rotate handle hit on primary selection
    final primaryId = state.selectedFurnitureId;
    if (primaryId != null && !state.multiSelectMode) {
      final primary = state.room.furniture.where((f) => f.id == primaryId);
      if (primary.isNotEmpty &&
          _hitRotateHandle(primary.first, position)) {
        rotateSelectedFurniture(degrees: AppConfig.rotateSnapDegrees);
        return;
      }
    }

    for (var i = state.room.furniture.length - 1; i >= 0; i--) {
      final item = state.room.furniture[i];
      if (_hitTestFurniture(item, position)) {
        _draggingFurniture = true;
        _roomBeforeDrag = state.room.copyWith(
          strokes: List.of(state.room.strokes),
          furniture: List.of(state.room.furniture),
        );

        if (state.multiSelectMode) {
          final ids = Set<String>.from(state.selectedFurnitureIds);
          if (ids.contains(item.id)) {
            ids.remove(item.id);
          } else {
            ids.add(item.id);
          }
          state = state.copyWith(
            selectedFurnitureId: ids.isEmpty ? null : item.id,
            selectedFurnitureIds: ids,
            isDraggingFurniture: ids.isNotEmpty,
            clearSelected: ids.isEmpty,
          );
          if (ids.isEmpty) {
            _draggingFurniture = false;
            _roomBeforeDrag = null;
          }
        } else {
          state = state.copyWith(
            selectedFurnitureId: item.id,
            selectedFurnitureIds: {item.id},
            isDraggingFurniture: true,
          );
        }
        return;
      }
    }
    state = state.copyWith(clearSelected: true, isDraggingFurniture: false);
  }

  bool _hitTestFurniture(FurnitureItem item, Offset position) {
    return FurnitureBounds.containsPoint(
      item,
      position,
      state.pixelsPerFoot,
      padPx: 8,
    );
  }

  /// Rotate handle sits above the item in local space (after rotation).
  bool _hitRotateHandle(FurnitureItem item, Offset world) {
    final halfH = item.lengthInFeet * state.pixelsPerFoot / 2;
    final localY = -(halfH + 22);
    final cosA = cos(item.rotationAngle);
    final sinA = sin(item.rotationAngle);
    final hx = item.position.dx - localY * sinA;
    final hy = item.position.dy + localY * cosA;
    final d = (world - Offset(hx, hy)).distance;
    return d <= 18;
  }

  void updateFurniturePosition(Offset delta) {
    final ids = state.effectiveSelection;
    if (ids.isEmpty) return;

    final furniture = state.room.furniture.map((item) {
      if (!ids.contains(item.id)) return item;
      return item.copyWith(position: item.position + delta);
    }).toList();

    state = state.copyWith(
      room: state.room.copyWith(furniture: furniture, updatedAt: DateTime.now()),
      isDraggingFurniture: true,
    );
  }

  void endFurnitureDrag() {
    if (_draggingFurniture && _roomBeforeDrag != null) {
      _undoStack.add(_HistoryEntry(_roomBeforeDrag!, state.selectedFurnitureId));
      if (_undoStack.length > _maxHistory) {
        _undoStack.removeAt(0);
      }
      _redoStack.clear();

      final roomR = FurnitureBounds.roomRect(
        state.room.widthInFeet,
        state.room.lengthInFeet,
        state.pixelsPerFoot,
      );
      final ids = state.effectiveSelection;

      // Soft snap + stay in room. Do NOT auto-push off overlaps — user
      // can place freely; red collision tips still show via _refreshLayout.
      final furniture = state.room.furniture.map((item) {
        if (!ids.contains(item.id)) return item;
        final others =
            state.room.furniture.where((f) => f.id != item.id).toList();
        var next = item.copyWith(
          position: FurnitureSnap.snap(
            item: item,
            room: state.room,
            pixelsPerFoot: state.pixelsPerFoot,
            others: others,
            thresholdPx: 7,
          ),
        );
        next = next.copyWith(
          position: FurnitureBounds.clampCenterInRoom(
            next,
            state.pixelsPerFoot,
            roomR,
            margin: 1,
          ),
        );
        return next;
      }).toList();

      state = state.copyWith(
        room: state.room.copyWith(furniture: furniture, updatedAt: DateTime.now()),
        isDraggingFurniture: false,
        canUndo: true,
        canRedo: false,
      );
      _refreshLayout();
    } else {
      state = state.copyWith(isDraggingFurniture: false);
    }
    _draggingFurniture = false;
    _roomBeforeDrag = null;
  }

  /// Rotate selected furniture by [degrees] (default 45° snap).
  void rotateSelectedFurniture({double degrees = AppConfig.rotateSnapDegrees}) {
    final ids = state.effectiveSelection;
    if (ids.isEmpty) return;
    _pushHistory();

    final radians = degrees * pi / 180.0;
    final furniture = state.room.furniture.map((item) {
      if (!ids.contains(item.id)) return item;
      var next = item.rotationAngle + radians;
      final step = radians;
      next = (next / step).round() * step;
      return item.copyWith(rotationAngle: next);
    }).toList();

    state = state.copyWith(
      room: state.room.copyWith(furniture: furniture, updatedAt: DateTime.now()),
    );
    _syncHistoryFlags();
    _refreshLayout();
  }

  void resizeSelectedFurniture(double widthFt, double lengthFt) {
    if (state.selectedFurnitureId == null) return;
    _pushHistory();
    final furniture = state.room.furniture.map((item) {
      if (item.id != state.selectedFurnitureId) return item;
      return item.copyWith(
        widthInFeet: widthFt,
        lengthInFeet: lengthFt,
      );
    }).toList();
    state = state.copyWith(
      room: state.room.copyWith(furniture: furniture, updatedAt: DateTime.now()),
    );
    _syncHistoryFlags();
    _refreshLayout();
  }

  void deleteSelectedFurniture() {
    final ids = state.effectiveSelection;
    if (ids.isEmpty) return;
    _pushHistory();
    final furniture =
        state.room.furniture.where((i) => !ids.contains(i.id)).toList();
    state = state.copyWith(
      room: state.room.copyWith(furniture: furniture, updatedAt: DateTime.now()),
      clearSelected: true,
      isDraggingFurniture: false,
    );
    _syncHistoryFlags();
    _refreshLayout();
  }

  void initFromScan(
    double width,
    double length,
    List<StrokeModel> strokes,
    List<FurnitureItem> furniture,
  ) {
    _undoStack.clear();
    _redoStack.clear();
    state = state.copyWith(
      room: RoomModel(
        id: _uuid.v4(),
        name:
            'AI Scan ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
        widthInFeet: width,
        lengthInFeet: length,
        strokes: strokes,
        furniture: furniture,
      ),
      clearSelected: true,
      isDraggingFurniture: false,
      canUndo: false,
      canRedo: false,
    );
    _refreshLayout();
  }

  void loadRoom(RoomModel room) {
    _undoStack.clear();
    _redoStack.clear();
    state = state.copyWith(
      room: room,
      clearSelected: true,
      pixelsPerFoot: AppConfig.defaultPixelsPerFoot,
      isDraggingFurniture: false,
      canUndo: false,
      canRedo: false,
    );
    _refreshLayout();
  }

  void updateName(String name) {
    _pushHistory();
    state = state.copyWith(
      room: state.room.copyWith(name: name, updatedAt: DateTime.now()),
    );
    _syncHistoryFlags();
  }

  void updateRoomSize(double width, double length) {
    _pushHistory();
    state = state.copyWith(
      room: state.room.copyWith(
        widthInFeet: width,
        lengthInFeet: length,
        updatedAt: DateTime.now(),
      ),
    );
    _syncHistoryFlags();
  }


  void setLayoutType(RoomLayoutType type) {
    state = state.copyWith(layoutType: type);
  }

  void _refreshLayout() {
    final score = LayoutScore.evaluate(state.room, state.pixelsPerFoot);
    state = state.copyWith(
      collisionIds: score.collisionIds,
      layoutScore: score.score,
      layoutTips: score.tips,
    );
  }

  /// Auto-arrange furniture.
  ///
  /// Default / [reflowExisting]: keep scanned pieces, suggest a more spacious
  /// layout. Preset [type] only used when the room is empty.
  void autoArrange({RoomLayoutType? type, bool reflowExisting = false}) {
    final layoutType = type ?? state.layoutType;
    _pushHistory();
    // Prefer spacious reflow of what is already on the plan.
    final seed = reflowExisting || state.room.furniture.isNotEmpty;
    final items = AutoArrange.arrange(
      room: state.room,
      pixelsPerFoot: state.pixelsPerFoot,
      type: layoutType,
      seedFromExisting: seed,
    );
    state = state.copyWith(
      room: state.room.copyWith(furniture: items, updatedAt: DateTime.now()),
      layoutType: layoutType,
      clearSelected: true,
      isDraggingFurniture: false,
      currentTool: ToolMode.select,
    );
    _syncHistoryFlags();
    _refreshLayout();
  }

  /// Explicit spacious reflow of current furniture only (no presets).
  void suggestSpaciousLayout() {
    if (state.room.furniture.isEmpty) return;
    _pushHistory();
    final items = AutoArrange.arrangeSpacious(
      room: state.room,
      pixelsPerFoot: state.pixelsPerFoot,
    );
    state = state.copyWith(
      room: state.room.copyWith(furniture: items, updatedAt: DateTime.now()),
      clearSelected: true,
      isDraggingFurniture: false,
      currentTool: ToolMode.select,
    );
    _syncHistoryFlags();
    _refreshLayout();
  }

  /// Apply a precomputed alternative layout (A/B/C) with undo support.
  void applyLayoutAlternative(List<FurnitureItem> furniture) {
    if (furniture.isEmpty) return;
    _pushHistory();
    state = state.copyWith(
      room: state.room.copyWith(furniture: furniture, updatedAt: DateTime.now()),
      clearSelected: true,
      isDraggingFurniture: false,
      currentTool: ToolMode.select,
    );
    _syncHistoryFlags();
    _refreshLayout();
  }

  /// Replace plan furniture with a room-type preset (bedroom / living / office).
  void applyPresetLayout(RoomLayoutType type) {
    _pushHistory();
    final emptyRoom = state.room.copyWith(furniture: []);
    final items = AutoArrange.arrange(
      room: emptyRoom,
      pixelsPerFoot: state.pixelsPerFoot,
      type: type,
      seedFromExisting: false,
    );
    state = state.copyWith(
      room: state.room.copyWith(furniture: items, updatedAt: DateTime.now()),
      layoutType: type,
      clearSelected: true,
      isDraggingFurniture: false,
      currentTool: ToolMode.select,
    );
    _syncHistoryFlags();
    _refreshLayout();
  }

  Offset _snapToGrid(Offset pos) {
    // ¼ ft grid — freer than full-foot snaps for manual placement
    final double snap = state.pixelsPerFoot * 0.25;
    return Offset(
      (pos.dx / snap).roundToDouble() * snap,
      (pos.dy / snap).roundToDouble() * snap,
    );
  }

  /// Force horizontal or vertical walls (orthogonal drawing).
  Offset _orthogonalSnap(Offset start, Offset end) {
    final dx = (end.dx - start.dx).abs();
    final dy = (end.dy - start.dy).abs();
    if (dx >= dy) {
      return Offset(end.dx, start.dy);
    }
    return Offset(start.dx, end.dy);
  }

  Rect get _roomPx => FurnitureBounds.roomRect(
        state.room.widthInFeet,
        state.room.lengthInFeet,
        state.pixelsPerFoot,
      );

  /// Snap [pos] onto the nearest room perimeter when close enough.
  /// Makes left/top edges drawable instead of fighting free space outside.
  Offset _snapToRoomEdge(Offset pos, {required double thresholdPx}) {
    final r = _roomPx;
    final dL = (pos.dx - r.left).abs();
    final dR = (pos.dx - r.right).abs();
    final dT = (pos.dy - r.top).abs();
    final dB = (pos.dy - r.bottom).abs();
    final minD = [dL, dR, dT, dB].reduce((a, b) => a < b ? a : b);
    if (minD > thresholdPx) return pos;

    if (minD == dL) {
      return Offset(r.left, pos.dy.clamp(r.top, r.bottom));
    }
    if (minD == dR) {
      return Offset(r.right, pos.dy.clamp(r.top, r.bottom));
    }
    if (minD == dT) {
      return Offset(pos.dx.clamp(r.left, r.right), r.top);
    }
    return Offset(pos.dx.clamp(r.left, r.right), r.bottom);
  }

  /// Keep door/window strokes coplanar with the wall they started on.
  Offset _projectOpeningOntoWall(Offset start, Offset end) {
    final r = _roomPx;
    final thr = state.pixelsPerFoot * 0.75;
    final onLeft = (start.dx - r.left).abs() <= thr;
    final onRight = (start.dx - r.right).abs() <= thr;
    final onTop = (start.dy - r.top).abs() <= thr;
    final onBottom = (start.dy - r.bottom).abs() <= thr;

    if (onLeft) {
      return Offset(r.left, end.dy.clamp(r.top, r.bottom));
    }
    if (onRight) {
      return Offset(r.right, end.dy.clamp(r.top, r.bottom));
    }
    if (onTop) {
      return Offset(end.dx.clamp(r.left, r.right), r.top);
    }
    if (onBottom) {
      return Offset(end.dx.clamp(r.left, r.right), r.bottom);
    }
    // Not near a wall yet — still magnet the end so openings don't float inside.
    return _snapToRoomEdge(end, thresholdPx: thr);
  }
}

final roomProvider = NotifierProvider<RoomNotifier, RoomState>(RoomNotifier.new);
