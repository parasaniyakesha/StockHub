import '../../core/utils/json.dart';

/// Minimal product reference embedded in stock, requests, orders, sales...
class ProductBrief {
  const ProductBrief({required this.id, required this.name, required this.sku, this.unit = 'PCS', this.minimumStock, this.sellingPrice, this.purchasePrice, this.taxRate = 0, this.category});

  final String id;
  final String name;
  final String sku;
  final String unit;
  final int? minimumStock;
  final double? sellingPrice;
  final double? purchasePrice;
  final double taxRate;
  final Ref? category;

  factory ProductBrief.fromJson(Object? json) {
    final j = asMap(json);
    return ProductBrief(
      id: asString(j['id']),
      name: asString(j['name']),
      sku: asString(j['sku']),
      unit: asString(j['unit'], 'PCS'),
      minimumStock: asIntOrNull(j['minimumStock']),
      sellingPrice: j['sellingPrice'] == null ? null : asDouble(j['sellingPrice']),
      purchasePrice: j['purchasePrice'] == null ? null : asDouble(j['purchasePrice']),
      taxRate: asDouble(j['taxRate']),
      category: Ref.fromJson(j['category']),
    );
  }
}

class Category {
  const Category({
    required this.id,
    required this.name,
    required this.code,
    required this.status,
    this.description,
    this.parentId,
    this.parent,
    this.productCount = 0,
    this.childCount = 0,
    this.createdAt,
  });

  final String id;
  final String name;
  final String code;
  final String status;
  final String? description;
  final String? parentId;
  final Ref? parent;
  final int productCount;
  final int childCount;
  final DateTime? createdAt;

  bool get isActive => status == 'ACTIVE';
  String get displayName => parent == null ? name : '${parent!.name} › $name';

  factory Category.fromJson(Map<String, dynamic> j) {
    final count = asMap(j['_count']);
    return Category(
      id: asString(j['id']),
      name: asString(j['name']),
      code: asString(j['code']),
      status: asString(j['status'], 'ACTIVE'),
      description: asStringOrNull(j['description']),
      parentId: asStringOrNull(j['parentId']),
      parent: Ref.fromJson(j['parent']),
      productCount: asInt(count['products']),
      childCount: asInt(count['children']),
      createdAt: asDate(j['createdAt']),
    );
  }
}

class LocationStock {
  const LocationStock({required this.location, required this.quantity, required this.reserved, required this.damaged});
  final Ref location;
  final int quantity;
  final int reserved;
  final int damaged;
  int get available => quantity - reserved;

  factory LocationStock.fromJson(Map<String, dynamic> j, String key) => LocationStock(
        location: Ref.fromJson(j[key]) ?? const Ref(id: '', name: '—'),
        quantity: asInt(j['quantity']),
        reserved: asInt(j['reservedQuantity']),
        damaged: asInt(j['damagedQuantity']),
      );
}

