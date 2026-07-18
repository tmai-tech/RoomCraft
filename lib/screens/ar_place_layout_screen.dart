import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/layout/ai_designer.dart';
import '../domain/units.dart';
import '../catalog/furniture_catalog.dart';
import '../models/furniture_item.dart';
import '../models/room_model.dart';
import '../providers/room_provider.dart';
import '../services/ar_measure_service.dart';
import '../services/storage_service.dart';
import '../widgets/furniture_catalog_sheet.dart';
import 'blueprint_screen.dart';
import 'isometric_preview_screen.dart';

/// Post-AR product path: real dimensions → place furniture → 3D explore.
///
/// This is the free-architecture AR Room Planner loop after ARCore measure:
/// measure (native) → this screen (place layout at real size) → 3D walkthrough.
class ArPlaceLayoutScreen extends ConsumerStatefulWidget {
  final ArRoomMeasure measure;
  final String roomName;

  const ArPlaceLayoutScreen({
    super.key,
    required this.measure,
    this.roomName = 'AR Room',
  });

  @override
  ConsumerState<ArPlaceLayoutScreen> createState() =>
      _ArPlaceLayoutScreenState();
}

class _ArPlaceLayoutScreenState extends ConsumerState<ArPlaceLayoutScreen> {
  late RoomModel _room;
  DesignStyle? _lastStyle;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final m = widget.measure.normalized;
    _room = RoomModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: widget.roomName,
      widthInFeet: m.widthFt,
      lengthInFeet: m.lengthFt,
    );
  }

  void _furnish(DesignStyle style) {
    final items = AiDesigner.furnish(
      room: _room,
      pixelsPerFoot: 20,
      style: style,
    );
    setState(() {
      _room = _room.copyWith(furniture: items, updatedAt: DateTime.now());
      _lastStyle = style;
    });
  }

  void _addFromCatalog(
    FurnitureType type,
    double w,
    double l, {
    String? catalogId,
  }) {
    final pxf = 20.0;
    final cx = _room.widthInFeet * pxf / 2;
    final cy = _room.lengthInFeet * pxf / 2;
    final item = FurnitureItem(
      id: 'ar_${DateTime.now().microsecondsSinceEpoch}',
      type: type,
      position: Offset(cx, cy),
      widthInFeet: w,
      lengthInFeet: l,
      catalogId: catalogId,
    );
    setState(() {
      _room = _room.copyWith(
        furniture: [..._room.furniture, item],
        updatedAt: DateTime.now(),
      );
    });
  }

  Future<void> _liveArPlace() async {
    try {
      final placed = await ArMeasureService.placeFurniture(
        widthFt: _room.widthInFeet,
        lengthFt: _room.lengthInFeet,
      );
      if (!mounted) return;
      if (placed.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No furniture placed in AR')),
        );
        return;
      }
      final pxf = 20.0;
      final items = <FurnitureItem>[
        for (final p in placed)
          FurnitureItem(
            id: 'arlive_${p.type}_${p.fromLeftFt.toStringAsFixed(2)}_${p.fromBottomFt.toStringAsFixed(2)}',
            type: FurnitureType.values.firstWhere(
              (e) => e.name == p.type,
              orElse: () => FurnitureType.table,
            ),
            position: Offset(
              (p.fromLeftFt * pxf).clamp(0, _room.widthInFeet * pxf),
              (p.fromBottomFt * pxf).clamp(0, _room.lengthInFeet * pxf),
            ),
            widthInFeet: FurnitureCatalog.entryFor(
              FurnitureType.values.firstWhere(
                (e) => e.name == p.type,
                orElse: () => FurnitureType.table,
              ),
            ).defaultWidthFt,
            lengthInFeet: FurnitureCatalog.entryFor(
              FurnitureType.values.firstWhere(
                (e) => e.name == p.type,
                orElse: () => FurnitureType.table,
              ),
            ).defaultLengthFt,
          ),
      ];
      setState(() {
        _room = _room.copyWith(
          furniture: [..._room.furniture, ...items],
          updatedAt: DateTime.now(),
        );
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Placed ${items.length} from AR camera')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('AR place: $e')),
      );
    }
  }

  Future<void> _openEditor({bool threeD = false}) async {
    // Prefer in-memory open first (tests + offline), persist best-effort.
    try {
      ref.read(roomProvider.notifier).loadRoom(_room);
    } catch (_) {}
    if (!mounted) return;

    if (threeD) {
      final result = await Navigator.of(context).push<List<FurnitureItem>>(
        MaterialPageRoute(
          builder: (_) => IsometricPreviewScreen(
            room: _room,
            pixelsPerFoot: 20,
            unitSystem: UnitSystem.feet,
            onFurnitureChanged: (items) {
              setState(() {
                _room = _room.copyWith(furniture: items);
              });
              try {
                ref.read(roomProvider.notifier).applyLayoutAlternative(items);
              } catch (_) {}
            },
          ),
        ),
      );
      if (result != null && mounted) {
        setState(() => _room = _room.copyWith(furniture: result));
      }
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const BlueprintScreen()),
      );
      if (mounted) {
        try {
          setState(() => _room = ref.read(roomProvider).room);
        } catch (_) {}
      }
    }

    // Best-effort persist after edit open
    try {
      await StorageService().saveRoom(_room);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.measure;
    return Scaffold(
      appBar: AppBar(
        title: const Text('AR place layout'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: Colors.teal.shade50,
            child: ListTile(
              leading: const Icon(Icons.view_in_ar, color: Colors.teal, size: 36),
              title: Text(m.summaryLabel),
              subtitle: Text(
                m.isChain
                    ? '4-wall AR chain · real dimensions locked for placement'
                    : 'ARCore floor measure · real dimensions locked',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Place furniture at real size',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Your room is ${_room.widthInFeet.toStringAsFixed(1)} × '
            '${_room.lengthInFeet.toStringAsFixed(1)} ft from AR. '
            'Auto-furnish or pick from the 10,000+ free catalogue, then explore in 3D.',
            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Text(
            'AI place (Furnisher)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in DesignStyle.values)
                ActionChip(
                  key: Key('ar_furnish_${s.name}'),
                  avatar: Icon(
                    _lastStyle == s ? Icons.check : Icons.auto_fix_high,
                    size: 16,
                  ),
                  label: Text(s.label),
                  onPressed: () => _furnish(s),
                ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              FurnitureCatalogSheet.show(
                context,
                unitSystem: UnitSystem.feet,
                onAdd: _addFromCatalog,
              );
            },
            icon: const Icon(Icons.add_box_outlined),
            label: Text(
              'Place from catalogue (${_room.furniture.length} on plan)',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            key: const Key('ar_live_place_camera'),
            onPressed: ArMeasureService.isPlatformSupported
                ? _liveArPlace
                : null,
            icon: const Icon(Icons.view_in_ar),
            label: const Text('Place furniture in AR camera'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.teal.shade700,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 8),
          if (_room.furniture.isNotEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'On plan: ${_room.furniture.length} pieces',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    for (final f in _room.furniture.take(8))
                      Text(
                        '· ${f.type.shortLabel}'
                        '${f.catalogId != null ? ' (${f.catalogId})' : ''} '
                        '${f.widthInFeet.toStringAsFixed(1)}×${f.lengthInFeet.toStringAsFixed(1)} ft',
                        style: const TextStyle(fontSize: 12),
                      ),
                    if (_room.furniture.length > 8)
                      Text('… +${_room.furniture.length - 8} more'),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const Key('ar_place_open_3d'),
            onPressed: _room.furniture.isEmpty
                ? null
                : () => _openEditor(threeD: true),
            icon: const Icon(Icons.threed_rotation),
            label: const Text('Explore & edit in 3D walkthrough'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            key: const Key('ar_place_open_2d'),
            onPressed: () => _openEditor(threeD: false),
            icon: const Icon(Icons.grid_on),
            label: const Text('Open 2D blueprint editor'),
          ),
        ],
      ),
    );
  }
}
