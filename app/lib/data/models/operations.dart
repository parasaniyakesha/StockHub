import '../../core/utils/json.dart';
import 'catalog.dart';

// ═══════════════════════════ Product requests ═══════════════════════════

class RequestStatus {
  RequestStatus._();
  static const draft = 'DRAFT';
  static const submitted = 'SUBMITTED';
  static const underReview = 'UNDER_REVIEW';
  static const approved = 'APPROVED';
  static const partiallyApproved = 'PARTIALLY_APPROVED';
  static const rejected = 'REJECTED';
  static const packed = 'PACKED';
  static const dispatched = 'DISPATCHED';
  static const received = 'RECEIVED';
  static const completed = 'COMPLETED';
  static const cancelled = 'CANCELLED';
  static const all = [draft, submitted, underReview, approved, partiallyApproved, rejected, packed, dispatched, received, completed, cancelled];
}

class ProductRequestItem {
  const ProductRequestItem({
    required this.id,
    required this.product,
    required this.requestedQuantity,
    this.approvedQuantity,
    this.notes,
    this.packedQuantity = 0,
    this.dispatchedQuantity = 0,
    this.receivedQuantity = 0,
    this.pendingQuantity = 0,
  });

  final String id;
  final ProductBrief product;
  final int requestedQuantity;
  final int? approvedQuantity;
  final String? notes;
  final int packedQuantity;
  final int dispatchedQuantity;
  final int receivedQuantity;
  final int pendingQuantity;

  factory ProductRequestItem.fromJson(Map<String, dynamic> j) => ProductRequestItem(
        id: asString(j['id']),
        product: ProductBrief.fromJson(j['product']),
        requestedQuantity: asInt(j['requestedQuantity']),
        approvedQuantity: asIntOrNull(j['approvedQuantity']),
        notes: asStringOrNull(j['notes']),
        packedQuantity: asInt(j['packedQuantity']),
        dispatchedQuantity: asInt(j['dispatchedQuantity']),
        receivedQuantity: asInt(j['receivedQuantity']),
        pendingQuantity: asInt(j['pendingQuantity']),
      );
}

class ProductRequest {
  const ProductRequest({
    required this.id,
    required this.requestNumber,
    required this.store,
    required this.status,
    this.notes,
    this.reviewNotes,
    this.createdAt,
    this.submittedAt,
    this.reviewedAt,
    this.itemCount = 0,
    this.totalRequested = 0,
    this.totalApproved,
    this.createdByName,
    this.reviewedByName,
    this.items = const [],
    this.packingOrders = const [],
  });

  final String id;
  final String requestNumber;
  final Ref store;
  final String status;
  final String? notes;
  final String? reviewNotes;
  final DateTime? createdAt;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final int itemCount;
  final int totalRequested;
  final int? totalApproved;
  final String? createdByName;
  final String? reviewedByName;
  final List<ProductRequestItem> items;

  /// Linked packing orders: {id, orderNumber, status}.
  final List<Ref> packingOrders;

  bool get isDraft => status == RequestStatus.draft;
  bool get isReviewable => status == RequestStatus.submitted || status == RequestStatus.underReview;
  bool get isPackable => (status == RequestStatus.approved || status == RequestStatus.partiallyApproved);

  factory ProductRequest.fromJson(Map<String, dynamic> j) {
    final items = asList(j['items']).map((e) => asMap(e)).toList();
    final detailed = items.isNotEmpty && items.first['id'] != null;
    return ProductRequest(
      id: asString(j['id']),
      requestNumber: asString(j['requestNumber']),
      store: Ref.fromJson(j['store']) ?? const Ref(id: '', name: '—'),
      status: asString(j['status']),
      notes: asStringOrNull(j['notes']),
      reviewNotes: asStringOrNull(j['reviewNotes']),
      createdAt: asDate(j['createdAt']),
      submittedAt: asDate(j['submittedAt']),
      reviewedAt: asDate(j['reviewedAt']),
      itemCount: asInt(j['itemCount'], items.length),
      totalRequested: asInt(j['totalRequested'], items.fold<int>(0, (a, i) => a + asInt(i['requestedQuantity']))),
      totalApproved: j.containsKey('totalApproved') ? asIntOrNull(j['totalApproved']) : null,
      createdByName: asStringOrNull(j['createdByName']),
      reviewedByName: asStringOrNull(j['reviewedByName']),
      items: detailed ? items.map(ProductRequestItem.fromJson).toList() : const [],
      packingOrders: asList(j['packingOrders'])
          .map((e) {
            final po = asMap(asMap(e)['packingOrder']);
            return po['id'] == null ? null : Ref(id: asString(po['id']), name: asString(po['orderNumber']), code: asString(po['status']));
          })
          .whereType<Ref>()
          .toList(),
    );
  }
}

