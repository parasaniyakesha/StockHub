import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/data_table_view.dart';
import '../../../core/widgets/filter_bar.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/catalog.dart';
import '../controllers/categories_controller.dart';
import '../widgets/category_form_dialog.dart';

class CategoriesView extends StatelessWidget {
  const CategoriesView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(CategoriesController(Get.find()));
    return ShellPage(
      title: 'Categories',
      breadcrumb: 'Catalog',
      headerActions: [
        FilledButton.icon(
          onPressed: () async {
            if (await showCategoryFormDialog(allCategories: c.allCategories)) c.load();
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('New category'),
        ),
      ],
      child: SectionCard(
        padding: EdgeInsets.zero,
        expandChild: true,
        child: Column(children: [
          Obx(() => FilterBar(
                search: SearchField(onChanged: c.setSearch, hint: 'Search categories…'),
                filters: [
                  FilterDropdown<String>(label: 'Status', value: c.filters['status'] as String?, items: const ['ACTIVE', 'INACTIVE'], onChanged: (v) => c.setFilter('status', v)),
                  if (c.hasActiveFilters) ClearFiltersButton(onPressed: c.clearFilters),
                ],
              )),
          const Divider(height: 1),
          Expanded(
            child: AppDataTable<Category>(
              controller: c,
              emptyTitle: 'No categories found',
              columns: [
                ColumnSpec(label: 'Category', sortKey: 'name', flex: 3, cell: (cat) => Text(cat.displayName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                ColumnSpec(label: 'Code', sortKey: 'code', width: 100, cell: (cat) => Text(cat.code, style: const TextStyle(fontSize: 12.5))),
                ColumnSpec(label: 'Products', width: 100, numeric: true, cell: (cat) => Text('${cat.productCount}', style: const TextStyle(fontSize: 12.5))),
                ColumnSpec(label: 'Subcategories', width: 120, numeric: true, cell: (cat) => Text('${cat.childCount}', style: const TextStyle(fontSize: 12.5))),
                ColumnSpec(label: 'Status', sortKey: 'status', width: 100, cell: (cat) => StatusBadge(cat.status)),
              ],
              rowActions: (cat) => PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, size: 18),
                onSelected: (action) async {
                  if (action == 'edit') {
                    if (await showCategoryFormDialog(category: cat, allCategories: c.allCategories)) c.load();
                  } else if (action == 'toggle') {
                    c.toggleStatus(cat);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'toggle', child: Text(cat.isActive ? 'Deactivate' : 'Activate')),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
