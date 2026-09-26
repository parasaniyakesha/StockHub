import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/operations.dart';
import '../controllers/packing_detail_controller.dart';
import '../widgets/packing_line_dialogs.dart';

class PackingDetailView extends StatelessWidget {
  const PackingDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    final id = Get.parameters['id']!;
    final reused = Get.isRegistered<PackingDetailController>(tag: id);
    final c = Get.put(PackingDetailController(Get.find(), id), tag: id);
    if (reused) c.load();
    return ShellPage(
      title: 'Packing order',
      breadcrumb: 'Operations / Packing',
      headerActions: [Obx(() => c.order.value == null ? const SizedBox() : _Actions(c: c))],
      child: StateSwitcher(
        state: c.state,
        onRetry: c.load,
        error: c.errorMessage.value,
        builder: () {
          final o = c.order.value!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(o.orderNumber, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(width: Gap.sm),
                StatusBadge(o.status),
              ]),
              const SizedBox(height: 4),
              Text('${o.warehouse?.name ?? ''} · Created ${Fmt.dateTime(o.createdAt)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: Gap.xl),
              SectionCard(
                title: 'Planned products',
                padding: EdgeInsets.zero,
                child: Column(children: [
                  Container(
                    color: AppColors.surfaceMuted,
                    padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 8),
                    child: const Row(children: [
                      Expanded(flex: 3, child: Text('Product', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      SizedBox(width: 70, child: Text('Planned', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      SizedBox(width: 70, child: Text('Alloc.', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      SizedBox(width: 70, child: Text('Packed', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      SizedBox(width: 70, child: Text('Dispatched', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      SizedBox(width: 70, child: Text('Received', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                    ]),
                  ),
                  for (final item in o.items) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 8),
                      child: Row(children: [
                        Expanded(flex: 3, child: Text(item.product.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                        SizedBox(width: 70, child: Text('${item.quantity}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5))),
                        SizedBox(width: 70, child: Text('${item.allocatedQuantity}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5))),
                        SizedBox(width: 70, child: Text('${item.packedQuantity}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5))),
                        SizedBox(width: 70, child: Text('${item.dispatchedQuantity}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5))),
                        SizedBox(width: 70, child: Text('${item.receivedQuantity}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                      ]),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: Gap.lg),
              for (final store in o.stores) ...[
                _StoreSection(controller: c, store: store),
                const SizedBox(height: Gap.lg),
              ],
              if (o.notes != null && o.notes!.isNotEmpty) SectionCard(title: 'Notes', child: Text(o.notes!, style: const TextStyle(fontSize: 13, height: 1.4))),
            ]),
          );
        },
      ),
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.c});
  final PackingDetailController c;

  @override
  Widget build(BuildContext context) {
    final o = c.order.value!;
    final busy = c.acting.value;
    final buttons = <Widget>[];

    if (o.status == PackingStatus.draft && c.canManage) {
      buttons.add(OutlinedButton(onPressed: () => Get.toNamed(AppRoutes.editPackingOrder(o.id), arguments: o), child: const Text('Edit')));
      buttons.add(FilledButton(onPressed: busy ? null : c.assign, child: const Text('Assign')));
    }
    if (o.status == PackingStatus.assigned && c.canManage) {
      buttons.add(FilledButton(onPressed: busy ? null : c.startPacking, child: const Text('Start packing')));
    }
    if ((o.status == PackingStatus.assigned || o.status == PackingStatus.packing) && c.canManage) {
      buttons.add(FilledButton(
        onPressed: busy
            ? null
            : () async {
                final lines = await showPackDialog(o);
                if (lines != null) c.pack(lines);
              },
        child: const Text('Record packing'),
      ));
    }
    if (o.status == PackingStatus.packed && c.canManage) {
      buttons.add(FilledButton(onPressed: busy ? null : c.dispatch, child: const Text('Dispatch')));
    }
    if (o.status == PackingStatus.received && c.canManage) {
      buttons.add(FilledButton(onPressed: busy ? null : c.complete, child: const Text('Close order')));
    }
    if ([PackingStatus.draft, PackingStatus.assigned, PackingStatus.packing, PackingStatus.packed].contains(o.status) && c.canManage) {
      buttons.add(TextButton(onPressed: busy ? null : c.cancel, child: const Text('Cancel order', style: TextStyle(color: AppColors.danger))));
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < buttons.length; i++) ...[if (i > 0) const SizedBox(width: Gap.sm), buttons[i]]]);
  }
}

class _StoreSection extends StatelessWidget {
  const _StoreSection({required this.controller, required this.store});
  final PackingDetailController controller;
  final PackingStore store;

  @override
  Widget build(BuildContext context) {
    final canReceiveThis = controller.canReceive && (controller.isAdmin || controller.myStoreId == store.storeId) && store.status == 'DISPATCHED';
    return SectionCard(
      title: store.store.name,
      subtitle: 'Status: ${store.status.toLowerCase()}${store.request != null ? ' · From request ${store.request!.name}' : ''}',
      actions: [
        if (canReceiveThis)
          FilledButton(
            onPressed: () async {
              final lines = await showReceiveDialog(store);
              if (lines != null) controller.receive(lines);
            },
            child: const Text('Receive'),
          ),
      ],
      padding: EdgeInsets.zero,
      child: Column(children: [
        for (var i = 0; i < store.lines.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 8),
            child: Row(children: [
              Expanded(child: Text(store.lines[i].product.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
              Text('Alloc. ${store.lines[i].allocatedQuantity}', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              const SizedBox(width: Gap.md),
              Text('Dispatched ${store.lines[i].dispatchedQuantity}', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
              const SizedBox(width: Gap.md),
              Text('Received ${store.lines[i].receivedQuantity}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              if (store.lines[i].damagedQuantity > 0) ...[const SizedBox(width: Gap.sm), Tag('${store.lines[i].damagedQuantity} damaged', tone: Tone.danger)],
              if (store.lines[i].shortQuantity > 0) ...[const SizedBox(width: Gap.sm), Tag('${store.lines[i].shortQuantity} short', tone: Tone.warning)],
            ]),
          ),
        ],
      ]),
    );
  }
}
