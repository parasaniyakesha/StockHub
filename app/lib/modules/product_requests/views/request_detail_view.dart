import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../data/models/operations.dart';
import '../controllers/request_detail_controller.dart';

class RequestDetailView extends StatelessWidget {
  const RequestDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    final id = Get.parameters['id']!;
    final reused = Get.isRegistered<RequestDetailController>(tag: id);
    final c = Get.put(RequestDetailController(Get.find(), id), tag: id);
    if (reused) c.load();
    return ShellPage(
      title: 'Product request',
      breadcrumb: 'Operations / Requests',
      headerActions: [
        Obx(() {
          final r = c.request.value;
          if (r == null) return const SizedBox();
          return Row(mainAxisSize: MainAxisSize.min, children: [
            if (r.isDraft && c.canCreate) ...[
              OutlinedButton(onPressed: () => Get.toNamed(AppRoutes.editRequest(r.id), arguments: r), child: const Text('Edit')),
              const SizedBox(width: Gap.sm),
              FilledButton(onPressed: c.acting.value ? null : c.submit, child: const Text('Submit')),
            ],
            if (r.isReviewable && c.canApprove) ...[
              if (r.status == RequestStatus.submitted) OutlinedButton(onPressed: c.acting.value ? null : c.startReview, child: const Text('Start review')),
              const SizedBox(width: Gap.sm),
              OutlinedButton(
                onPressed: c.acting.value ? null : c.reject,
                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)),
                child: const Text('Reject'),
              ),
              const SizedBox(width: Gap.sm),
              FilledButton(onPressed: c.acting.value ? null : () => c.approve(null), child: const Text('Approve')),
            ],
            if ((r.isDraft || r.status == RequestStatus.submitted) && (c.canCreate || c.canApprove)) ...[
              const SizedBox(width: Gap.sm),
              TextButton(onPressed: c.acting.value ? null : c.cancel, child: const Text('Cancel request', style: TextStyle(color: AppColors.danger))),
            ],
          ]);
        }),
      ],
      child: StateSwitcher(
        state: c.state,
        onRetry: c.load,
        error: c.errorMessage.value,
        builder: () {
          final r = c.request.value!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(r.requestNumber, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(width: Gap.sm),
                StatusBadge(r.status),
              ]),
              const SizedBox(height: 4),
              Text('${r.store.name} · Created ${Fmt.dateTime(r.createdAt)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              const SizedBox(height: Gap.xl),
              if (r.reviewNotes != null && r.reviewNotes!.isNotEmpty)
                Padding(padding: const EdgeInsets.only(bottom: Gap.lg), child: InfoBanner(message: r.reviewNotes!, tone: r.status == RequestStatus.rejected ? Tone.danger : Tone.info, icon: Icons.comment_outlined)),
              SectionCard(
                title: 'Requested products',
                subtitle: r.isReviewable && c.canApprove ? 'Enter the approved quantity for each product before approving.' : null,
                padding: EdgeInsets.zero,
                child: _ItemsTable(request: r, controller: c),
              ),
              if (r.packingOrders.isNotEmpty) ...[
                const SizedBox(height: Gap.lg),
                SectionCard(
                  title: 'Linked packing orders',
                  child: Column(children: [
                    for (final po in r.packingOrders)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(po.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        trailing: StatusBadge(po.code ?? ''),
                        onTap: () => Get.toNamed(AppRoutes.packingOrder(po.id)),
                      ),
                  ]),
                ),
              ],
              if (r.notes != null && r.notes!.isNotEmpty) ...[
                const SizedBox(height: Gap.lg),
                SectionCard(title: 'Notes', child: Text(r.notes!, style: const TextStyle(fontSize: 13, height: 1.4))),
              ],
            ]),
          );
        },
      ),
    );
  }
}

class _ItemsTable extends StatelessWidget {
  const _ItemsTable({required this.request, required this.controller});
  final ProductRequest request;
  final RequestDetailController controller;

  @override
  Widget build(BuildContext context) {
    final editable = request.isReviewable && controller.canApprove;
    return Column(children: [
      Container(
        color: AppColors.surfaceMuted,
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 10),
        child: Row(children: [
          const Expanded(flex: 3, child: Text('Product', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
          const SizedBox(width: 90, child: Text('Requested', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
          SizedBox(width: editable ? 110 : 90, child: Text(editable ? 'Approve qty' : 'Approved', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
          if (!editable) const SizedBox(width: 90, child: Text('Received', textAlign: TextAlign.right, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
        ]),
      ),
      const Divider(height: 1),
      for (final item in request.items) ...[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.lg, vertical: 10),
          child: Row(children: [
            Expanded(
              flex: 3,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(item.product.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(item.product.sku, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ]),
            ),
            SizedBox(width: 90, child: Text('${item.requestedQuantity}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
            SizedBox(
              width: editable ? 110 : 90,
              child: editable
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: Obx(() => QuantityInput(
                            value: controller.approvals[item.id] ?? 0,
                            max: item.requestedQuantity,
                            onChanged: (v) => controller.approvals[item.id] = v,
                          )),
                    )
                  : Text(item.approvedQuantity == null ? '—' : '${item.approvedQuantity}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            if (!editable) SizedBox(width: 90, child: Text('${item.receivedQuantity}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: AppColors.textMuted))),
          ]),
        ),
        const Divider(height: 1),
      ],
    ]);
  }
}
