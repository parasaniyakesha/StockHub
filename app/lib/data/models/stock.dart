import '../../core/utils/json.dart';
import 'catalog.dart';

/// Current balance of one product at one location (store or warehouse).
class StockBalance {
  const StockBalance({
    required this.id,
    required this.product,
    required this.quantity,
    required this.reservedQuantity,
    required this.availableQuantity,
    required this.damagedQuantity,
    this.store,
    this.warehouse,
    this.updatedAt,
  });

  final String id;
  final ProductBrief product;
  final Ref? store;
  final Ref? warehouse;
  final int quantity;
  final int reservedQuantity;
  final int availableQuantity;
  final int damagedQuantity;
  final DateTime? updatedAt;

  Ref get location => store ?? warehouse ?? const Ref(id: '', name: '—');
  bool get isLow => product.minimumStock != null && quantity <= product.minimumStock!;
  bool get isOut => quantity <= 0;

  factory StockBalance.fromJson(Map<String, dynamic> j) => StockBalance(
        id: asString(j['id']),
        product: ProductBrief.fromJson(j['product']),
        store: Ref.fromJson(j['store']),
        warehouse: Ref.fromJson(j['warehouse']),
        quantity: asInt(j['quantity']),
        reservedQuantity: asInt(j['reservedQuantity']),
        availableQuantity: asInt(j['availableQuantity'], asInt(j['quantity']) - asInt(j['reservedQuantity'])),
        damagedQuantity: asInt(j['damagedQuantity']),
        updatedAt: asDate(j['updatedAt']),
      );
}

class StockMovement {
  const StockMovement({
    required this.id,
    required this.product,
    required this.type,
    required this.bucket,
    required this.quantity,
    required this.balanceAfter,
    required this.createdAt,
    this.store,
    this.warehouse,
    this.referenceType,
    this.referenceId,
    this.reason,
    this.createdBy,
  });

  final String id;
  final ProductBrief product;
  final Ref? store;
  final Ref? warehouse;
  final String type;
  final String bucket;
  final int quantity;
  final int balanceAfter;
  final String? referenceType;
  final String? referenceId;
  final String? reason;
  final Ref? createdBy;
  final DateTime? createdAt;

  Ref get location => store ?? warehouse ?? const Ref(id: '', name: '—');
  bool get isInbound => quantity > 0;

  factory StockMovement.fromJson(Map<String, dynamic> j) => StockMovement(
        id: asString(j['id']),
        product: ProductBrief.fromJson(j['product']),
        store: Ref.fromJson(j['store']),
        warehouse: Ref.fromJson(j['warehouse']),
        type: asString(j['type']),
        bucket: asString(j['bucket'], 'AVAILABLE'),
        quantity: asInt(j['quantity']),
        balanceAfter: asInt(j['balanceAfter']),
        referenceType: asStringOrNull(j['referenceType']),
        referenceId: asStringOrNull(j['referenceId']),
        reason: asStringOrNull(j['reason']),
        createdBy: Ref.fromJson(j['createdBy']),
        createdAt: asDate(j['createdAt']),
      );
}

/// Quantity a store self-declared as physically available.
class StoreAvailability {
  const StoreAvailability({required this.id, required this.product, required this.store, required this.quantity, this.notes, this.updatedAt});
  final String id;
  final ProductBrief product;
  final Ref store;
  final int quantity;
  final String? notes;
  final DateTime? updatedAt;

  factory StoreAvailability.fromJson(Map<String, dynamic> j) => StoreAvailability(
        id: asString(j['id']),
        product: ProductBrief.fromJson(j['product']),
        store: Ref.fromJson(j['store']) ?? const Ref(id: '', name: '—'),
        quantity: asInt(j['quantity']),
        notes: asStringOrNull(j['notes']),
        updatedAt: asDate(j['updatedAt']),
      );
}

class AvailabilityCell {
  const AvailabilityCell({required this.storeId, required this.systemQuantity, this.declaredQuantity, this.declaredAt});
  final String storeId;
  final int? declaredQuantity;
  final DateTime? declaredAt;
  final int systemQuantity;
}

class AvailabilityRow {
  const AvailabilityRow({required this.product, required this.cells, required this.totalDeclared, required this.totalSystem});
  final ProductBrief product;
  final List<AvailabilityCell> cells;
  final int totalDeclared;
  final int totalSystem;

  AvailabilityCell? cellFor(String storeId) => cells.where((c) => c.storeId == storeId).firstOrNull;

  factory AvailabilityRow.fromJson(Map<String, dynamic> j) => AvailabilityRow(
        product: ProductBrief.fromJson(j['product']),
        cells: asList(j['stores']).map((e) {
          final c = asMap(e);
          return AvailabilityCell(
            storeId: asString(c['storeId']),
            declaredQuantity: asIntOrNull(c['declaredQuantity']),
            declaredAt: asDate(c['declaredAt']),
            systemQuantity: asInt(c['systemQuantity']),
          );
        }).toList(),
        totalDeclared: asInt(j['totalDeclared']),
        totalSystem: asInt(j['totalSystem']),
      );
}

class AvailabilityMatrix {
  const AvailabilityMatrix({required this.stores, required this.rows});
  final List<Ref> stores;
  final List<AvailabilityRow> rows;
}

/// Movement type labels & direction for display.
class MovementTypes {
  MovementTypes._();
  static const all = ['OPENING', 'PURCHASE', 'TRANSFER_IN', 'TRANSFER_OUT', 'SALE', 'RETURN', 'DAMAGE', 'ADJUSTMENT', 'PACKING', 'CANCELLATION'];
}
