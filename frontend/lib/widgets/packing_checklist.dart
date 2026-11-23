import 'package:material_ui/material_ui.dart';

import '../models/packing_item_model.dart';

/// Editable per-trip packing checklist widget persisted offline (FM4).
class PackingChecklist extends StatefulWidget {
  const PackingChecklist({
    super.key,
    required this.items,
    required this.onToggle,
    required this.onAdd,
    required this.onRemove,
  });

  final List<PackingItemModel> items;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onAdd;
  final ValueChanged<String> onRemove;

  @override
  State<PackingChecklist> createState() => _PackingChecklistState();
}

class _PackingChecklistState extends State<PackingChecklist> {
  final _newItemController = TextEditingController();

  @override
  void dispose() {
    _newItemController.dispose();
    super.dispose();
  }

  void _handleAdd() {
    final text = _newItemController.text.trim();
    if (text.isEmpty) return;
    widget.onAdd(text);
    _newItemController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final packedCount = widget.items.where((i) => i.isPacked).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.checklist_rounded, color: colors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Packing Checklist',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Chip(
                  label: Text('$packedCount/${widget.items.length} packed'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _newItemController,
                    decoration: const InputDecoration(
                      hintText: 'Add item (e.g. Raincoat)',
                      isDense: true,
                    ),
                    onSubmitted: (_) => _handleAdd(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _handleAdd,
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Add packing item',
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final item in widget.items)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: item.isPacked,
                onChanged: (_) => widget.onToggle(item.id),
                title: Text(
                  item.title,
                  style: TextStyle(
                    decoration: item.isPacked
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    color: item.isPacked ? colors.onSurfaceVariant : null,
                  ),
                ),
                subtitle: Text(item.category),
                secondary: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  tooltip: 'Remove item',
                  onPressed: () => widget.onRemove(item.id),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
