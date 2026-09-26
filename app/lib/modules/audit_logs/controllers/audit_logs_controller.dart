import 'package:get/get.dart';

import '../../../core/base/paged_list_controller.dart';
import '../../../core/network/api_response.dart';
import '../../../core/utils/file_utils.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/platform.dart';
import '../../../data/repositories/repositories.dart';

class AuditLogsController extends PagedListController<AuditLogEntry> {
  AuditLogsController(this._repo) : super(tableId: 'audit_logs', initialSortBy: 'createdAt', initialSortAsc: false);
  final PlatformRepository _repo;

  final modules = <String>[].obs;
  final actions = <String>[].obs;
  final exporting = false.obs;

  @override
  void onInit() {
    super.onInit();
    _loadFacets();
  }

  Future<void> _loadFacets() async {
    try {
      final (m, a) = await _repo.auditFacets();
      modules.assignAll(m);
      actions.assignAll(a);
    } catch (_) {}
  }

  @override
  Future<PageResult<AuditLogEntry>> fetchPage(ListQuery query) => _repo.auditLogs(query);

  @override
  String idOf(AuditLogEntry item) => item.id;

  Future<void> export(String format) async {
    exporting.value = true;
    try {
      final file = await _repo.exportAudit(query, format);
      final saved = await FileUtils.saveDownload(file);
      if (saved != null) Toast.success('Exported to $saved');
    } catch (e) {
      Toast.fromError(e);
    } finally {
      exporting.value = false;
    }
  }
}