// ═══════════════════════════ Packing orders ═══════════════════════════

class PackingStatus {
  PackingStatus._();
  static const draft = 'DRAFT';
  static const assigned = 'ASSIGNED';
  static const packing = 'PACKING';
  static const packed = 'PACKED';
  static const dispatched = 'DISPATCHED';
  static const received = 'RECEIVED';
  static const completed = 'COMPLETED';
  static const cancelled = 'CANCELLED';
  static const all = [draft, assigned, packing, packed, dispatched, received, completed, cancelled];
}

class PackingItem {
  const PackingItem({
    required this.id,
    required this.productId,
    required this.product,
    required this.quantity,
    this.requestedQuantity = 0,
    this.approvedQuantity = 0,
    this.allocatedQuantity = 0,
    this.packedQuantity = 0,
    this.dispatchedQuantity = 0,
    this.receivedQuantity = 0,
    this.damagedQuantity = 0,
    this.pendingQuantity = 0,
    this.unallocatedQuantity = 0,
    this.warehouseAvailable,
  });

  final String id;
  final String productId;
  final ProductBrief product;

  /// Planned total quantity.
  final int quantity;
  final int requestedQuantity;
  final int approvedQuantity;
  final int allocatedQuantity;
  final int packedQuantity;
  final int dispatchedQuantity;
  final int receivedQuantity;
  final int damagedQuantity;
  final int pendingQuantity;
  final int unallocatedQuantity;

  /// Warehouse available stock (hidden from store users).
  final int? warehouseAvailable;

  factory PackingItem.fromJson(Map<String, dynamic> j) => PackingItem(
        id: asString(j['id']),
        productId: asString(j['productId']),
        product: ProductBrief.fromJson(j['product']),
        quantity: asInt(j['quantity']),
        requestedQuantity: asInt(j['requestedQuantity']),
        approvedQuantity: asInt(j['approvedQuantity']),
        allocatedQuantity: asInt(j['allocatedQuantity']),
        packedQuantity: asInt(j['packedQuantity']),
        dispatchedQuantity: asInt(j['dispatchedQuantity']),
        receivedQuantity: asInt(j['receivedQuantity']),
        damagedQuantity: asInt(j['damagedQuantity']),
        pendingQuantity: asInt(j['pendingQuantity']),
        unallocatedQuantity: asInt(j['unallocatedQuantity']),
        warehouseAvailable: asIntOrNull(j['warehouseAvailable']),
      );
}

/// Allocation line: one product for one store within a packing order.
class PackingLine {
  const PackingLine({
    required this.id,
    required this.productId,
    required this.product,
    required this.allocatedQuantity,
    this.requestedQuantity = 0,
    this.approvedQuantity = 0,
    this.packedQuantity = 0,
    this.dispatchedQuantity = 0,
    this.receivedQuantity = 0,
    this.damagedQuantity = 0,
    this.pendingQuantity = 0,
    this.shortQuantity = 0,
  });

  final String id;
  final String productId;
  final ProductBrief product;
  final int requestedQuantity;
  final int approvedQuantity;
  final int allocatedQuantity;
  final int packedQuantity;
  final int dispatchedQuantity;
  final int receivedQuantity;
  final int damagedQuantity;
  final int pendingQuantity;
  final int shortQuantity;

  factory PackingLine.fromJson(Map<String, dynamic> j) => PackingLine(
        id: asString(j['id']),
        productId: asString(j['productId']),
        product: ProductBrief.fromJson(j['product']),
        requestedQuantity: asInt(j['requestedQuantity']),
        approvedQuantity: asInt(j['approvedQuantity']),
        allocatedQuantity: asInt(j['allocatedQuantity']),
        packedQuantity: asInt(j['packedQuantity']),
        dispatchedQuantity: asInt(j['dispatchedQuantity']),
        receivedQuantity: asInt(j['receivedQuantity']),
        damagedQuantity: asInt(j['damagedQuantity']),
        pendingQuantity: asInt(j['pendingQuantity']),
        shortQuantity: asInt(j['shortQuantity']),
      );
}

