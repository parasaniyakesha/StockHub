import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/session/auth_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/filter_bar.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../controllers/dashboard_controller.dart';
import '../widgets/dashboard_charts.dart';

class DashboardView extends GetView<DashboardController> {
  const DashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    Get.put(DashboardController(Get.find(), Get.find()));
    final auth = Get.find<AuthService>();
    return ShellPage(
      title: 'Dashboard',
      breadcrumb: 'Overview',
      headerActions: [
        Obx(() {
          if (!controller.isManager || controller.stores.isEmpty) return const SizedBox();
          return FilterDropdown<String>(
            label: 'Store',
            value: controller.storeFilter.value,
            items: controller.stores.map((s) => s.id).toList(),
            itemLabel: (id) => controller.stores.firstWhere((s) => s.id == id).name,
            allLabel: 'All my stores',
            onChanged: controller.setStore,
            width: 160,
          );
        }),
      ],
      child: Obx(() {
        if (controller.errorMessage.value != null && controller.data.value == null) {
          return ErrorView(message: controller.errorMessage.value!, onRetry: controller.load);
        }
        return RefreshIndicator(
          onRefresh: controller.load,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Welcome back, ${auth.current?.name.split(' ').first ?? ''}', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 2),
              Text('Here is what is happening across ${controller.isAdmin ? 'the company' : 'your stores'} today.', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: Gap.xl),
              _StatGrid(controller: controller),
              const SizedBox(height: Gap.xl),
              LayoutBuilder(builder: (context, c) {
                final wide = c.maxWidth > 900;
                final trend = SectionCard(
                  title: 'Sales trend',
                  subtitle: 'Last 30 days',
                  child: Obx(() => SalesTrendChart(points: controller.data.value?.salesTrend ?? const [], loading: controller.loading.value)),
                );
                final storeSales = SectionCard(
                  title: 'Store-wise sales',
                  subtitle: 'This month',
                  child: Obx(() => StoreSalesChart(data: controller.data.value?.storeSales ?? const [], loading: controller.loading.value)),
                );
                if (!wide) return Column(children: [trend, const SizedBox(height: Gap.lg), storeSales]);
                return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(flex: 3, child: trend), const SizedBox(width: Gap.lg), Expanded(flex: 2, child: storeSales)]));
              }),
              const SizedBox(height: Gap.lg),
              LayoutBuilder(builder: (context, c) {
                final wide = c.maxWidth > 900;
                final topProducts = SectionCard(
                  title: 'Top products',
                  subtitle: 'By quantity sold, last 30 days',
                  child: Obx(() => TopProductsChart(data: controller.data.value?.topProducts ?? const [], loading: controller.loading.value)),
                );
                final movement = SectionCard(
                  title: 'Stock movement',
                  subtitle: 'Last 14 days',
                  child: Obx(() => StockMovementChart(points: controller.data.value?.stockMovement ?? const [], loading: controller.loading.value)),
                );
                if (!wide) return Column(children: [topProducts, const SizedBox(height: Gap.lg), movement]);
                return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: topProducts), const SizedBox(width: Gap.lg), Expanded(child: movement)]));
              }),
              const SizedBox(height: Gap.lg),
              SectionCard(
                title: 'Low stock',
                subtitle: 'Products at or below their minimum level',
                child: Obx(() {
                  final rows = controller.data.value?.lowStock ?? const [];
                  if (controller.loading.value) return const Skeleton(height: 120);
                  if (rows.isEmpty) return const EmptyView(compact: true, icon: Icons.inventory_2_outlined, title: 'Nothing is low on stock', message: 'All products are above their minimum level.');
                  return Column(children: [
                    for (final r in rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          const StatusBadge('LOW', label: 'Low', dense: true),
                          const SizedBox(width: Gap.md),
                          Expanded(child: Text(r.name, style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          SizedBox(width: 90, child: Text(r.sku, style: const TextStyle(fontSize: 12, color: AppColors.textMuted))),
                          SizedBox(width: 110, child: Text(r.location, style: const TextStyle(fontSize: 12, color: AppColors.textMuted), overflow: TextOverflow.ellipsis)),
                          SizedBox(width: 90, child: Text('${r.quantity} / min ${r.minimumStock}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                        ]),
                      ),
                  ]);
                }),
              ),
            ]),
          ),
        );
      }),
    );
  }
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.controller});
  final DashboardController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final d = controller.data.value;
      final loading = controller.loading.value && d == null;
      final tiles = <Widget>[
        StatCard(label: 'Total stores', value: '${d?.card('totalStores') ?? 0}', icon: Icons.storefront_outlined, tone: Tone.primary, loading: loading),
        StatCard(label: 'Total products', value: '${d?.card('totalProducts') ?? 0}', icon: Icons.inventory_2_outlined, tone: Tone.info, loading: loading),
        StatCard(
          label: d?.has('warehouseStock') == true ? 'Warehouse stock' : 'Store stock',
          value: Fmt.number(d?.has('warehouseStock') == true ? d?.card('warehouseStock') : d?.card('storeStock')),
          icon: Icons.warehouse_outlined,
          tone: Tone.purple,
          loading: loading,
        ),
        StatCard(label: 'Low stock', value: '${d?.card('lowStock') ?? 0}', icon: Icons.warning_amber_outlined, tone: Tone.warning, loading: loading),
        StatCard(label: 'Pending requests', value: '${d?.card('pendingRequests') ?? 0}', icon: Icons.assignment_outlined, tone: Tone.info, loading: loading),
        StatCard(label: 'Pending packing orders', value: '${d?.card('pendingPackingOrders') ?? 0}', icon: Icons.local_shipping_outlined, tone: Tone.purple, loading: loading),
        StatCard(label: "Today's sales", value: Fmt.money(d?.money('todaySales')), caption: '${d?.card('todayInvoices') ?? 0} invoices', icon: Icons.today_outlined, tone: Tone.success, loading: loading),
        StatCard(label: 'Monthly sales', value: Fmt.money(d?.money('monthlySales')), caption: '${d?.card('monthlyInvoices') ?? 0} invoices', icon: Icons.calendar_month_outlined, tone: Tone.success, loading: loading),
      ];
      return LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth > 1200 ? 4 : c.maxWidth > 860 ? 3 : c.maxWidth > 560 ? 2 : 1;
        final width = (c.maxWidth - (cols - 1) * Gap.lg) / cols;
        return Wrap(spacing: Gap.lg, runSpacing: Gap.lg, children: [for (final t in tiles) SizedBox(width: width, child: t)]);
      });
    });
  }
}
