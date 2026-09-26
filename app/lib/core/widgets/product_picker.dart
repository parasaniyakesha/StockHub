import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../data/models/catalog.dart';
import '../../data/repositories/repositories.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';
import 'dialogs.dart';
import 'state_views.dart';

/// Search-and-pick dialog for adding a product line to a request, sale,
/// transfer, packing order or stock entry. [exclude] hides already-added ids.
Future<ProductBrief?> pickProductDialog({Set<String> exclude = const {}}) {
  return Get.dialog<ProductBrief>(
    AppDialog(title: 'Add product', width: 520, scrollable: false, child: _ProductPicker(exclude: exclude)),
  );
}

class _ProductPicker extends StatefulWidget {
  const _ProductPicker({required this.exclude});
  final Set<String> exclude;

  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  final _controller = TextEditingController();
  List<Product> _results = const [];
  bool _loading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(value));
  }

  Future<void> _search(String value) async {
    setState(() => _loading = true);
    try {
      final res = await Get.find<ProductRepository>().search(value, limit: 30);
      if (mounted) setState(() => _results = res);
    } catch (_) {
      if (mounted) setState(() => _results = const []);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _results.where((p) => !widget.exclude.contains(p.id)).toList();
    return SizedBox(
      width: 480,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _controller,
          autofocus: true,
          onChanged: _onChanged,
          decoration: const InputDecoration(hintText: 'Search by name, SKU or barcode…', prefixIcon: Icon(Icons.search, size: 18)),
        ),
        const SizedBox(height: Gap.md),
        SizedBox(
          height: 360,
          child: _loading
              ? const LoadingView()
              : visible.isEmpty
                  ? const EmptyView(compact: true, icon: Icons.search_off_outlined, title: 'No products found')
                  : ListView.separated(
                      itemCount: visible.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final p = visible[i];
                        return ListTile(
                          dense: true,
                          title: Text(p.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                          subtitle: Text('${p.sku}${p.category != null ? ' · ${p.category!.name}' : ''}', style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted)),
                          trailing: Text(Fmt.money(p.sellingPrice), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          onTap: () => Get.back(result: p.brief),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