class PackingStore {
  const PackingStore({required this.id, required this.storeId, required this.store, required this.status, this.request, this.dispatchedAt, this.receivedAt, this.receiptNotes, this.lines = const []});

  final String id;
  final String storeId;
  final Ref store;

  /// PENDING · DISPATCHED · RECEIVED · CANCELLED
  final String status;

  /// Source product request {id, name: requestNumber}.
  final Ref? request;
  final DateTime? dispatchedAt;
  final DateTime? receivedAt;
  final String? receiptNotes;
  final List<PackingLine> lines;

  int get totalAllocated => lines.fold(0, (a, l) => a + l.allocatedQuantity);
  int get totalDispatched => lines.fold(0, (a, l) => a + l.dispatchedQuantity);
  int get totalReceived => lines.fold(0, (a, l) => a + l.receivedQuantity);

  factory PackingStore.fromJson(Map<String, dynamic> j) {
    final req = asMap(j['request']);
    final store = Ref.fromJson(j['store']) ?? const Ref(id: '', name: '—');
    return PackingStore(
      id: asString(j['id']),
      storeId: asString(j['storeId'], store.id),
      store: store,
      status: asString(j['status']),
      request: req['id'] == null ? null : Ref(id: asString(req['id']), name: asString(req['requestNumber']), code: asStringOrNull(req['status'])),
      dispatchedAt: asDate(j['dispatchedAt']),
      receivedAt: asDate(j['receivedAt']),
      receiptNotes: asStringOrNull(j['receiptNotes']),
      lines: asList(j['items']).map((e) => PackingLine.fromJson(asMap(e))).toList(),
    );
  }
}

class PackingOrder {
  const PackingOrder({
    required this.id,
    required this.orderNumber,
    required this.status,
    this.warehouse,
    this.notes,
    this.createdAt,
    this.assignedAt,
    this.packedAt,
    this.dispatchedAt,
    this.completedAt,
    this.cancelledAt,
    this.itemCount = 0,
    this.storeCount = 0,
    this.totalAllocated = 0,
    this.totalPacked = 0,
    this.totalDispatched = 0,
    this.totalReceived = 0,
    this.items = const [],
    this.stores = const [],
  });

  final String id;
  final String orderNumber;
  final String status;
  final Ref? warehouse;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? assignedAt;
  final DateTime? packedAt;
  final DateTime? dispatchedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final int itemCount;
  final int storeCount;
  final int totalAllocated;
  final int totalPacked;
  final int totalDispatched;
  final int totalReceived;
  final List<PackingItem> items;
  final List<PackingStore> stores;

  bool get isDraft => status == PackingStatus.draft;

  factory PackingOrder.fromJson(Map<String, dynamic> j) {
    final stores = asList(j['stores']).map((e) => PackingStore.fromJson(asMap(e))).toList();
    return PackingOrder(
      id: asString(j['id']),
      orderNumber: asString(j['orderNumber']),
      status: asString(j['status']),
      warehouse: Ref.fromJson(j['warehouse']),
      notes: asStringOrNull(j['notes']),
      createdAt: asDate(j['createdAt']),
      assignedAt: asDate(j['assignedAt']),
      packedAt: asDate(j['packedAt']),
      dispatchedAt: asDate(j['dispatchedAt']),
      completedAt: asDate(j['completedAt']),
      cancelledAt: asDate(j['cancelledAt']),
      itemCount: asInt(j['itemCount'], asList(j['items']).length),
      storeCount: asInt(j['storeCount'], stores.length),
      totalAllocated: asInt(j['totalAllocated'], stores.fold<int>(0, (a, s) => a + s.totalAllocated)),
      totalPacked: asInt(j['totalPacked']),
      totalDispatched: asInt(j['totalDispatched'], stores.fold<int>(0, (a, s) => a + s.totalDispatched)),
      totalReceived: asInt(j['totalReceived'], stores.fold<int>(0, (a, s) => a + s.totalReceived)),
      items: asList(j['items']).map((e) => PackingItem.fromJson(asMap(e))).toList(),
      stores: stores,
    );
  }
}

// ═══════════════════════════ Transfers ═══════════════════════════

class TransferStatus {
  TransferStatus._();
  static const requested = 'REQUESTED';
  static const approved = 'APPROVED';
  static const dispatched = 'DISPATCHED';
  static const received = 'RECEIVED';
  static const completed = 'COMPLETED';
  static const rejected = 'REJECTED';
  static const cancelled = 'CANCELLED';
  static const all = [requested, approved, dispatched, received, completed, rejected, cancelled];
}

