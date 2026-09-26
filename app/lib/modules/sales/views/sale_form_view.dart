import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/form_fields.dart';
import '../../../core/widgets/product_picker.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/sales.dart';
import '../controllers/sale_form_controller.dart';

class SaleFormView extends StatelessWidget {
  const SaleFormView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(SaleFormController(Get.find(), Get.find()));
    return ShellPage(
      title: 'New sale',
      breadcrumb: 'Sales',
      child: Obx(() {
        if (c.loading.value) return const LoadingView();
        return SingleChildScrollView(
          padding: const EdgeInsets.all(Gap.xl),
          child: LayoutBuilder(builder: (context, cst) {
            final wide = cst.maxWidth > 900;
            final left = SectionCard(
              title: 'Products',
              actions: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await pickProductDialog(exclude: c.lines.map((l) => l.product.id).toSet());
                    if (picked != null) c.addLine(picked);
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add product'),
                ),
              ],
              child: Obx(() {
                c.lines.length; // subscribe to the RxList so add/remove/edit rebuilds this table
                return _LinesTable(c: c);
              }),
            );
            final right = SectionCard(
              title: 'Sale details',
              child: FormColumn(children: [
                if (!c.isStore)
                  Obx(() => AppDropdownField<String>(label: 'Store', required: true, value: c.storeId.value, items: c.stores.map((s) => s.id).toList(), itemLabel: (id) => c.stores.firstWhere((s) => s.id == id).name, onChanged: (v) => c.storeId.value = v)),
                AppTextField(label: 'Customer name (optional)', onChanged: (v) => c.customerName.value = v),
                AppTextField(label: 'Customer phone (optional)', keyboardType: TextInputType.phone, onChanged: (v) => c.customerPhone.value = v),
                Obx(() => AppDropdownField<String>(label: 'Payment method', required: true, value: c.paymentMethod.value, items: PaymentMethods.all, onChanged: (v) => c.paymentMethod.value = v ?? 'CASH')),
                AppTextField(label: 'Overall discount', keyboardType: TextInputType.number, inputFormatters: Formatters.decimal, onChanged: (v) => c.discount.value = double.tryParse(v) ?? 0),
                AppTextField(label: 'Notes (optional)', maxLines: 2, onChanged: (v) => c.notes.value = v),
                const Divider(),
                Obx(() {
                  c.lines.length;
                  c.discount.value; // both feed _Totals' computed subtotal/tax/grandTotal
                  return _Totals(c: c);
                }),
                const SizedBox(height: Gap.lg),
                Obx(() => FilledButton(
                      onPressed: c.saving.value
                          ? null
                          : () async {
                              final sale = await c.submit();
                              if (sale != null) {
                                Toast.success('Sale recorded: ${sale.invoiceNumber}');
                                Get.offNamed(AppRoutes.sale(sale.id));
                              }
                            },
                      child: c.saving.value ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Complete sale'),
                    )),
              ]),
            );
            if (!wide) return Column(children: [left, const SizedBox(height: Gap.lg), right]);
            return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(flex: 3, child: left), const SizedBox(width: Gap.lg), SizedBox(width: 340, child: right)]));
          }),
        );
      }),
    );
  }
}

class _LinesTable extends StatelessWidget {
  const _LinesTable({required this.c});
  final SaleFormController c;

  @override
  Widget build(BuildContext context) {
    if (c.lines.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(Gap.xl),
        decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(Radii.md)),
        child: const Center(child: Text('Add products to this sale.', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted))),
      );
    }
    return Container(
      decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(Radii.md)),
      child: Column(children: [
        Container(
          color: AppColors.surfaceMuted,
          padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 8),
          child: const Row(children: [
            Expanded(flex: 3, child: Text('Product', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
            SizedBox(width: 70, child: Text('Qty', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
            SizedBox(width: 90, child: Text('Price', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
            SizedBox(width: 70, child: Text('Disc.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
            SizedBox(width: 90, child: Text('Total', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
            SizedBox(width: 32),
          ]),
        ),
        for (var i = 0; i < c.lines.length; i++) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md, vertical: 6),
            child: Row(children: [
              Expanded(
                flex: 3,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.lines[i].product.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(c.lines[i].product.sku, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ]),
              ),
              SizedBox(
                width: 70,
                child: QuantityInput(
                  value: c.lines[i].quantity,
                  width: 60,
                  onChanged: (v) {
                    c.lines[i].quantity = v;
                    c.lines.refresh();
                  },
                ),
              ),
              SizedBox(
                width: 90,
                child: TextFormField(
                  enabled: c.allowPriceOverride,
                  initialValue: c.lines[i].unitPrice.toStringAsFixed(2),
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.number,
                  inputFormatters: Formatters.decimal,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                  onChanged: (v) {
                    c.lines[i].unitPrice = double.tryParse(v) ?? c.lines[i].unitPrice;
                    c.lines.refresh();
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 70,
                child: TextFormField(
                  initialValue: c.lines[i].discount.toStringAsFixed(0),
                  textAlign: TextAlign.right,
                  keyboardType: TextInputType.number,
                  inputFormatters: Formatters.decimal,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                  onChanged: (v) {
                    c.lines[i].discount = double.tryParse(v) ?? 0;
                    c.lines.refresh();
                  },
                ),
              ),
              SizedBox(width: 90, child: Text(Fmt.money(c.lines[i].total), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700))),
              SizedBox(width: 32, child: IconButton(icon: const Icon(Icons.close, size: 16), onPressed: () => c.removeLine(i))),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.c});
  final SaleFormController c;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text(label, style: TextStyle(fontSize: bold ? 14 : 12.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: bold ? AppColors.textPrimary : AppColors.textSecondary)),
            Text(value, style: TextStyle(fontSize: bold ? 15 : 12.5, fontWeight: FontWeight.w700, color: bold ? AppColors.primary : AppColors.textPrimary)),
          ]),
        );
    return Column(children: [
      row('Subtotal', Fmt.money(c.subtotal)),
      row('Tax', Fmt.money(c.tax)),
      row('Discount', '- ${Fmt.money(c.discount.value)}'),
      row('Grand total', Fmt.money(c.grandTotal), bold: true),
    ]);
  }
}
