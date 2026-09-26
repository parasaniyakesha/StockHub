import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// Toolbar above a table: search on the left, filters, actions on the right.
/// Wraps onto multiple lines at narrow widths.
class FilterBar extends StatelessWidget {
  const FilterBar({super.key, this.search, this.filters = const [], this.actions = const []});
  final Widget? search;
  final List<Widget> filters;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.lg, Gap.md),
      child: Wrap(
        spacing: Gap.sm,
        runSpacing: Gap.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Wrap(spacing: Gap.sm, runSpacing: Gap.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [if (search != null) search!, ...filters]),
          if (actions.isNotEmpty) Wrap(spacing: Gap.sm, runSpacing: Gap.sm, children: actions),
        ],
      ),
    );
  }
}

/// Search box bound to a callback (controllers debounce it).
class SearchField extends StatefulWidget {
  const SearchField({super.key, required this.onChanged, this.hint = 'Search…', this.width = 280, this.initialValue = ''});
  final ValueChanged<String> onChanged;
  final String hint;
  final double width;
  final String initialValue;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _c = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: AppTheme.controlHeight,
      child: ValueListenableBuilder(
        valueListenable: _c,
        builder: (context, value, _) => TextField(
          controller: _c,
          onChanged: widget.onChanged,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.search, size: 18),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () {
                      _c.clear();
                      widget.onChanged('');
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

/// Compact dropdown filter. `null` value = "All".
class FilterDropdown<T> extends StatelessWidget {
  const FilterDropdown({super.key, required this.label, required this.value, required this.items, required this.onChanged, this.itemLabel, this.width = 170, this.allLabel});
  final String label;
  final T? value;
  final List<T> items;
  final ValueChanged<T?> onChanged;
  final String Function(T)? itemLabel;
  final double width;
  final String? allLabel;

  @override
  Widget build(BuildContext context) {
    String labelOf(T v) => itemLabel?.call(v) ?? Fmt.enumLabel(v.toString());
    return PopupMenuButton<Object?>(
      tooltip: label,
      position: PopupMenuPosition.under,
      constraints: BoxConstraints(minWidth: width, maxHeight: 420),
      onSelected: (v) => onChanged(v == _all ? null : v as T),
      itemBuilder: (_) => [
        PopupMenuItem<Object?>(value: _all, height: 36, child: Text(allLabel ?? 'All ${label.toLowerCase()}')),
        const PopupMenuDivider(height: 1),
        for (final i in items)
          PopupMenuItem<Object?>(
            value: i,
            height: 36,
            child: Row(children: [
              Expanded(child: Text(labelOf(i), overflow: TextOverflow.ellipsis)),
              if (i == value) const Icon(Icons.check, size: 16, color: AppColors.primary),
            ]),
          ),
      ],
      child: Container(
        height: AppTheme.controlHeight,
        constraints: BoxConstraints(minWidth: width * 0.7, maxWidth: width + 60),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: value == null ? AppColors.surface : AppColors.primarySoft,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: value == null ? AppColors.borderStrong : AppColors.primary.withValues(alpha: 0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text(
              value == null ? label : '$label: ${labelOf(value as T)}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: value == null ? AppColors.textSecondary : AppColors.primary),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.expand_more, size: 18, color: value == null ? AppColors.textMuted : AppColors.primary),
        ]),
      ),
    );
  }
}

const _all = '__all__';

/// Date range filter button.
class DateRangeFilter extends StatelessWidget {
  const DateRangeFilter({super.key, required this.start, required this.end, required this.onChanged, this.label = 'Date'});
  final DateTime? start;
  final DateTime? end;
  final void Function(DateTime? start, DateTime? end) onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final active = start != null || end != null;
    final text = active ? '${Fmt.shortDate(start)} – ${Fmt.shortDate(end)}' : label;
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.sm),
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(now.year - 5),
          lastDate: DateTime(now.year + 1),
          initialDateRange: active ? DateTimeRange(start: start ?? end!, end: end ?? start!) : null,
          builder: (context, child) => Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420, maxHeight: 620), child: child)),
        );
        if (picked != null) onChanged(picked.start, picked.end);
      },
      child: Container(
        height: AppTheme.controlHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? AppColors.primarySoft : AppColors.surface,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: active ? AppColors.primary.withValues(alpha: 0.4) : AppColors.borderStrong),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.calendar_today_outlined, size: 15, color: active ? AppColors.primary : AppColors.textMuted),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: active ? AppColors.primary : AppColors.textSecondary)),
          if (active) ...[
            const SizedBox(width: 4),
            InkWell(onTap: () => onChanged(null, null), child: const Icon(Icons.close, size: 15, color: AppColors.primary)),
          ],
        ]),
      ),
    );
  }
}

/// "Clear filters" link shown when any filter is active.
class ClearFiltersButton extends StatelessWidget {
  const ClearFiltersButton({super.key, required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) =>
      TextButton.icon(onPressed: onPressed, icon: const Icon(Icons.filter_alt_off_outlined, size: 16), label: const Text('Clear'));
}