class TransferItem {
  const TransferItem({
    required this.id,
    required this.product,
    required this.requestedQuantity,
    this.approvedQuantity,
    this.dispatchedQuantity = 0,
    this.receivedQuantity = 0,
    this.damagedQuantity = 0,
    this.shortQuantity = 0,
  });
  final String id;
  final ProductBrief product;
  final int requestedQuantity;
  final int? approvedQuantity;
  final int dispatchedQuantity;
  final int receivedQuantity;
  final int damagedQuantity;
  final int shortQuantity;

  factory TransferItem.fromJson(Map<String, dynamic> j) => TransferItem(
        id: asString(j['id']),
        product: ProductBrief.fromJson(j['product']),
        requestedQuantity: asInt(j['requestedQuantity']),
        approvedQuantity: asIntOrNull(j['approvedQuantity']),
        dispatchedQuantity: asInt(j['dispatchedQuantity']),
        receivedQuantity: asInt(j['receivedQuantity']),
        damagedQuantity: asInt(j['damagedQuantity']),
        shortQuantity: asInt(j['shortQuantity']),
      );
}

class StockTransfer {
  const StockTransfer({
    required this.id,
    required this.transferNumber,
    required this.sourceType,
    required this.toStore,
    required this.status,
    this.fromStore,
    this.fromWarehouse,
    this.notes,
    this.rejectionReason,
    this.requestedById,
    this.createdAt,
    this.approvedAt,
    this.dispatchedAt,
    this.receivedAt,
    this.completedAt,
    this.itemCount = 0,
    this.totalRequested = 0,
    this.totalDispatched = 0,
    this.totalReceived = 0,
    this.items = const [],
    this.allowedActions = const {},
  });

  final String id;
  final String transferNumber;

  /// WAREHOUSE or STORE
  final String sourceType;
  final Ref? fromStore;
  final Ref? fromWarehouse;
  final Ref toStore;
  final String status;
  final String? notes;
  final String? rejectionReason;
  final String? requestedById;
  final DateTime? createdAt;
  final DateTime? approvedAt;
  final DateTime? dispatchedAt;
  final DateTime? receivedAt;
  final DateTime? completedAt;
  final int itemCount;
  final int totalRequested;
  final int totalDispatched;
  final int totalReceived;
  final List<TransferItem> items;

  /// Server hints: approve, reject, dispatch, receive, complete, cancel.
  final Map<String, bool> allowedActions;

  bool get fromWarehouseSource => sourceType == 'WAREHOUSE';
  Ref get source => (fromWarehouseSource ? fromWarehouse : fromStore) ?? const Ref(id: '', name: '—');
  bool can(String action) => allowedActions[action] == true;

  factory StockTransfer.fromJson(Map<String, dynamic> j) {
    final items = asList(j['items']).map((e) => asMap(e)).toList();
    final detailed = items.isNotEmpty && items.first['id'] != null;
    return StockTransfer(
      id: asString(j['id']),
      transferNumber: asString(j['transferNumber']),
      sourceType: asString(j['sourceType']),
      fromStore: Ref.fromJson(j['fromStore']),
      fromWarehouse: Ref.fromJson(j['fromWarehouse']),
      toStore: Ref.fromJson(j['toStore']) ?? const Ref(id: '', name: '—'),
      status: asString(j['status']),
      notes: asStringOrNull(j['notes']),
      rejectionReason: asStringOrNull(j['rejectionReason']),
      requestedById: asStringOrNull(j['requestedById']),
      createdAt: asDate(j['createdAt']),
      approvedAt: asDate(j['approvedAt']),
      dispatchedAt: asDate(j['dispatchedAt']),
      receivedAt: asDate(j['receivedAt']),
      completedAt: asDate(j['completedAt']),
      itemCount: asInt(j['itemCount'], items.length),
      totalRequested: asInt(j['totalRequested'], items.fold<int>(0, (a, i) => a + asInt(i['requestedQuantity']))),
      totalDispatched: asInt(j['totalDispatched'], items.fold<int>(0, (a, i) => a + asInt(i['dispatchedQuantity']))),
      totalReceived: asInt(j['totalReceived'], items.fold<int>(0, (a, i) => a + asInt(i['receivedQuantity']))),
      items: detailed ? items.map(TransferItem.fromJson).toList() : const [],
      allowedActions: asMap(j['allowedActions']).map((k, v) => MapEntry(k, v == true)),
    );
  }
}
