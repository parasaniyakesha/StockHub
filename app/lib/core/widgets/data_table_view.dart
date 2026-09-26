import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../base/paged_list_controller.dart';
import '../base/view_state.dart';
import '../constants/app_config.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import 'state_views.dart';

class ColumnSpec<T> {
  const ColumnSpec({
    required this.label,
    required this.cell,
    this.sortKey,
    this.width,
    this.flex = 1,
    this.numeric = false,
    this.visibleByDefault = true,
  });

  final String label;
  final Widget Function(T item) cell;

  /// Server sort key; null = column is not sortable.
  final String? sortKey;

  /// Fixed width in logical pixels; if null, uses [flex] of remaining space.
  final double? width;
  final int flex;
  final bool numeric;
  final bool visibleByDefault;
}

/// Minimum width given to a flexible (non-fixed-width) column before the
/// table switches to horizontal scrolling.
const _minFlexColumnWidth = 110.0;

/// Resolves one pixel width per column. Flexible columns share the space left
/// after fixed-width columns and [reserved] (checkbox/actions), proportional
/// to their flex - but never below [_minFlexColumnWidth]. This is computed up
/// front so cells are always plain SizedBoxes: a Row nested inside a
/// horizontally-scrolling SingleChildScrollView has unbounded width, and an
/// Expanded/Flexible child there throws ("BoxConstraints forces an infinite
/// width"), so this table never uses Expanded for column layout.
List<double> _resolveColumnWidths<T>(double available, List<ColumnSpec<T>> columns, double reserved) {
  final usable = available - reserved;
  final fixedTotal = columns.where((c) => c.width != null).fold<double>(0, (a, c) => a + c.width!);
  final flexCols = columns.where((c) => c.width == null).toList();
  final totalFlex = flexCols.fold<int>(0, (a, c) => a + c.flex);
  if (totalFlex == 0) return [for (final c in columns) c.width!];

  final remaining = usable - fixedTotal;
  final fitsWithoutScrolling = remaining >= totalFlex * _minFlexColumnWidth;
  return [
    for (final c in columns)
      c.width ?? (fitsWithoutScrolling ? remaining * c.flex / totalFlex : _minFlexColumnWidth),
  ];
}

/// Enterprise data table bound to a [PagedListController]: server-side search,
/// sort, pagination, optional row selection with bulk actions, and column
/// hide/show. Renders loading/empty/error states automatically.
class AppDataTable<T> extends StatelessWidget {
  const AppDataTable({
    super.key,
    required this.controller,
    required this.columns,
    this.rowActions,
    this.selectable = false,
    this.onRowTap,
    this.bulkActions = const [],
    this.emptyTitle = 'No records found',
    this.emptyMessage,
    this.rowHeight = 46,
  });

  final PagedListController<T> controller;
  final List<ColumnSpec<T>> columns;
  final Widget Function(T item)? rowActions;
  final bool selectable;
  final void Function(T item)? onRowTap;
  final List<Widget> bulkActions;
  final String emptyTitle;
  final String? emptyMessage;
  final double rowHeight;

  static const _actionsWidth = 56.0;
  static const _checkboxWidth = 44.0;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final state = controller.state.value;
      if (state == ViewState.loading) return const _SkeletonTable();
      if (state == ViewState.error) return ErrorView(message: controller.errorMessage.value, onRetry: controller.load);
      if (state == ViewState.empty) return EmptyView(title: emptyTitle, message: emptyMessage, icon: Icons.search_off_outlined);

      final reserved = (selectable ? _checkboxWidth : 0.0) + (rowActions != null ? _actionsWidth : 0.0);

