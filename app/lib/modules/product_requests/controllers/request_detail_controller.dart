import 'package:get/get.dart';

import '../../../core/base/view_state.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/auth_service.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/operations.dart';
import '../../../data/repositories/repositories.dart';

class RequestDetailController extends GetxController {
  RequestDetailController(this._repo, this.requestId);
  final RequestRepository _repo;
  final String requestId;

  final state = ViewState.loading.obs;
  final errorMessage = ''.obs;
  final request = Rxn<ProductRequest>();
  final acting = false.obs;

  /// itemId -> approved quantity, edited inline during review.
  final approvals = <String, int>{}.obs;

  bool get isStoreUser => Get.find<AuthService>().isStore;
  bool get canApprove => Get.find<AuthService>().can('requests.approve');
  bool get canCreate => Get.find<AuthService>().can('requests.create');

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    state.value = ViewState.loading;
    try {
      final r = await _repo.get(requestId);
      request.value = r;
      approvals.assignAll({for (final i in r.items) i.id: i.approvedQuantity ?? i.requestedQuantity});
      state.value = ViewState.success;
    } catch (e) {
      errorMessage.value = AppException.from(e).message;
      state.value = ViewState.error;
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    acting.value = true;
    try {
      await action();
      await load();
    } catch (e) {
      Toast.error(AppException.from(e).detailedMessage);
    } finally {
      acting.value = false;
    }
  }

  Future<void> submit() => _run(() async {
        await _repo.submit(requestId);
        Toast.success('Request submitted');
      });

  Future<void> startReview() => _run(() async {
        await _repo.startReview(requestId);
      });

  Future<void> approve(String? reviewNotes) => _run(() async {
        await _repo.approve(requestId, Map.of(approvals), reviewNotes: reviewNotes);
        Toast.success('Request approved');
      });

  Future<void> reject() async {
    final reason = await reasonDialog(title: 'Reject request', message: 'Explain why this request is being rejected. The store will be notified.', confirmLabel: 'Reject', destructive: true);
    if (reason == null) return;
    await _run(() async {
      await _repo.reject(requestId, reason);
      Toast.success('Request rejected');
    });
  }

  Future<void> cancel() async {
    if (!await confirmDialog(title: 'Cancel request', message: 'Are you sure you want to cancel this request?', confirmLabel: 'Cancel request', destructive: true)) return;
    await _run(() async {
      await _repo.cancel(requestId);
      Toast.success('Request cancelled');
    });
  }
}
