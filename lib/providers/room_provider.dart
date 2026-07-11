import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../models/furniture_item.dart';
import '../models/room_model.dart';
import '../models/stroke_model.dart';

/// Editor tools. [pan] pans/zooms the canvas; [select] moves furniture; others draw.
enum ToolMode { pan, select, wall, door, window, erase, balcony }

class RoomState {
  final RoomModel room;
  final StrokeModel? currentStroke;
  final ToolMode currentTool;
  final double pixelsPerFoot;
  final String? selectedFurnitureId;
  /// True while user is dragging selected furniture (disables pan).
  final bool isDraggingFurniture;

  RoomState({
    required this.room,
    this.currentStroke,
    this.currentTool = ToolMode.select,
    this.pixelsPerFoot = AppConfig.defaultPixelsPerFoot,
    this.selectedFurnitureId,
    this.isDraggingFurniture = false,
  });

  bool get isDrawTool =>
      currentTool == ToolMode.wall ||
      currentTool == ToolMode.door ||
      currentTool == ToolMode.window ||
      currentTool == ToolMode.balcony;

  /// Whether InteractiveViewer should pan with one finger.
  bool get canvasPanEnabled =>
      currentTool == ToolMode.pan ||
      (currentTool == ToolMode.select && !isDraggingFurniture && selectedFurnitureId == null);

  RoomState copyWith({
    RoomModel? room,
    StrokeModel? currentStroke,
    ToolMode? currentTool,
    double? pixelsPerFoot,
    String? selectedFurnitureId,
    bool? isDraggingFurniture,
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
    );
  }
}

class RoomNotifier extends Notifier<RoomState> {
  final _uuid = const Uuid();

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

  void setTool(ToolMode tool) {
    state = state.copyWith(
      currentTool: tool,
      clearSelected: true,
      isDraggingFurniture: false,
      clearStroke: true,
    );
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
    final snapped = _snapToGrid(position);

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

    final updatedRoom = state.room.copyWith(
      strokes: [...state.room.strokes, state.currentStroke!],
      updatedAt: DateTime.now(),
    );

    state = state.copyWith(
      room: updatedRoom,
      clearStroke: true,
    );
  }

  void undo() {
    if (state.room.strokes.isEmpty && state.room.furniture.isEmpty) return;

    if (state.room.strokes.isNotEmpty) {
      final strokes = List<StrokeModel>.from(state.room.strokes)..removeLast();
      state = state.copyWith(
        room: state.room.copyWith(strokes: strokes, updatedAt: DateTime.now()),
      );
    } else if (state.room.furniture.isNotEmpty) {
      final furniture = List<FurnitureItem>.from(state.room.furniture)..removeLast();
      state = state.copyWith(
        room: state.room.copyWith(furniture: furniture, updatedAt: DateTime.now()),
        clearSelected: true,
      );
    }
  }

  void clearRoom() {
    state = state.copyWith(
      room: state.room.copyWith(
        strokes: [],
        furniture: [],
        updatedAt: DateTime.now(),
      ),
      clearSelected: true,
      isDraggingFurniture: false,
    );
  }

  void addFurniture(FurnitureType type, Offset position, double width, double length) {
    final newItem = FurnitureItem(
      id: _uuid.v4(),
      type: type,
      position: position,
      widthInFeet: width,
      lengthInFeet: length,
    );
    state = state.copyWith(
      room: state.room.copyWith(
        furniture: [...state.room.furniture, newItem],
        updatedAt: DateTime.now(),
      ),
      selectedFurnitureId: newItem.id,
      currentTool: ToolMode.select,
    );
  }

  void selectFurnitureAt(Offset position) {
    if (state.currentTool != ToolMode.select) return;

    for (var i = state.room.furniture.length - 1; i >= 0; i--) {
      final item = state.room.furniture[i];
      final itemWidth = item.widthInFeet * state.pixelsPerFoot;
      final itemLength = item.lengthInFeet * state.pixelsPerFoot;

      final rect = Rect.fromCenter(
        center: item.position,
        width: itemWidth,
        height: itemLength,
      );

      if (rect.contains(position)) {
        state = state.copyWith(
          selectedFurnitureId: item.id,
          isDraggingFurniture: true,
        );
        return;
      }
    }
    state = state.copyWith(clearSelected: true, isDraggingFurniture: false);
  }

  void updateFurniturePosition(Offset delta) {
    if (state.selectedFurnitureId == null) return;

    final furniture = state.room.furniture.map((item) {
      if (item.id != state.selectedFurnitureId) return item;
      return FurnitureItem(
        id: item.id,
        type: item.type,
        position: item.position + delta,
        rotationAngle: item.rotationAngle,
        widthInFeet: item.widthInFeet,
        lengthInFeet: item.lengthInFeet,
      );
    }).toList();

    state = state.copyWith(
      room: state.room.copyWith(furniture: furniture, updatedAt: DateTime.now()),
      isDraggingFurniture: true,
    );
  }

  void endFurnitureDrag() {
    state = state.copyWith(isDraggingFurniture: false);
  }

  void rotateSelectedFurniture() {
    if (state.selectedFurnitureId == null) return;

    final furniture = state.room.furniture.map((item) {
      if (item.id != state.selectedFurnitureId) return item;
      return FurnitureItem(
        id: item.id,
        type: item.type,
        position: item.position,
        rotationAngle: item.rotationAngle + pi / 2,
        widthInFeet: item.widthInFeet,
        lengthInFeet: item.lengthInFeet,
      );
    }).toList();

    state = state.copyWith(
      room: state.room.copyWith(furniture: furniture, updatedAt: DateTime.now()),
    );
  }

  void deleteSelectedFurniture() {
    if (state.selectedFurnitureId == null) return;
    final furniture = state.room.furniture
        .where((i) => i.id != state.selectedFurnitureId)
        .toList();
    state = state.copyWith(
      room: state.room.copyWith(furniture: furniture, updatedAt: DateTime.now()),
      clearSelected: true,
      isDraggingFurniture: false,
    );
  }

  void initFromScan(
    double width,
    double length,
    List<StrokeModel> strokes,
    List<FurnitureItem> furniture,
  ) {
    state = state.copyWith(
      room: RoomModel(
        id: _uuid.v4(),
        name: 'AI Scan ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
        widthInFeet: width,
        lengthInFeet: length,
        strokes: strokes,
        furniture: furniture,
      ),
      clearSelected: true,
      isDraggingFurniture: false,
    );
  }

  void loadRoom(RoomModel room) {
    state = state.copyWith(
      room: room,
      clearSelected: true,
      pixelsPerFoot: AppConfig.defaultPixelsPerFoot,
      isDraggingFurniture: false,
    );
  }

  void updateName(String name) {
    state = state.copyWith(
      room: state.room.copyWith(name: name, updatedAt: DateTime.now()),
    );
  }

  void updateRoomSize(double width, double length) {
    state = state.copyWith(
      room: state.room.copyWith(
        widthInFeet: width,
        lengthInFeet: length,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Offset _snapToGrid(Offset pos) {
    final double snap = state.pixelsPerFoot;
    return Offset(
      (pos.dx / snap).roundToDouble() * snap,
      (pos.dy / snap).roundToDouble() * snap,
    );
  }
}

final roomProvider = NotifierProvider<RoomNotifier, RoomState>(RoomNotifier.new);
