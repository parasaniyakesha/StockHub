import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../core/constants/permissions.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/user.dart';

/// Multi-select store assignment for a manager. Returns the new list, or null if cancelled.
Future<List<String>?> showAssignStoresDialog(AppUser manager, List<StoreModel> allStores) async {
  final selected = manager.managedStores.map((s) => s.id).toSet().obs;
  final result = await Get.dialog<bool>(
    AppDialog(
      title: 'Assign stores to ${manager.name}',
      width: 480,
      actions: [
        OutlinedButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Get.back(result: true), child: const Text('Save')),
      ],
      child: allStores.isEmpty
          ? const Padding(padding: EdgeInsets.all(16), child: Text('No stores exist yet.', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)))
          : Obx(() {
              selected.length; // force an Rx read even if allStores is ever empty
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final store in allStores)
                    CheckboxListTile(
                      dense: true,
                      value: selected.contains(store.id),
                      onChanged: (v) => v == true ? selected.add(store.id) : selected.remove(store.id),
                      title: Text(store.name, style: const TextStyle(fontSize: 13)),
                      subtitle: Text(store.code, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                    ),
                ],
              );
            }),
    ),
  );
  return result == true ? selected.toList() : null;
}

/// Manager permission editor. Returns the new list, or null if cancelled.
Future<List<String>?> showManagerPermissionsDialog(AppUser manager) async {
  final selected = manager.permissions.toSet().obs;
  final result = await Get.dialog<bool>(
    AppDialog(
      title: 'Permissions for ${manager.name}',
      subtitle: 'Controls what this manager can do within their assigned stores.',
      width: 480,
      actions: [
        OutlinedButton(onPressed: () => Get.back(result: false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Get.back(result: true), child: const Text('Save')),
      ],
      child: Obx(() {
        selected.length; // force an Rx read - Perm.labels is non-empty but this stays correct if that ever changes
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in Perm.labels.entries)
              CheckboxListTile(
                dense: true,
                value: selected.contains(entry.key),
                onChanged: (v) => v == true ? selected.add(entry.key) : selected.remove(entry.key),
                title: Text(entry.value, style: const TextStyle(fontSize: 13)),
              ),
          ],
        );
      }),
    ),
  );
  return result == true ? selected.toList() : null;
}