class Product {
  const Product({
    required this.id,
    required this.name,
    required this.sku,
    required this.categoryId,
    required this.unit,
    required this.sellingPrice,
    required this.taxRate,
    required this.minimumStock,
    required this.status,
    this.barcode,
    this.category,
    this.brand,
    this.description,
    this.purchasePrice,
    this.maximumStock,
    this.imageUrl,
    this.warehouseQuantity,
    this.warehouseAvailable,
    this.storeQuantity,
    this.warehouseStock = const [],
    this.storeStock = const [],
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String sku;
  final String? barcode;
  final String categoryId;
  final Ref? category;
  final String? brand;
  final String unit;
  final String? description;

  /// Null for store users (the API hides cost prices from them).
  final double? purchasePrice;
  final double sellingPrice;
  final double taxRate;
  final int minimumStock;
  final int? maximumStock;
  final String? imageUrl;
  final String status;

  /// Aggregates returned by the list endpoint (null when not visible to the role).
  final int? warehouseQuantity;
  final int? warehouseAvailable;
  final int? storeQuantity;

  /// Detail endpoint only.
  final List<LocationStock> warehouseStock;
  final List<LocationStock> storeStock;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isActive => status == 'ACTIVE';
  double? get marginPercent => purchasePrice == null || sellingPrice == 0 ? null : ((sellingPrice - purchasePrice!) / sellingPrice) * 100;

  /// Stock figure shown in the catalog table for the current role.
  int get displayStock => (warehouseQuantity ?? 0) + (storeQuantity ?? 0);

  ProductBrief get brief => ProductBrief(id: id, name: name, sku: sku, unit: unit, minimumStock: minimumStock, sellingPrice: sellingPrice, purchasePrice: purchasePrice, taxRate: taxRate, category: category);

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: asString(j['id']),
        name: asString(j['name']),
        sku: asString(j['sku']),
        barcode: asStringOrNull(j['barcode']),
        categoryId: asString(j['categoryId']),
        category: Ref.fromJson(j['category']),
        brand: asStringOrNull(j['brand']),
        unit: asString(j['unit'], 'PCS'),
        description: asStringOrNull(j['description']),
        purchasePrice: j['purchasePrice'] == null ? null : asDouble(j['purchasePrice']),
        sellingPrice: asDouble(j['sellingPrice']),
        taxRate: asDouble(j['taxRate']),
        minimumStock: asInt(j['minimumStock']),
        maximumStock: asIntOrNull(j['maximumStock']),
        imageUrl: asStringOrNull(j['imageUrl']),
        status: asString(j['status'], 'ACTIVE'),
        warehouseQuantity: asIntOrNull(j['warehouseQuantity']),
        warehouseAvailable: asIntOrNull(j['warehouseAvailable']),
        storeQuantity: asIntOrNull(j['storeQuantity']),
        warehouseStock: asList(j['warehouseStock']).map((e) => LocationStock.fromJson(asMap(e), 'warehouse')).toList(),
        storeStock: asList(j['storeStock']).map((e) => LocationStock.fromJson(asMap(e), 'store')).toList(),
        createdAt: asDate(j['createdAt']),
        updatedAt: asDate(j['updatedAt']),
      );
}

class StoreModel {
  const StoreModel({
    required this.id,
    required this.name,
    required this.code,
    required this.status,
    this.address,
    this.city,
    this.phone,
    this.email,
    this.contactPerson,
    this.assignedManagerId,
    this.manager,
    this.userCount = 0,
    this.users = const [],
    this.createdAt,
  });

  final String id;
  final String name;
  final String code;
  final String status;
  final String? address;
  final String? city;
  final String? phone;
  final String? email;
  final String? contactPerson;
  final String? assignedManagerId;
  final Ref? manager;
  final int userCount;
  final List<StoreUserSummary> users;
  final DateTime? createdAt;

  bool get isActive => status == 'ACTIVE';
  Ref get ref => Ref(id: id, name: name, code: code);

  factory StoreModel.fromJson(Map<String, dynamic> j) => StoreModel(
        id: asString(j['id']),
        name: asString(j['name']),
        code: asString(j['code']),
        status: asString(j['status'], 'ACTIVE'),
        address: asStringOrNull(j['address']),
        city: asStringOrNull(j['city']),
        phone: asStringOrNull(j['phone']),
        email: asStringOrNull(j['email']),
        contactPerson: asStringOrNull(j['contactPerson']),
        assignedManagerId: asStringOrNull(j['assignedManagerId']),
        manager: Ref.fromJson(j['assignedManager']),
        userCount: asInt(asMap(j['_count'])['users']),
        users: asList(j['users']).map((e) => StoreUserSummary.fromJson(asMap(e))).toList(),
        createdAt: asDate(j['createdAt']),
      );
}

class StoreUserSummary {
  const StoreUserSummary({required this.id, required this.name, required this.email, required this.status, this.lastLoginAt});
  final String id;
  final String name;
  final String email;
  final String status;
  final DateTime? lastLoginAt;

  factory StoreUserSummary.fromJson(Map<String, dynamic> j) => StoreUserSummary(
        id: asString(j['id']),
        name: asString(j['name']),
        email: asString(j['email']),
        status: asString(j['status']),
        lastLoginAt: asDate(j['lastLoginAt']),
      );
}

class Warehouse {
  const Warehouse({required this.id, required this.name, required this.code, required this.isDefault, required this.status, this.address});
  final String id;
  final String name;
  final String code;
  final bool isDefault;
  final String status;
  final String? address;

  factory Warehouse.fromJson(Map<String, dynamic> j) => Warehouse(
        id: asString(j['id']),
        name: asString(j['name']),
        code: asString(j['code']),
        isDefault: asBool(j['isDefault']),
        status: asString(j['status'], 'ACTIVE'),
        address: asStringOrNull(j['address']),
      );
}
