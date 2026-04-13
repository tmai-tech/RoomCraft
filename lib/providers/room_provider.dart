import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/room_model.dart';
import '../models/stroke_model.dart';
import '../models/furniture_item.dart';

enum ToolMode { select, wall, door, window, erase, balcony }

class RoomState {
  final RoomModel room;
  final StrokeModel? currentStroke;
  final ToolMode currentTool;
  final double pixelsPerFoot;
  final String? selectedFurnitureId;

  RoomState({
    required this.room,
    this.currentStroke,
    this.currentTool = ToolMode.select,
    this.pixelsPerFoot = 20.0,
    this.selectedFurnitureId,
  });

  RoomState copyWith({
    RoomModel? room,
    StrokeModel? currentStroke,
    ToolMode? currentTool,
    double? pixelsPerFoot,
    String? selectedFurnitureId,
    bool clearStroke = false,
    bool clearSelected = false,
  }) {
    return RoomState(
      room: room ?? this.room,
      currentStroke: clearStroke ? null : (currentStroke ?? this.currentStroke),
      currentTool: currentTool ?? this.currentTool,
      pixelsPerFoot: pixelsPerFoot ?? this.pixelsPerFoot,
      selectedFurnitureId: clearSelected ? null : (selectedFurnitureId ?? this.selectedFurnitureId),
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
        lengthInFeet: 20.0,
        widthInFeet: 20.0,
      ),
    );
  }

  void setTool(ToolMode tool) {
    state = state.copyWith(currentTool: tool, clearSelected: true);
  }

  void startStroke(Offset position) {
    if (state.currentTool == ToolMode.select || state.currentTool == ToolMode.erase) return;

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

    final updatedRoom = RoomModel.fromMap(state.room.toMap());
    updatedRoom.strokes.add(state.currentStroke!);

    state = state.copyWith(
      room: updatedRoom,
      clearStroke: true,
    );
  }

  void undo() {
    if (state.room.strokes.isEmpty && state.room.furniture.isEmpty) return;
    
    final updatedRoom = RoomModel.fromMap(state.room.toMap());
    
    if (updatedRoom.strokes.isNotEmpty) {
      updatedRoom.strokes.removeLast();
    } else if (updatedRoom.furniture.isNotEmpty) {
      updatedRoom.furniture.removeLast();
    }

    state = state.copyWith(room: updatedRoom);
  }

  void clearRoom() {
    final updatedRoom = RoomModel.fromMap(state.room.toMap());
    updatedRoom.strokes.clear();
    updatedRoom.furniture.clear();
    state = state.copyWith(room: updatedRoom, clearSelected: true);
  }

  void addFurniture(FurnitureType type, Offset position, double width, double length) {
    final updatedRoom = RoomModel.fromMap(state.room.toMap());
    final newItem = FurnitureItem(
      id: _uuid.v4(),
      type: type,
      position: position,
      widthInFeet: width,
      lengthInFeet: length,
    );
    updatedRoom.furniture.add(newItem);
    state = state.copyWith(room: updatedRoom, selectedFurnitureId: newItem.id, currentTool: ToolMode.select);
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

      // Simple click bounds handling. Doesn't rotate the rect for the hit test yet.
      if (rect.contains(position)) {
        state = state.copyWith(selectedFurnitureId: item.id);
        return;
      }
    }
    state = state.copyWith(clearSelected: true);
  }

  void updateFurniturePosition(Offset delta) {
    if (state.selectedFurnitureId == null) return;
    
    final updatedRoom = RoomModel.fromMap(state.room.toMap());
    final itemIndex = updatedRoom.furniture.indexWhere((i) => i.id == state.selectedFurnitureId);
    
    if (itemIndex != -1) {
      updatedRoom.furniture[itemIndex].position += delta;
      state = state.copyWith(room: updatedRoom);
    }
  }

  void rotateSelectedFurniture() {
    if (state.selectedFurnitureId == null) return;

    final updatedRoom = RoomModel.fromMap(state.room.toMap());
    final itemIndex = updatedRoom.furniture.indexWhere((i) => i.id == state.selectedFurnitureId);
    
    if (itemIndex != -1) {
        updatedRoom.furniture[itemIndex].rotationAngle += pi / 2;
        state = state.copyWith(room: updatedRoom);
    }
  }
  
  void deleteSelectedFurniture() {
    if (state.selectedFurnitureId == null) return;
    final updatedRoom = RoomModel.fromMap(state.room.toMap());
    updatedRoom.furniture.removeWhere((i) => i.id == state.selectedFurnitureId);
    state = state.copyWith(room: updatedRoom, clearSelected: true);
  }

  void initFromScan(double width, double length, List<StrokeModel> strokes, List<FurnitureItem> furniture) {
    state = state.copyWith(
      room: RoomModel(
        id: _uuid.v4(),
        name: 'AI Scan ${DateTime.now().hour}:${DateTime.now().minute}',
        widthInFeet: width,
        lengthInFeet: length,
        strokes: strokes,
        furniture: furniture,
      ),
      clearSelected: true,
    );
  }

  void loadRoom(RoomModel room) {
    state = state.copyWith(
      room: room,
      clearSelected: true,
      pixelsPerFoot: 20.0, // Reset to default zoom
    );
  }

  void updateName(String name) {
    final updatedRoom = RoomModel.fromMap(state.room.toMap());
    updatedRoom.name = name;
    state = state.copyWith(room: updatedRoom);
  }

  void updateRoomSize(double width, double length) {
    final updatedRoom = RoomModel.fromMap(state.room.toMap());
    updatedRoom.widthInFeet = width;
    updatedRoom.lengthInFeet = length;
    state = state.copyWith(room: updatedRoom);
  }

  Offset _snapToGrid(Offset pos) {
    final double snap = state.pixelsPerFoot;
    return Offset(
      (pos.dx / snap).roundToDouble() * snap,
      (pos.dy / snap).roundToDouble() * snap,
    );
  }
}

final roomProvider = NotifierProvider<RoomNotifier, RoomState>(() {
  return RoomNotifier();
});
