import 'package:get/get.dart';

import '../../../core/base/view_state.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/operations.dart';
import '../../../data/repositories/repositories.dart';

class TransferDetailController extends GetxController {
  TransferDetailController(this._repo, this.transferId);
  final TransferRepository _repo;
  final String transferId;

  final state = ViewState.loading.obs;
  final errorMessage = ''.obs;
  final transfer = Rxn<StockTransfer>();
  final acting = false.obs;
  final approvals = <String, int>{}.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    state.value = ViewState.loading;
    try {
      final t = await _repo.get(transferId);
      transfer.value = t;
      approvals.assignAll({for (final i in t.items) i.id: i.approvedQuantity ?? i.requestedQuantity});
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

  Future<void> approve() => _run(() async {
        await _repo.approve(transferId, Map.of(approvals));
        Toast.success('Transfer approved');
      });

  Future<void> reject() async {
    final reason = await reasonDialog(title: 'Reject transfer', confirmLabel: 'Reject', destructive: true);
    if (reason == null) return;
    await _run(() async {
      await _repo.reject(transferId, reason);
      Toast.success('Transfer rejected');
    });
  }

  Future<void> dispatch() async {
    if (!await confirmDialog(title: 'Dispatch transfer', message: 'This removes the approved quantity from the source stock. Continue?')) return;
    await _run(() async {
      await _repo.dispatch(transferId);
      Toast.success('Transfer dispatched');
    });
  }

  Future<void> receive() async {
    if (!await confirmDialog(title: 'Receive transfer', message: 'Confirm the full dispatched quantity arrived in good condition?', confirmLabel: 'Receive')) return;
    await _run(() async {
      await _repo.receive(transferId);
      Toast.success('Transfer received');
    });
  }

  Future<void> complete() => _run(() async {
        await _repo.complete(transferId);
        Toast.success('Transfer closed');
      });

  Future<void> cancel() async {
    if (!await confirmDialog(title: 'Cancel transfer', message: 'Are you sure you want to cancel this transfer?', confirmLabel: 'Cancel transfer', destructive: true)) return;
    await _run(() async {
      await _repo.cancel(transferId);
      Toast.success('Transfer cancelled');
    });
  }
}
