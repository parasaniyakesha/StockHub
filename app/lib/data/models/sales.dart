import '../../core/utils/json.dart';
import 'catalog.dart';

class PaymentMethods {
  PaymentMethods._();
  static const all = ['CASH', 'CARD', 'UPI', 'BANK_TRANSFER', 'CREDIT', 'OTHER'];
}

class SaleItem {
  const SaleItem({
    required this.id,
    required this.product,
    required this.quantity,
    required this.unitPrice,
    required this.discount,
    required this.taxRate,
    required this.tax,
    required this.total,
    this.returnedQuantity = 0,
  });
  final String id;
  final ProductBrief product;
  final int quantity;
  final double unitPrice;
  final double discount;
  final double taxRate;
  final double tax;
  final double total;
  final int returnedQuantity;

  int get returnableQuantity => quantity - returnedQuantity;

  factory SaleItem.fromJson(Map<String, dynamic> j) => SaleItem(
        id: asString(j['id']),
        product: ProductBrief.fromJson(j['product']),
        quantity: asInt(j['quantity']),
        unitPrice: asDouble(j['unitPrice']),
        discount: asDouble(j['discount']),
        taxRate: asDouble(j['taxRate']),
        tax: asDouble(j['tax']),
        total: asDouble(j['total']),
        returnedQuantity: asInt(j['returnedQuantity']),
      );
}

class SaleStoreInfo {
  const SaleStoreInfo({required this.id, required this.name, required this.code, this.address, this.city, this.phone});
  final String id;
  final String name;
  final String code;
  final String? address;
  final String? city;
  final String? phone;

  factory SaleStoreInfo.fromJson(Object? json) {
    final j = asMap(json);
    return SaleStoreInfo(
      id: asString(j['id']),
      name: asString(j['name']),
      code: asString(j['code']),
      address: asStringOrNull(j['address']),
      city: asStringOrNull(j['city']),
      phone: asStringOrNull(j['phone']),
    );
  }
}

class Sale {
  const Sale({
    required this.id,
    required this.invoiceNumber,
    required this.store,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.grandTotal,
    required this.paymentMethod,
    required this.status,
    this.customerName,
    this.customerPhone,
    this.notes,
    this.createdBy,
    this.createdAt,
    this.cancelledAt,
    this.cancelReason,
    this.itemCount = 0,
    this.items = const [],
    this.returns = const [],
  });

  final String id;
  final String invoiceNumber;
  final SaleStoreInfo store;
  final String? customerName;
  final String? customerPhone;
  final double subtotal;
  final double discount;
  final double tax;
  final double grandTotal;
  final String paymentMethod;

  /// COMPLETED or CANCELLED
  final String status;
  final String? notes;
  final Ref? createdBy;
  final DateTime? createdAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final int itemCount;
  final List<SaleItem> items;

  /// {id, name: returnNumber, code: refundAmount}
  final List<Ref> returns;

  bool get isCancelled => status == 'CANCELLED';

  factory Sale.fromJson(Map<String, dynamic> j) => Sale(
        id: asString(j['id']),
        invoiceNumber: asString(j['invoiceNumber']),
        store: SaleStoreInfo.fromJson(j['store']),
        customerName: asStringOrNull(j['customerName']),
        customerPhone: asStringOrNull(j['customerPhone']),
        subtotal: asDouble(j['subtotal']),
        discount: asDouble(j['discount']),
        tax: asDouble(j['tax']),
        grandTotal: asDouble(j['grandTotal']),
        paymentMethod: asString(j['paymentMethod']),
        status: asString(j['status'], 'COMPLETED'),
        notes: asStringOrNull(j['notes']),
        createdBy: Ref.fromJson(j['createdBy']),
        createdAt: asDate(j['createdAt']),
        cancelledAt: asDate(j['cancelledAt']),
        cancelReason: asStringOrNull(j['cancelReason']),
        itemCount: asInt(asMap(j['_count'])['items'], asList(j['items']).length),
        items: asList(j['items']).map((e) => SaleItem.fromJson(asMap(e))).toList(),
        returns: asList(j['returns'])
            .map((e) {
              final r = asMap(e);
              return Ref(id: asString(r['id']), name: asString(r['returnNumber']), code: asString(r['refundAmount']));
            })
            .toList(),
      );
}

class SalesSummary {
  const SalesSummary({required this.completedCount, required this.completedTotal});
  final int completedCount;
  final double completedTotal;

  factory SalesSummary.fromJson(Object? json) {
    final j = asMap(json);
    return SalesSummary(completedCount: asInt(j['completedCount']), completedTotal: asDouble(j['completedTotal']));
  }
}

class ReturnItem {
  const ReturnItem({required this.id, required this.product, required this.quantity, required this.condition, required this.reason, required this.unitPrice});
  final String id;
  final ProductBrief product;
  final int quantity;

  /// GOOD or DAMAGED
  final String condition;
  final String reason;
  final double unitPrice;

  factory ReturnItem.fromJson(Map<String, dynamic> j) => ReturnItem(
        id: asString(j['id']),
        product: ProductBrief.fromJson(j['product']),
        quantity: asInt(j['quantity']),
        condition: asString(j['condition']),
        reason: asString(j['reason']),
        unitPrice: asDouble(j['unitPrice']),
      );
}

class SaleReturn {
  const SaleReturn({
    required this.id,
    required this.returnNumber,
    required this.store,
    required this.refundAmount,
    this.sale,
    this.notes,
    this.createdBy,
    this.createdAt,
    this.totalQuantity = 0,
    this.goodQuantity = 0,
    this.damagedQuantity = 0,
    this.items = const [],
  });

  final String id;
  final String returnNumber;
  final Ref store;

  /// {id, name: invoiceNumber}
  final Ref? sale;
  final String? notes;
  final double refundAmount;
  final Ref? createdBy;
  final DateTime? createdAt;
  final int totalQuantity;
  final int goodQuantity;
  final int damagedQuantity;
  final List<ReturnItem> items;

  factory SaleReturn.fromJson(Map<String, dynamic> j) {
    final sale = asMap(j['sale']);
    final items = asList(j['items']).map((e) => ReturnItem.fromJson(asMap(e))).toList();
    return SaleReturn(
      id: asString(j['id']),
      returnNumber: asString(j['returnNumber']),
      store: Ref.fromJson(j['store']) ?? const Ref(id: '', name: '—'),
      sale: sale['id'] == null ? null : Ref(id: asString(sale['id']), name: asString(sale['invoiceNumber'])),
      notes: asStringOrNull(j['notes']),
      refundAmount: asDouble(j['refundAmount']),
      createdBy: Ref.fromJson(j['createdBy']),
      createdAt: asDate(j['createdAt']),
      totalQuantity: asInt(j['totalQuantity'], items.fold<int>(0, (a, i) => a + i.quantity)),
      goodQuantity: asInt(j['goodQuantity'], items.where((i) => i.condition == 'GOOD').fold<int>(0, (a, i) => a + i.quantity)),
      damagedQuantity: asInt(j['damagedQuantity'], items.where((i) => i.condition == 'DAMAGED').fold<int>(0, (a, i) => a + i.quantity)),
      items: items,
    );
  }
}
