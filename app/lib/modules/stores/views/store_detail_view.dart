import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_shell.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/toast.dart';
import '../controllers/store_detail_controller.dart';
import '../widgets/store_form_dialog.dart';

class StoreDetailView extends StatelessWidget {
  const StoreDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    final id = Get.parameters['id']!;
    final reused = Get.isRegistered<StoreDetailController>(tag: id);
    final c = Get.put(StoreDetailController(Get.find(), Get.find(), id), tag: id);
    if (reused) c.load();
    return ShellPage(
      title: 'Store details',
      breadcrumb: 'Catalog / Stores',
      headerActions: [
        Obx(() {
          final s = c.store.value;
          if (s == null) return const SizedBox();
          return OutlinedButton.icon(
            onPressed: () async {
              final saved = await showStoreFormDialog(store: s, managers: c.managers);
              if (saved) {
                Toast.success('Store updated');
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
          final s = c.store.value!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(Radii.md)),
                  child: const Icon(Icons.storefront_outlined, size: 28, color: AppColors.primary),
                ),
                const SizedBox(width: Gap.lg),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(s.name, style: Theme.of(context).textTheme.headlineSmall, overflow: TextOverflow.ellipsis)),
                      const SizedBox(width: Gap.sm),
                      StatusBadge(s.status),
                    ]),
                    const SizedBox(height: 4),
                    Text('Code ${s.code}${s.city != null ? ' · ${s.city}' : ''}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  ]),
                ),
              ]),
              const SizedBox(height: Gap.xl),
              SectionCard(
                title: 'Store information',
                child: InfoGrid(items: [
                  ('Address', infoText(s.address)),
                  ('Phone', infoText(s.phone)),
                  ('Email', infoText(s.email)),
                  ('Contact person', infoText(s.contactPerson)),
                  ('Manager', infoText(s.manager?.name)),
                  ('Created', infoText(Fmt.date(s.createdAt))),
                ]),
              ),
              const SizedBox(height: Gap.lg),
              SectionCard(
                title: 'Store users',
                subtitle: '${s.users.length} user(s)',
                child: s.users.isEmpty
                    ? const EmptyView(compact: true, icon: Icons.people_outline, title: 'No users assigned yet')
                    : Column(children: [
                        for (final u in s.users)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(children: [
                              InitialsAvatar(Fmt.initials(u.name), size: 28),
                              const SizedBox(width: Gap.sm),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(u.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                  Text(u.email, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                                ]),
                              ),
                              Text(Fmt.relative(u.lastLoginAt), style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                              const SizedBox(width: Gap.md),
                              StatusBadge(u.status, dense: true),
                            ]),
                          ),
                      ]),
              ),
            ]),
          );
        },
      ),
    );
  }
}
