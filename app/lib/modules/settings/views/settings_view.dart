import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/session/auth_service.dart';
import '../../../core/session/settings_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/form_fields.dart';
import '../controllers/settings_page_controller.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(SettingsPageController(Get.find()));
    final auth = Get.find<AuthService>();
    return ShellPage(
      title: 'Settings',
      breadcrumb: 'Administration',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Gap.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SectionCard(
              title: 'Your profile',
              child: Form(
                key: c.profileFormKey,
                child: FormColumn(children: [
                  FieldRow(children: [
                    AppTextField(label: 'Full name', controller: c.nameController, required: true, validator: V.required('Name')),
                    AppTextField(label: 'Phone', controller: c.phoneController, validator: V.phone),
                  ]),
                  Obx(() => Text(auth.current?.email ?? '', style: Theme.of(context).textTheme.bodySmall)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Obx(() => FilledButton(
                          onPressed: c.savingProfile.value ? null : c.saveProfile,
                          child: c.savingProfile.value ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save profile'),
                        )),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: Gap.lg),
            SectionCard(
              title: 'Change password',
              child: Form(
                key: c.passwordFormKey,
                child: FormColumn(children: [
                  AppTextField(label: 'Current password', controller: c.currentPasswordController, required: true, obscure: true, validator: V.required('Current password')),
                  AppTextField(label: 'New password', controller: c.newPasswordController, required: true, obscure: true, validator: V.password),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Obx(() => FilledButton(
                          onPressed: c.changingPassword.value ? null : c.changePassword,
                          child: c.changingPassword.value ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Change password'),
                        )),
                  ),
                ]),
              ),
            ),
            if (c.isAdmin) ...[
              const SizedBox(height: Gap.lg),
              _CompanySettingsCard(c: c),
            ],
            const SizedBox(height: Gap.lg),
            SectionCard(
              title: 'Session',
              child: Row(children: [
                const Expanded(child: Text('Sign out of your account on this device.', style: TextStyle(fontSize: 13))),
                OutlinedButton(onPressed: confirmLogout, child: const Text('Sign out')),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _CompanySettingsCard extends StatefulWidget {
  const _CompanySettingsCard({required this.c});
  final SettingsPageController c;

  @override
  State<_CompanySettingsCard> createState() => _CompanySettingsCardState();
}

class _CompanySettingsCardState extends State<_CompanySettingsCard> {
  late final settings = Get.find<SettingsService>().settings.value;
  late final companyNameController = TextEditingController(text: settings.companyName);
  late final currencyCodeController = TextEditingController(text: settings.currencyCode);
  late final currencySymbolController = TextEditingController(text: settings.currencySymbol);
  late final invoicePrefixController = TextEditingController(text: settings.invoicePrefix);
  late bool allowNegativeStock = settings.allowNegativeStock;
  late bool lowStockAlerts = settings.lowStockAlerts;
  late bool allowPriceOverride = settings.allowPriceOverride;

  @override
  void dispose() {
    companyNameController.dispose();
    currencyCodeController.dispose();
    currencySymbolController.dispose();
    invoicePrefixController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Company settings',
      subtitle: 'Affects invoice numbering, currency display and stock rules company-wide.',
      child: FormColumn(children: [
        FieldRow(children: [
          AppTextField(label: 'Company name', controller: companyNameController),
          AppTextField(label: 'Invoice prefix', controller: invoicePrefixController, maxLength: 10),
        ]),
        FieldRow(children: [
          AppTextField(label: 'Currency code', controller: currencyCodeController, maxLength: 3),
          AppTextField(label: 'Currency symbol', controller: currencySymbolController, maxLength: 5),
        ]),
        SwitchRow(title: 'Allow negative stock', subtitle: 'Permit stock adjustments to drive balances below zero', value: allowNegativeStock, onChanged: (v) => setState(() => allowNegativeStock = v)),
        SwitchRow(title: 'Low stock alerts', subtitle: 'Notify admins and managers when stock crosses the minimum', value: lowStockAlerts, onChanged: (v) => setState(() => lowStockAlerts = v)),
        SwitchRow(title: 'Allow price override', subtitle: 'Let store users change the selling price on a sale', value: allowPriceOverride, onChanged: (v) => setState(() => allowPriceOverride = v)),
        Align(
          alignment: Alignment.centerRight,
          child: Obx(() => FilledButton(
                onPressed: widget.c.companySaving.value
                    ? null
                    : () => widget.c.saveCompanySettings({
                          'companyName': companyNameController.text.trim(),
                          'currencyCode': currencyCodeController.text.trim(),
                          'currencySymbol': currencySymbolController.text.trim(),
                          'invoicePrefix': invoicePrefixController.text.trim(),
                          'allowNegativeStock': allowNegativeStock,
                          'lowStockAlerts': lowStockAlerts,
                          'allowPriceOverride': allowPriceOverride,
                        }),
                child: widget.c.companySaving.value ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Save settings'),
              )),
        ),
      ]),
    );
  }
}
