import 'package:get/get.dart';

import '../../../core/base/view_state.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/session/auth_service.dart';
import '../../../core/widgets/dialogs.dart';
import '../../../core/widgets/toast.dart';
import '../../../data/models/operations.dart';
import '../../../data/repositories/repositories.dart';

class PackingDetailController extends GetxController {
  PackingDetailController(this._repo, this.orderId);
  final PackingRepository _repo;
  final String orderId;

  final state = ViewState.loading.obs;
  final errorMessage = ''.obs;
  final order = Rxn<PackingOrder>();
  final acting = false.obs;

  bool get isAdmin => Get.find<AuthService>().isAdmin;
  bool get canManage => Get.find<AuthService>().can('packing.manage');
  bool get canReceive => Get.find<AuthService>().can('packing.receive');
  String? get myStoreId => Get.find<AuthService>().current?.storeId;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    state.value = ViewState.loading;
    try {
      order.value = await _repo.get(orderId);
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

  Future<void> assign() async {
    final shortfalls = order.value!.items.where((i) => i.allocatedQuantity != i.quantity).toList();
    if (shortfalls.isNotEmpty) {
      final names = shortfalls.map((i) => '${i.product.name} (${i.allocatedQuantity} of ${i.quantity})').join(', ');
      Toast.warning('Fully allocate every product before assigning: $names');
      return;
    }
    if (!await confirmDialog(title: 'Assign packing order', message: 'This freezes the allocation and reserves stock in the warehouse. Continue?')) return;
    await _run(() async {
      await _repo.assign(orderId);
      Toast.success('Packing order assigned');
    });
  }

  Future<void> startPacking() => _run(() async {
        await _repo.startPacking(orderId);
      });

  Future<void> pack(Map<String, int> packedByLine) => _run(() async {
        await _repo.pack(orderId, packedByLine);
        Toast.success('Packing recorded');
      });

  Future<void> dispatch() async {
    if (!await confirmDialog(title: 'Dispatch packing order', message: 'This removes the packed stock from the warehouse. Continue?')) return;
    await _run(() async {
      await _repo.dispatch(orderId);
      Toast.success('Packing order dispatched');
    });
  }

  Future<void> receive(List<Map<String, dynamic>> lines) => _run(() async {
        await _repo.receive(orderId, lines: lines);
        Toast.success('Stock received');
      });

  Future<void> complete() => _run(() async {
        await _repo.complete(orderId);
        Toast.success('Packing order closed');
      });

  Future<void> cancel() async {
    final reason = await reasonDialog(title: 'Cancel packing order', message: 'Explain why this packing order is being cancelled. Any packed or reserved stock is returned to the warehouse.', confirmLabel: 'Cancel order', destructive: true);
    if (reason == null) return;
    await _run(() async {
      await _repo.cancel(orderId, reason);
      Toast.success('Packing order cancelled');
    });
  }
}
