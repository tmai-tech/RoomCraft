import 'package:flutter/material.dart';

import '../catalog/furniture_catalog.dart';
import '../domain/units.dart';
import '../models/furniture_item.dart';

/// Bottom sheet furniture catalog with categories and one-tap add.
class FurnitureCatalogSheet extends StatefulWidget {
  final UnitSystem unitSystem;
  final void Function(FurnitureType type, double widthFt, double lengthFt) onAdd;

  const FurnitureCatalogSheet({
    super.key,
    required this.unitSystem,
    required this.onAdd,
  });

  static Future<void> show(
    BuildContext context, {
    required UnitSystem unitSystem,
    required void Function(FurnitureType type, double widthFt, double lengthFt) onAdd,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => FurnitureCatalogSheet(
        unitSystem: unitSystem,
        onAdd: onAdd,
      ),
    );
  }

  @override
  State<FurnitureCatalogSheet> createState() => _FurnitureCatalogSheetState();
}

class _FurnitureCatalogSheetState extends State<FurnitureCatalogSheet> {
  FurnitureCategory? _filter;

  @override
  Widget build(BuildContext context) {
    final entries = _filter == null
        ? FurnitureCatalog.all
        : FurnitureCatalog.byCategory(_filter!);

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.62,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Furniture catalog',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('All'),
                    selected: _filter == null,
                    onSelected: (_) => setState(() => _filter = null),
                  ),
                  const SizedBox(width: 8),
                  ...FurnitureCategory.values.map((c) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(FurnitureCatalog.categoryLabel(c)),
                        selected: _filter == c,
                        onSelected: (_) => setState(() => _filter = c),
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                itemCount: entries.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final e = entries[i];
                  final sizeLabel =
                      '${LengthFormat.formatFeet(e.defaultWidthFt, widget.unitSystem)}'
                      ' × '
                      '${LengthFormat.formatFeet(e.defaultLengthFt, widget.unitSystem)}';
                  return Card(
                    elevation: 0,
                    color: Colors.blueGrey.shade50,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.white,
                        child: Icon(e.icon, color: Colors.blueGrey.shade700),
                      ),
                      title: Text(e.label),
                      subtitle: Text('${e.description} · $sizeLabel'),
                      trailing: FilledButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          widget.onAdd(
                            e.type,
                            e.defaultWidthFt,
                            e.defaultLengthFt,
                          );
                        },
                        child: const Text('Add'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
