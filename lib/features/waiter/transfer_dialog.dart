import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../models/floorplan.dart';

/// Destination picker for moving an open order to another table (port of TransferTableModal.tsx).
/// Resolves to the chosen destination table id, or null.
Future<int?> showTransferDialog(BuildContext context, {required PosTable from, required List<Floor> floors}) {
  return showDialog<int>(context: context, builder: (_) => _TransferDialog(from: from, floors: floors));
}

class _TransferDialog extends StatefulWidget {
  const _TransferDialog({required this.from, required this.floors});
  final PosTable from;
  final List<Floor> floors;
  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Only genuinely free, real tables are valid destinations.
    final options = [
      for (final f in widget.floors)
        for (final t in f.tables)
          if (t.id != widget.from.id && t.status == 'free' && !t.virtual) (floor: f.name, table: t),
    ];

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440, maxHeight: 560),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            color: scheme.primary,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(LucideIcons.moveRight, color: scheme.onPrimary),
                const SizedBox(width: 12),
                Text('TRANSFERT DE TABLE', style: titleStyle.copyWith(fontSize: 20, color: scheme.onPrimary)),
              ]),
              const SizedBox(height: 4),
              Text('DÉPLACER LA COMMANDE DE ${widget.from.name.toUpperCase()}', style: microLabelStyle.copyWith(color: scheme.onPrimary.withValues(alpha: 0.8), letterSpacing: 1.5)),
            ]),
          ),
          Flexible(
            child: options.isEmpty
                ? const Padding(padding: EdgeInsets.all(32), child: Text('Aucune table libre disponible.'))
                : GridView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.all(20),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 1.5),
                    itemCount: options.length,
                    itemBuilder: (_, i) {
                      final o = options[i];
                      final on = _selected == o.table.id;
                      return InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => setState(() => _selected = o.table.id),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: on ? scheme.primary.withValues(alpha: 0.05) : null,
                            border: Border.all(color: on ? scheme.primary : scheme.outline, width: 2),
                          ),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(LucideIcons.table, size: 22, color: on ? scheme.primary : scheme.onSurfaceVariant),
                            const SizedBox(height: 4),
                            Text(o.table.name, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: on ? scheme.primary : null)),
                            Text(o.floor.toUpperCase(), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.slate400)),
                          ]),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            child: Row(children: [
              Expanded(child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('ANNULER'))),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _selected == null ? null : () => Navigator.pop(context, _selected),
                  child: const Text('CONFIRMER', style: TextStyle(fontSize: 12)),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
