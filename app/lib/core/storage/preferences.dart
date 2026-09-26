import 'package:get_storage/get_storage.dart';

/// Non-sensitive UI preferences (sidebar state, table column visibility, page size).
class Preferences {
  Preferences._();

  static final GetStorage _box = GetStorage('stockhub_prefs');

  static Future<void> init() => GetStorage.init('stockhub_prefs');

  static bool get sidebarCollapsed => _box.read<bool>('sidebarCollapsed') ?? false;
  static set sidebarCollapsed(bool v) => _box.write('sidebarCollapsed', v);

  static String? get lastEmail => _box.read<String>('lastEmail');
  static set lastEmail(String? v) => v == null ? _box.remove('lastEmail') : _box.write('lastEmail', v);

  static List<String>? hiddenColumns(String tableId) => (_box.read<List>('cols.$tableId'))?.cast<String>();
  static void setHiddenColumns(String tableId, List<String> ids) => _box.write('cols.$tableId', ids);

  static int? pageSize(String tableId) => _box.read<int>('pageSize.$tableId');
  static void setPageSize(String tableId, int v) => _box.write('pageSize.$tableId', v);
}
