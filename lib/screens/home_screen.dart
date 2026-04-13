import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'blueprint_screen.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';
import '../services/storage_service.dart';
import '../models/room_model.dart';
import '../providers/room_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final StorageService _storageService = StorageService();
  List<RoomModel> _rooms = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    final rooms = await _storageService.loadRooms();
    if (mounted) {
      setState(() {
        _rooms = rooms;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteRoom(String id) async {
    await _storageService.deleteRoom(id);
    _loadRooms();
  }

  void _createNewManual() {
    ref.invalidate(roomProvider); // Reset to new room
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BlueprintScreen()),
    ).then((_) => _loadRooms());
  }

  void _createNewAI() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    ).then((_) => _loadRooms());
  }

  void _editRoom(RoomModel room) {
    ref.read(roomProvider.notifier).loadRoom(room);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BlueprintScreen()),
    ).then((_) => _loadRooms());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RoomCraft Pro'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rooms.isEmpty
              ? _buildEmptyState()
              : _buildRoomList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateOptions,
        label: const Text('New Blueprint'),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.architecture, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            'No blueprints yet.',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _showCreateOptions,
            child: const Text('Start Designing'),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _rooms.length,
      itemBuilder: (ctx, index) {
        final room = _rooms[index];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              backgroundColor: Colors.blue.shade100,
              child: const Icon(Icons.room, color: Colors.blue),
            ),
            title: Text(room.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("${room.widthInFeet}' x ${room.lengthInFeet}' | ${room.strokes.length} walls"),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => _confirmDelete(room),
            ),
            onTap: () => _editRoom(room),
          ),
        );
      },
    );
  }

  void _showCreateOptions() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.auto_awesome, color: Colors.blue),
            title: const Text('Auto-Generate with AI'),
            subtitle: const Text('Create from room photos'),
            onTap: () {
              Navigator.pop(ctx);
              _createNewAI();
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit, color: Colors.green),
            title: const Text('Manually Enter (Draw)'),
            subtitle: const Text('Draft from scratch'),
            onTap: () {
              Navigator.pop(ctx);
              _createNewManual();
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _confirmDelete(RoomModel room) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Blueprint?'),
        content: Text('Are you sure you want to delete "${room.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              _deleteRoom(room.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