      // Read every value the row/footer widgets need RIGHT HERE, inside this
      // Obx's own callback. LayoutBuilder's `builder` only runs later, during
      // layout, which is outside whatever Obx returned it - any .value read
      // only in there is invisible to Obx's dependency tracking and would
      // never trigger a rebuild (e.g. after an action calls controller.load()).
      final items = controller.items.toList();
      final refreshing = controller.refreshing.value;
      final hasSelection = selectable && controller.selectedIds.isNotEmpty;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasSelection) _SelectionBar<T>(controller: controller, actions: bulkActions),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final widths = _resolveColumnWidths(constraints.maxWidth, columns, reserved);
              final contentWidth = widths.fold<double>(0, (a, b) => a + b) + reserved;
              return Stack(children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: contentWidth < constraints.maxWidth ? constraints.maxWidth : contentWidth,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _HeaderRow<T>(controller: controller, columns: columns, widths: widths, selectable: selectable, actionsWidth: rowActions != null ? _actionsWidth : 0),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, i) {
                            final item = items[i];
                            return _DataRow<T>(
                              item: item,
                              controller: controller,
                              columns: columns,
                              widths: widths,
                              selectable: selectable,
                              rowActions: rowActions,
                              actionsWidth: _actionsWidth,
                              onTap: onRowTap == null ? null : () => onRowTap!(item),
                              height: rowHeight,
                              zebra: i.isOdd,
                            );
                          },
                        ),
                      ),
                    ]),
                  ),
                ),
                if (refreshing) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
              ]);
            }),
          ),
          const Divider(height: 1),
          _PaginationFooter(controller: controller),
        ],
      );
    });
  }
}

class _HeaderRow<T> extends StatelessWidget {
  const _HeaderRow({required this.controller, required this.columns, required this.widths, required this.selectable, required this.actionsWidth});
  final PagedListController<T> controller;
  final List<ColumnSpec<T>> columns;
  final List<double> widths;
  final bool selectable;
  final double actionsWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: AppColors.surfaceMuted,
      child: Row(children: [
        if (selectable)
          SizedBox(
            width: 44,
            child: Obx(() => Checkbox(
                  value: controller.allOnPageSelected,
                  onChanged: (_) => controller.toggleSelectAllOnPage(),
                )),
          ),
        for (var i = 0; i < columns.length; i++)
          _HeaderCell(label: columns[i].label, width: widths[i], numeric: columns[i].numeric, sortKey: columns[i].sortKey, controller: controller),
        if (actionsWidth > 0) SizedBox(width: actionsWidth),
      ]),
    );
  }
}

class _HeaderCell<T> extends StatelessWidget {
  const _HeaderCell({required this.label, required this.width, required this.numeric, required this.sortKey, required this.controller});
  final String label;
  final double width;
  final bool numeric;
  final String? sortKey;
  final PagedListController<T> controller;

  Widget _label(Color color) => Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.2, color: color),
      );

  @override
  Widget build(BuildContext context) {
    // Non-sortable columns never read an Rx value, so they must not be built
    // inside an Obx - Obx throws when its builder registers zero dependencies.
    if (sortKey == null) {
      return SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
          child: Row(mainAxisAlignment: numeric ? MainAxisAlignment.end : MainAxisAlignment.start, children: [Flexible(child: _label(AppColors.textSecondary))]),
        ),
      );
    }
    final content = Obx(() {
      final active = controller.sortBy.value == sortKey;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
        child: Row(
          mainAxisAlignment: numeric ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Flexible(child: _label(active ? AppColors.primary : AppColors.textSecondary)),
            const SizedBox(width: 2),
            Icon(
              active ? (controller.sortAsc.value ? Icons.arrow_upward : Icons.arrow_downward) : Icons.unfold_more,
              size: 13,
              color: active ? AppColors.primary : AppColors.textMuted,
            ),
          ],
        ),
      );
    });
    return SizedBox(width: width, child: InkWell(onTap: () => controller.sort(sortKey!), child: content));
  }
}

class _DataRow<T> extends StatelessWidget {
  const _DataRow({
    required this.item,
    required this.controller,
    required this.columns,
    required this.widths,
    required this.selectable,
    required this.rowActions,
    required this.actionsWidth,
    required this.onTap,
    required this.height,
    required this.zebra,
  });

