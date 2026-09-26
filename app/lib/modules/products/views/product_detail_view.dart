import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/session/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/catalog.dart';
import '../controllers/product_detail_controller.dart';
import '../widgets/product_form_dialog.dart';

class ProductDetailView extends StatelessWidget {
  const ProductDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    final id = Get.parameters['id']!;
    final reused = Get.isRegistered<ProductDetailController>(tag: id);
    final c = Get.put(ProductDetailController(Get.find(), Get.find(), id), tag: id);
    if (reused) c.load();
    final canManage = Get.find<AuthService>().can('products.manage');
    final isStore = Get.find<AuthService>().isStore;

    return ShellPage(
      title: 'Product details',
      breadcrumb: 'Catalog / Products',
      headerActions: [
        if (canManage)
          Obx(() {
            final p = c.product.value;
            if (p == null) return const SizedBox();
            return OutlinedButton.icon(
              onPressed: () async {
                final saved = await showProductFormDialog(product: p, categories: c.categories);
                if (saved != null) {
                  Toast.success('Product updated');
                  c.load();
                }
              },
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit'),
            );
          }),
      ],
      child: StateSwitcher(
        state: c.state,
        onRetry: c.load,
        error: c.errorMessage.value,
        builder: () {
          final p = c.product.value!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: AppColors.neutralSoft, borderRadius: BorderRadius.circular(Radii.md)),
                  child: const Icon(Icons.inventory_2_outlined, size: 28, color: AppColors.textMuted),
                ),
                const SizedBox(width: Gap.lg),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(p.name, style: Theme.of(context).textTheme.headlineSmall, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: Gap.sm),
                      StatusBadge(p.status),
                    ]),
                    const SizedBox(height: 4),
                    Text('${p.sku}${p.barcode != null ? ' · ${p.barcode}' : ''}${p.brand != null ? ' · ${p.brand}' : ''}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ]),
                ),
              ]),
              const SizedBox(height: Gap.xl),
              LayoutBuilder(builder: (context, cst) {
                final wide = cst.maxWidth > 900;
                final overview = SectionCard(
                  title: 'Overview',
                  child: InfoGrid(items: [
                    ('Category', infoText(p.category?.name)),
                    ('Unit', infoText(p.unit)),
                    if (!isStore) ('Purchase price', infoText(p.purchasePrice == null ? null : Fmt.money(p.purchasePrice))),
                    ('Selling price', infoText(Fmt.money(p.sellingPrice))),
                    ('Tax rate', infoText(Fmt.percent(p.taxRate))),
                    if (!isStore && p.marginPercent != null) ('Margin', infoText(Fmt.percent(p.marginPercent))),
                    ('Minimum stock', infoText('${p.minimumStock}')),
                    ('Maximum stock', infoText(p.maximumStock == null ? null : '${p.maximumStock}')),
                    ('Created', infoText(Fmt.date(p.createdAt))),
                    if (p.description != null && p.description!.isNotEmpty) ('Description', infoText(p.description)),
                  ]),
                );
                final stock = SectionCard(
                  title: 'Stock by location',
                  child: _StockBreakdown(product: p, isStore: isStore),
                );
                if (!wide) return Column(children: [overview, const SizedBox(height: Gap.lg), stock]);
                return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(flex: 3, child: overview), const SizedBox(width: Gap.lg), Expanded(flex: 2, child: stock)]));
              }),
            ]),
          );
        },
      ),
    );
  }
}

class _StockBreakdown extends StatelessWidget {
  const _StockBreakdown({required this.product, required this.isStore});
  final Product product;
  final bool isStore;

  @override
  Widget build(BuildContext context) {
    final rows = [...product.warehouseStock, ...product.storeStock];
    if (rows.isEmpty) return const EmptyView(compact: true, icon: Icons.warehouse_outlined, title: 'No stock recorded yet');
    return Column(children: [
      for (final r in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(product.warehouseStock.contains(r) ? Icons.warehouse_outlined : Icons.storefront_outlined, size: 15, color: AppColors.textMuted),
            const SizedBox(width: Gap.sm),
            Expanded(child: Text(r.location.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
            if (r.damaged > 0) ...[Tag('${r.damaged} damaged', tone: Tone.danger), const SizedBox(width: Gap.sm)],
            Text('${r.available} avail.', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(width: Gap.sm),
            SizedBox(width: 56, child: Text('${r.quantity}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
          ]),
        ),
    ]);
  }
}
