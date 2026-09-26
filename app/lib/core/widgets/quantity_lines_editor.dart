import 'package:flutter/material.dart';

import '../../data/models/catalog.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'form_fields.dart';
import 'product_picker.dart';

class QuantityLine {
  QuantityLine({required this.product, this.quantity = 1, this.note});
  final ProductBrief product;
  int quantity;
  String? note;
}

/// Reusable product + quantity (+ optional note) line editor used by product
/// requests, stock opening/purchase/adjustment/damage, and transfers.
/// Sales and packing allocation have their own bespoke editors.
class QuantityLinesEditor extends StatefulWidget {
  const QuantityLinesEditor({
    super.key,
    required this.lines,
    required this.onChanged,
    this.showNote = false,
    this.noteLabel = 'Note',
    this.noteRequired = false,
    this.allowNegative = false,
    this.emptyHint = 'Add products to this list.',
  });

  final List<QuantityLine> lines;
  final ValueChanged<List<QuantityLine>> onChanged;
  final bool showNote;
  final String noteLabel;
  final bool noteRequired;
  final bool allowNegative;
  final String emptyHint;

  @override
  State<QuantityLinesEditor> createState() => _QuantityLinesEditorState();
}

class _QuantityLinesEditorState extends State<QuantityLinesEditor> {
  Future<void> _add() async {
    final picked = await pickProductDialog(exclude: widget.lines.map((l) => l.product.id).toSet());
    if (picked == null) return;
    setState(() => widget.lines.add(QuantityLine(product: picked)));
    widget.onChanged(widget.lines);
  }

  void _remove(int index) {
    setState(() => widget.lines.removeAt(index));
    widget.onChanged(widget.lines);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.lines.isEmpty)
        Container(
          padding: const EdgeInsets.all(Gap.lg),
          decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(Radii.md), border: Border.all(color: AppColors.border)),
          child: Center(child: Text(widget.emptyHint, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted))),
        )
      else
        Container(
          decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(Radii.md)),
          child: Column(children: [
            for (var i = 0; i < widget.lines.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _LineRow(
                line: widget.lines[i],
                showNote: widget.showNote,
                noteLabel: widget.noteLabel,
                allowNegative: widget.allowNegative,
                onQuantityChanged: (v) {
                  widget.lines[i].quantity = v;
                  widget.onChanged(widget.lines);
                },
                onNoteChanged: (v) {
                  widget.lines[i].note = v;
                  widget.onChanged(widget.lines);
                },
                onRemove: () => _remove(i),
              ),
            ],
          ]),
        ),
      const SizedBox(height: Gap.sm),
      OutlinedButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 16), label: const Text('Add product')),
    ]);
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, required this.showNote, required this.noteLabel, required this.allowNegative, required this.onQuantityChanged, required this.onNoteChanged, required this.onRemove});
  final QuantityLine line;
  final bool showNote;
  final String noteLabel;
  final bool allowNegative;
  final ValueChanged<int> onQuantityChanged;
  final ValueChanged<String> onNoteChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: Gap.sm),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(line.product.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(line.product.sku, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
            ]),
          ),
          const SizedBox(width: Gap.sm),
          QuantityInput(
            value: line.quantity,
            min: allowNegative ? -999999 : (line.quantity == 0 ? 0 : 1),
            onChanged: onQuantityChanged,
          ),
          IconButton(icon: const Icon(Icons.close, size: 16), tooltip: 'Remove', onPressed: onRemove),
        ]),
        if (showNote) ...[
          const SizedBox(height: 6),
          TextFormField(
            initialValue: line.note,
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(hintText: noteLabel, isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
            onChanged: onNoteChanged,
          ),
        ],
      ]),
    );
  }
}
