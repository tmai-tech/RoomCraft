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
import '../domain/layout/collision.dart';
import '../domain/layout/furniture_bounds.dart';
import '../domain/layout/layout_score.dart';

/// Editor tools. [pan] pans/zooms the canvas; [select] moves furniture; others draw.
enum ToolMode { pan, select, wall, door, window, erase, balcony }

class RoomState {
  final RoomModel room;
  final StrokeModel? currentStroke;
  final ToolMode currentTool;
  final double pixelsPerFoot;
  final String? selectedFurnitureId;
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

  bool get canvasPanEnabled =>
      currentTool == ToolMode.pan ||
      (currentTool == ToolMode.select &&
          !isDraggingFurniture &&
          selectedFurnitureId == null);

  RoomState copyWith({
    RoomModel? room,
    StrokeModel? currentStroke,
    ToolMode? currentTool,
    double? pixelsPerFoot,
    String? selectedFurnitureId,
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

    final snapped = _snapToGrid(position);

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
    final snapped = state.currentTool == ToolMode.balcony
        ? gridSnapped
        : _orthogonalSnap(start, gridSnapped);

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
    var newItem = FurnitureItem(
      id: _uuid.v4(),
      type: type,
      position: _snapToGrid(position),
      widthInFeet: width,
      lengthInFeet: length,
    );
    newItem = newItem.copyWith(
      position: FurnitureBounds.clampCenterInRoom(
        newItem,
        state.pixelsPerFoot,
        roomR,
      ),
    );
    newItem = Collision.resolveOverlaps(
      newItem,
      state.room.furniture,
      state.pixelsPerFoot,
      roomR,
    );
    state = state.copyWith(
      room: state.room.copyWith(
        furniture: [...state.room.furniture, newItem],
        updatedAt: DateTime.now(),
      ),
      selectedFurnitureId: newItem.id,
      currentTool: ToolMode.select,
    );
    _syncHistoryFlags();
    _refreshLayout();
  }

  void selectFurnitureAt(Offset position) {
    if (state.currentTool != ToolMode.select) return;

    for (var i = state.room.furniture.length - 1; i >= 0; i--) {
      final item = state.room.furniture[i];
      if (_hitTestFurniture(item, position)) {
        _draggingFurniture = true;
        _roomBeforeDrag = state.room.copyWith(
          strokes: List.of(state.room.strokes),
          furniture: List.of(state.room.furniture),
        );
        state = state.copyWith(
          selectedFurnitureId: item.id,
          isDraggingFurniture: true,
        );
        return;
      }
    }
    state = state.copyWith(clearSelected: true, isDraggingFurniture: false);
  }

  bool _hitTestFurniture(FurnitureItem item, Offset position) {
    // Approximate axis-aligned hit test (rotation ignored for MVP simplicity).
    final itemWidth = item.widthInFeet * state.pixelsPerFoot;
    final itemLength = item.lengthInFeet * state.pixelsPerFoot;
    final rect = Rect.fromCenter(
      center: item.position,
      width: itemWidth,
      height: itemLength,
    );
    return rect.inflate(8).contains(position);
  }

  void updateFurniturePosition(Offset delta) {
    if (state.selectedFurnitureId == null) return;

    final furniture = state.room.furniture.map((item) {
      if (item.id != state.selectedFurnitureId) return item;
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

      final furniture = state.room.furniture.map((item) {
        if (item.id != state.selectedFurnitureId) return item;
        var next = item.copyWith(position: _snapToGrid(item.position));
        next = next.copyWith(
          position: FurnitureBounds.clampCenterInRoom(
            next,
            state.pixelsPerFoot,
            roomR,
          ),
        );
        final others = state.room.furniture.where((f) => f.id != item.id).toList();
        return Collision.resolveOverlaps(
          next,
          others,
          state.pixelsPerFoot,
          roomR,
        );
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
    if (state.selectedFurnitureId == null) return;
    _pushHistory();

    final radians = degrees * pi / 180.0;
    final furniture = state.room.furniture.map((item) {
      if (item.id != state.selectedFurnitureId) return item;
      var next = item.rotationAngle + radians;
      // Normalize to 0..2π and snap to nearest step.
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
    if (state.selectedFurnitureId == null) return;
    _pushHistory();
    final furniture = state.room.furniture
        .where((i) => i.id != state.selectedFurnitureId)
        .toList();
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

  /// Auto-arrange furniture for [type]. Replaces furniture list.
  void autoArrange({RoomLayoutType? type, bool reflowExisting = false}) {
    final layoutType = type ?? state.layoutType;
    _pushHistory();
    final items = AutoArrange.arrange(
      room: state.room,
      pixelsPerFoot: state.pixelsPerFoot,
      type: layoutType,
      seedFromExisting: reflowExisting,
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

  Offset _snapToGrid(Offset pos) {
    final double snap = state.pixelsPerFoot;
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
}

final roomProvider = NotifierProvider<RoomNotifier, RoomState>(RoomNotifier.new);