  final T item;
  final PagedListController<T> controller;
  final List<ColumnSpec<T>> columns;
  final List<double> widths;
  final bool selectable;
  final Widget Function(T item)? rowActions;
  final double actionsWidth;
  final VoidCallback? onTap;
  final double height;
  final bool zebra;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: zebra ? AppColors.surfaceMuted.withValues(alpha: 0.5) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: AppColors.primarySoft.withValues(alpha: 0.4),
        child: SizedBox(
          height: height,
          child: Row(children: [
            if (selectable)
              SizedBox(
                width: 44,
                child: Obx(() => Checkbox(value: controller.isSelected(item), onChanged: (_) => controller.toggleSelected(item))),
              ),
            for (var i = 0; i < columns.length; i++) SizedBox(width: widths[i], child: _cellPadding(columns[i])),
            if (rowActions != null) SizedBox(width: actionsWidth, child: Center(child: rowActions!(item))),
          ]),
        ),
      ),
    );
  }

  Widget _cellPadding(ColumnSpec<T> col) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.sm),
        child: Align(alignment: col.numeric ? Alignment.centerRight : Alignment.centerLeft, child: col.cell(item)),
      );
}

class _SelectionBar<T> extends StatelessWidget {
  const _SelectionBar({required this.controller, required this.actions});
  final PagedListController<T> controller;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primarySoft,
      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
      child: Row(children: [
        Text('${controller.selectedIds.length} selected', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
        const SizedBox(width: Gap.md),
        TextButton(onPressed: controller.clearSelection, child: const Text('Clear')),
        const Spacer(),
        ...actions,
      ]),
    );
  }
}

class _PaginationFooter<T> extends StatelessWidget {
  const _PaginationFooter({required this.controller});
  final PagedListController<T> controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final total = controller.total.value;
      final page = controller.page.value;
      final limit = controller.limit.value;
      final pages = controller.totalPages.value;
      final from = total == 0 ? 0 : (page - 1) * limit + 1;
      final to = (page * limit).clamp(0, total);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: Gap.sm),
        child: Wrap(
          spacing: Gap.lg,
          runSpacing: Gap.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Rows per page', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(width: Gap.sm),
              DropdownButton<int>(
                value: limit,
                underline: const SizedBox(),
                items: [for (final s in AppConfig.pageSizes) DropdownMenuItem(value: s, child: Text('$s'))],
                onChanged: (v) => v == null ? null : controller.setLimit(v),
                style: const TextStyle(fontSize: 12.5, color: AppColors.textPrimary),
              ),
              const SizedBox(width: Gap.lg),
              Text(total == 0 ? '0 results' : '$from–$to of $total', style: Theme.of(context).textTheme.bodySmall),
            ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(icon: const Icon(Icons.first_page, size: 18), onPressed: page > 1 ? () => controller.goToPage(1) : null),
              IconButton(icon: const Icon(Icons.chevron_left, size: 18), onPressed: page > 1 ? () => controller.goToPage(page - 1) : null),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text('Page $page of ${pages == 0 ? 1 : pages}', style: Theme.of(context).textTheme.bodySmall)),
              IconButton(icon: const Icon(Icons.chevron_right, size: 18), onPressed: page < pages ? () => controller.goToPage(page + 1) : null),
              IconButton(icon: const Icon(Icons.last_page, size: 18), onPressed: page < pages ? () => controller.goToPage(pages) : null),
            ]),
          ],
        ),
      );
    });
  }
}

class _SkeletonTable extends StatelessWidget {
  const _SkeletonTable();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(Gap.lg),
      child: Column(children: [
        for (var i = 0; i < 8; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Gap.sm),
            child: Row(children: [
              Skeleton(width: 28, height: 28, radius: 6),
              const SizedBox(width: Gap.lg),
              const Expanded(flex: 2, child: Skeleton()),
              const SizedBox(width: Gap.lg),
              const Expanded(child: Skeleton()),
              const SizedBox(width: Gap.lg),
              const Expanded(child: Skeleton()),
              const SizedBox(width: Gap.lg),
              SizedBox(width: 80, child: Skeleton()),
            ]),
          ),
      ]),
    );
  }
}
