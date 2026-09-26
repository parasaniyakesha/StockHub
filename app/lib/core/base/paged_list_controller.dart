import 'package:get/get.dart';

import '../constants/app_config.dart';
import '../network/api_exception.dart';
import '../network/api_response.dart';
import '../storage/preferences.dart';
import 'view_state.dart';

/// Base controller for every server-paginated table.
///
/// Subclasses implement [fetchPage] (usually a single repository call) and
/// [idOf]. Search is debounced, filters/sort reset to page 1, stale responses
/// from superseded requests are ignored, and the current page is kept while
/// refreshing so the table does not flash.
abstract class PagedListController<T> extends GetxController {
  PagedListController({this.tableId, String? initialSortBy, bool initialSortAsc = false}) {
    sortBy.value = initialSortBy;
    sortAsc.value = initialSortAsc;
    final saved = tableId == null ? null : Preferences.pageSize(tableId!);
    if (saved != null) limit.value = saved;
  }

  /// Used to persist page size / column visibility per table.
  final String? tableId;

  final items = <T>[].obs;
  final state = ViewState.loading.obs;
  final errorMessage = ''.obs;

  /// True while re-fetching with rows already on screen.
  final refreshing = false.obs;

  final page = 1.obs;
  final limit = AppConfig.defaultPageSize.obs;
  final total = 0.obs;
  final totalPages = 0.obs;

  final search = ''.obs;
  final filters = <String, Object?>{}.obs;
  final sortBy = RxnString();
  final sortAsc = false.obs;

  final selectedIds = <String>{}.obs;

  /// Extra top-level fields from the last response (e.g. `summary`).
  final extra = <String, dynamic>{}.obs;

  int _requestSeq = 0;
  bool loadOnInit = true;

  Future<PageResult<T>> fetchPage(ListQuery query);
  String idOf(T item);

  ListQuery get query => ListQuery(
        page: page.value,
        limit: limit.value,
        search: search.value,
        sortBy: sortBy.value,
        sortOrder: sortBy.value == null ? null : (sortAsc.value ? 'asc' : 'desc'),
        filters: Map.of(filters),
      );

  @override
  void onInit() {
    super.onInit();
    debounce<String>(search, (_) {
      page.value = 1;
      load();
    }, time: const Duration(milliseconds: 350));
    if (loadOnInit) load();
  }

  Future<void> load() async {
    final seq = ++_requestSeq;
    if (items.isEmpty) {
      state.value = ViewState.loading;
    } else {
      refreshing.value = true;
    }
    try {
      final result = await fetchPage(query);
      if (seq != _requestSeq) return; // a newer request superseded this one
      items.assignAll(result.items);
      total.value = result.pagination.total;
      totalPages.value = result.pagination.totalPages;
      extra.assignAll(result.extra);
      // Deleted/filtered-out rows must not stay selected.
      selectedIds.removeWhere((id) => !result.items.any((i) => idOf(i) == id));
      // Page emptied (e.g. after deleting the last row) → step back.
      if (result.items.isEmpty && page.value > 1 && result.pagination.total > 0) {
        page.value = page.value - 1;
        return load();
      }
      state.value = result.items.isEmpty ? ViewState.empty : ViewState.success;
    } catch (e) {
      if (seq != _requestSeq) return;
      errorMessage.value = AppException.from(e).message;
      if (items.isEmpty) state.value = ViewState.error;
      onLoadError(AppException.from(e));
    } finally {
      if (seq == _requestSeq) refreshing.value = false;
    }
  }

  /// Hook: when a refresh fails while rows are shown (e.g. show a toast).
  void onLoadError(AppException error) {}

  Future<void> reload() => load();

  void setSearch(String value) => search.value = value;

  void setFilter(String key, Object? value) {
    if (value == null || (value is String && value.isEmpty)) {
      filters.remove(key);
    } else {
      filters[key] = value;
    }
    page.value = 1;
    load();
  }

  void setFilters(Map<String, Object?> values) {
    values.forEach((key, value) {
      if (value == null || (value is String && value.isEmpty)) {
        filters.remove(key);
      } else {
        filters[key] = value;
      }
    });
    page.value = 1;
    load();
  }

  void clearFilters() {
    filters.clear();
    search.value = '';
    page.value = 1;
    load();
  }

  bool get hasActiveFilters => filters.isNotEmpty || search.value.isNotEmpty;

  /// Toggles descending → ascending → descending on the same column.
  void sort(String key) {
    if (sortBy.value == key) {
      sortAsc.value = !sortAsc.value;
    } else {
      sortBy.value = key;
      sortAsc.value = true;
    }
    page.value = 1;
    load();
  }

  void goToPage(int p) {
    if (p < 1 || (totalPages.value > 0 && p > totalPages.value) || p == page.value) return;
    page.value = p;
    load();
  }

  void setLimit(int value) {
    limit.value = value;
    if (tableId != null) Preferences.setPageSize(tableId!, value);
    page.value = 1;
    load();
  }

  // ─── Selection ───
  bool isSelected(T item) => selectedIds.contains(idOf(item));

  void toggleSelected(T item) {
    final id = idOf(item);
    selectedIds.contains(id) ? selectedIds.remove(id) : selectedIds.add(id);
  }

  bool get allOnPageSelected => items.isNotEmpty && items.every(isSelected);

  void toggleSelectAllOnPage() {
    if (allOnPageSelected) {
      selectedIds.removeAll(items.map(idOf));
    } else {
      selectedIds.addAll(items.map(idOf));
    }
  }

  void clearSelection() => selectedIds.clear();

  List<T> get selectedItems => items.where(isSelected).toList();
}
