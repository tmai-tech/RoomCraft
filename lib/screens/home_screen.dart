import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../domain/units.dart';
import '../models/room_model.dart';
import '../providers/room_provider.dart';
import '../domain/layout/sample_plans.dart';
import '../services/prefs_service.dart';
import '../services/storage_service.dart';
import '../widgets/room_thumbnail.dart';
import 'blueprint_screen.dart';
import '../services/ar_measure_service.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

enum _HomeSort { updatedDesc, updatedAsc, nameAsc }

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final StorageService _storageService = StorageService();
  final PrefsService _prefs = PrefsService();
  final _searchCtrl = TextEditingController();
  List<RoomModel> _rooms = [];
  bool _isLoading = true;
  String? _loadError;
  UnitSystem _units = UnitSystem.feet;
  bool _showBetaBanner = false;
  String _query = '';
  _HomeSort _sort = _HomeSort.updatedDesc;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<RoomModel> get _filteredRooms {
    var list = List<RoomModel>.from(_rooms);
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list
          .where((r) => r.name.toLowerCase().contains(q))
          .toList();
    }
    switch (_sort) {
      case _HomeSort.updatedDesc:
        list.sort((a, b) {
          final au = a.updatedAt ?? DateTime(1970);
          final bu = b.updatedAt ?? DateTime(1970);
          return bu.compareTo(au);
        });
      case _HomeSort.updatedAsc:
        list.sort((a, b) {
          final au = a.updatedAt ?? DateTime(1970);
          final bu = b.updatedAt ?? DateTime(1970);
          return au.compareTo(bu);
        });
      case _HomeSort.nameAsc:
        list.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
    }
    return list;
  }

  Future<void> _loadRooms() async {
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    try {
      final rooms = await _storageService.loadRooms();
      final units = await _prefs.loadUnitSystem();
      final bannerDismissed = await _prefs.isBetaBannerDismissed();
      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _units = units;
        _isLoading = false;
        _showBetaBanner = AppConfig.isBeta && !bannerDismissed;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = 'Could not load saved plans. $e';
      });
    }
  }

  Future<void> _deleteRoom(String id) async {
    await _storageService.deleteRoom(id);
    await _loadRooms();
  }

  Future<void> _duplicateRoom(RoomModel room) async {
    await _storageService.duplicateRoom(room);
    await _loadRooms();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Duplicated “${room.name}”')),
    );
  }

  Future<void> _duplicateUpperFloor(RoomModel room) async {
    final upper = await _storageService.duplicateAsUpperFloor(room);
    await _loadRooms();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Created ${upper.spaceLabel}: “${upper.name}”')),
    );
  }

  Future<void> _createNewManual() async {
    final size = await _promptRoomSize();
    if (!mounted || size == null) return;
    ref.invalidate(roomProvider);
    // Reading after invalidate creates a fresh editor room, then apply size.
    ref.read(roomProvider);
    ref.read(roomProvider.notifier).updateRoomSize(size.$1, size.$2);
    ref.read(roomProvider.notifier).setTool(ToolMode.wall);
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const BlueprintScreen()))
        .then((_) => _loadRooms());
  }

  /// Ask for room size so manual plans are not stuck at a mystery 10×10 box.
  Future<(double, double)?> _promptRoomSize() async {
    final wCtrl = TextEditingController(text: '12');
    final lCtrl = TextEditingController(text: '14');
    final unit = _units;
    final result = await showDialog<(double, double)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New room size'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Set the outer room size first (not a fixed 10×10). '
              'You can change it later in the editor.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: wCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Width (${unit.label})',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: lCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Length (${unit.label})',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final wDisp = double.tryParse(wCtrl.text.trim());
              final lDisp = double.tryParse(lCtrl.text.trim());
              if (wDisp == null ||
                  lDisp == null ||
                  wDisp <= 0 ||
                  lDisp <= 0) {
                return;
              }
              Navigator.pop(ctx, (
                LengthFormat.displayToFeet(wDisp, unit),
                LengthFormat.displayToFeet(lDisp, unit),
              ));
            },
            child: const Text('Create room'),
          ),
        ],
      ),
    );
    wCtrl.dispose();
    lCtrl.dispose();
    return result;
  }

  void _createNewAI() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const ScannerScreen()))
        .then((_) => _loadRooms());
  }

  /// Distinct AR Room Planner path — opens scanner in AR guided measure mode.
  void _createNewAR() {
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => const ScannerScreen(
              initialScanMode: 'ar_guided',
              openAdvanced: true,
            ),
          ),
        )
        .then((_) => _loadRooms());
  }

  void _editRoom(RoomModel room) {
    ref.read(roomProvider.notifier).loadRoom(room);
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const BlueprintScreen()))
        .then((_) => _loadRooms());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_mosaic_outlined),
            tooltip: 'Gallery of ideas',
            onPressed: _showGallery,
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () {
              Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => const SettingsScreen()))
                  .then((_) => _loadRooms());
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_showBetaBanner) _buildBetaBanner(),
          if (_rooms.isNotEmpty) _buildSearchSortBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _loadError != null
                    ? _buildErrorState()
                    : _rooms.isEmpty
                        ? _buildEmptyState()
                        : _filteredRooms.isEmpty
                            ? Center(
                                child: Text(
                                  'No plans match “$_query”',
                                  style: TextStyle(color: Colors.grey.shade600),
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _loadRooms,
                                child: _buildRoomList(),
                              ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateOptions,
        label: const Text('New Blueprint'),
        icon: const Icon(Icons.add),
      ),
    );
  }


  Widget _buildBetaBanner() {
    return MaterialBanner(
      content: const Text(
        'Closed beta ${AppConfig.appVersion} — plans stay on this device. Send feedback from Settings.',
      ),
      leading: const Icon(Icons.science_outlined),
      backgroundColor: Colors.amber.shade50,
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
          child: const Text('Feedback'),
        ),
        TextButton(
          onPressed: () async {
            await _prefs.setBetaBannerDismissed(true);
            if (mounted) setState(() => _showBetaBanner = false);
          },
          child: const Text('Dismiss'),
        ),
      ],
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
            const SizedBox(height: 16),
            Text(
              _loadError ?? 'Something went wrong',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _loadRooms, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.architecture, size: 88, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'No blueprints yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Scan a room with your camera or draw a plan from scratch.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _createNewAR,
              icon: const Icon(Icons.view_in_ar),
              label: const Text('AR Room Planner'),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _createNewAI,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Scan with photos'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _createNewManual,
              icon: const Icon(Icons.edit),
              label: const Text('Draw manually'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchSortBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search plans…',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<_HomeSort>(
            tooltip: 'Sort',
            initialValue: _sort,
            onSelected: (v) => setState(() => _sort = v),
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: _HomeSort.updatedDesc,
                child: Text('Newest first'),
              ),
              PopupMenuItem(
                value: _HomeSort.updatedAsc,
                child: Text('Oldest first'),
              ),
              PopupMenuItem(
                value: _HomeSort.nameAsc,
                child: Text('Name A–Z'),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.sort),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomList() {
    final rooms = _filteredRooms;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      itemCount: rooms.length,
      itemBuilder: (ctx, index) {
        final room = rooms[index];
        final dim =
            '${LengthFormat.formatFeet(room.widthInFeet, _units)} × '
            '${LengthFormat.formatFeet(room.lengthInFeet, _units)}';
        final updated = room.updatedAt;
        final when = updated == null
            ? ''
            : '${updated.year}-${updated.month.toString().padLeft(2, '0')}-${updated.day.toString().padLeft(2, '0')}';

        return Card(
          elevation: 1,
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _editRoom(room),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  RoomThumbnail(room: room, size: 72),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$dim · ${room.furniture.length} items · ${room.strokes.length} lines',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Chip(
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              avatar: Icon(
                                room.isExterior
                                    ? Icons.yard_outlined
                                    : Icons.layers_outlined,
                                size: 14,
                              ),
                              label: Text(
                                room.spaceLabel,
                                style: const TextStyle(fontSize: 11),
                              ),
                              padding: EdgeInsets.zero,
                              labelPadding:
                                  const EdgeInsets.only(right: 6),
                            ),
                            if (room.isPolygonFloor)
                              Chip(
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                label: const Text(
                                  'L-shape',
                                  style: TextStyle(fontSize: 11),
                                ),
                                padding: EdgeInsets.zero,
                                labelPadding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                              ),
                          ],
                        ),
                        if (when.isNotEmpty)
                          Text(
                            'Updated $when',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'open') _editRoom(room);
                      if (v == 'duplicate') await _duplicateRoom(room);
                      if (v == 'upper') await _duplicateUpperFloor(room);
                      if (v == 'delete') _confirmDelete(room);
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'open', child: Text('Open')),
                      const PopupMenuItem(
                        value: 'duplicate',
                        child: Text('Duplicate'),
                      ),
                      if (!room.isExterior)
                        const PopupMenuItem(
                          value: 'upper',
                          child: Text('Duplicate as upper floor'),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Delete'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }


  Future<void> _showGallery() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Gallery of ideas',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                'Starter plans like Planner 5D inspiration — free on-device styles',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.5,
                child: ListView(
                  children: [
                    for (final plan in SamplePlans.all)
                      ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.indigo.shade50,
                          child: Icon(Icons.home_work_outlined,
                              color: Colors.indigo.shade700),
                        ),
                        title: Text(plan.title),
                        subtitle: Text(plan.blurb),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () async {
                          Navigator.pop(ctx);
                          final room = SamplePlans.materialize(plan);
                          await _storageService.saveRoom(room);
                          await _loadRooms();
                          if (!mounted) return;
                          _editRoom(room);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateOptions() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.view_in_ar, color: Colors.teal),
              title: const Text('AR Room Planner'),
              subtitle: Text(
                ArMeasureService.isPlatformSupported
                    ? 'ARCore real dimensions → plan → furnish'
                    : 'Needs Android + ARCore (photo scan still available)',
              ),
              onTap: () {
                Navigator.pop(ctx);
                _createNewAR();
              },
            ),
            ListTile(
              leading: const Icon(Icons.auto_awesome, color: Colors.blue),
              title: const Text('Scan with AI photos'),
              subtitle: const Text('Photos → top-down plan'),
              onTap: () {
                Navigator.pop(ctx);
                _createNewAI();
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.green),
              title: const Text('Draw manually'),
              subtitle: const Text('Walls and furniture by hand'),
              onTap: () {
                Navigator.pop(ctx);
                _createNewManual();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(RoomModel room) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete blueprint?'),
        content: Text('Delete “${room.name}”? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
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
