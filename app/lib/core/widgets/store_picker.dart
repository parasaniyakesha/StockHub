import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/models/catalog.dart';
import 'dialogs.dart';
import 'state_views.dart';

/// Simple search-and-pick dialog for adding a store to a list.
Future<StoreModel?> pickStoreDialog(List<StoreModel> options, {Set<String> exclude = const {}}) {
  final visible = options.where((s) => !exclude.contains(s.id)).toList();
  final search = ''.obs;
  return Get.dialog<StoreModel>(
    AppDialog(
      title: 'Add store',
      width: 460,
      scrollable: false,
      child: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(autofocus: true, onChanged: (v) => search.value = v, decoration: const InputDecoration(hintText: 'Search stores…', prefixIcon: Icon(Icons.search, size: 18))),
          const SizedBox(height: 12),
          SizedBox(
            height: 320,
            child: Obx(() {
              final query = search.value.toLowerCase();
              final filtered = visible.where((s) => s.name.toLowerCase().contains(query) || s.code.toLowerCase().contains(query)).toList();
              if (filtered.isEmpty) return const EmptyView(compact: true, icon: Icons.storefront_outlined, title: 'No stores found');
              return ListView.separated(
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final s = filtered[i];
                  return ListTile(dense: true, title: Text(s.name, style: const TextStyle(fontSize: 13)), subtitle: Text(s.code, style: const TextStyle(fontSize: 11.5)), onTap: () => Get.back(result: s));
                },
              );
            }),
          ),
        ]),
      ),
    ),
  );
}
