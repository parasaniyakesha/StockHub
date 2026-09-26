import '../../core/utils/json.dart';

class AppNotification {
  const AppNotification({required this.id, required this.type, required this.title, required this.message, this.entityType, this.entityId, this.readAt, this.createdAt});

  final String id;
  final String type;
  final String title;
  final String message;
  final String? entityType;
  final String? entityId;
  final DateTime? readAt;
  final DateTime? createdAt;

  bool get isRead => readAt != null;

  AppNotification markRead() =>
      AppNotification(id: id, type: type, title: title, message: message, entityType: entityType, entityId: entityId, readAt: DateTime.now(), createdAt: createdAt);

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: asString(j['id']),
        type: asString(j['type']),
        title: asString(j['title']),
        message: asString(j['message']),
        entityType: asStringOrNull(j['entityType']),
        entityId: asStringOrNull(j['entityId']),
        readAt: asDate(j['readAt']),
        createdAt: asDate(j['createdAt']),
      );
}

class AuditLogEntry {
  const AuditLogEntry({
    required this.id,
    required this.action,
    required this.module,
    this.userName,
    this.userEmail,
    this.userRole,
    this.recordId,
    this.summary,
    this.oldValue,
    this.newValue,
    this.ipAddress,
    this.userAgent,
    this.createdAt,
  });

  final String id;
  final String action;
  final String module;
  final String? userName;
  final String? userEmail;
  final String? userRole;
  final String? recordId;
  final String? summary;
  final Object? oldValue;
  final Object? newValue;
  final String? ipAddress;
  final String? userAgent;
  final DateTime? createdAt;

  factory AuditLogEntry.fromJson(Map<String, dynamic> j) {
    final user = asMap(j['user']);
    return AuditLogEntry(
      id: asString(j['id']),
      action: asString(j['action']),
      module: asString(j['module']),
      userName: asStringOrNull(user['name']),
      userEmail: asStringOrNull(user['email']),
      userRole: asStringOrNull(user['role']),
      recordId: asStringOrNull(j['recordId']),
      summary: asStringOrNull(j['summary']),
      oldValue: j['oldValue'],
      newValue: j['newValue'],
      ipAddress: asStringOrNull(j['ipAddress']),
      userAgent: asStringOrNull(j['userAgent']),
      createdAt: asDate(j['createdAt']),
    );
  }
}

class AppSettings {
  const AppSettings({
    this.companyName = 'StockHub',
    this.currencyCode = 'INR',
    this.currencySymbol = '₹',
    this.allowNegativeStock = false,
    this.lowStockAlerts = true,
    this.allowPriceOverride = false,
    this.invoicePrefix = 'INV',
    this.timezone = 'Asia/Kolkata',
  });

  final String companyName;
  final String currencyCode;
  final String currencySymbol;
  final bool allowNegativeStock;
  final bool lowStockAlerts;
  final bool allowPriceOverride;
  final String invoicePrefix;
  final String timezone;

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        companyName: asString(j['companyName'], 'StockHub'),
        currencyCode: asString(j['currencyCode'], 'INR'),
        currencySymbol: asString(j['currencySymbol'], '₹'),
        allowNegativeStock: asBool(j['allowNegativeStock']),
        lowStockAlerts: asBool(j['lowStockAlerts'], true),
        allowPriceOverride: asBool(j['allowPriceOverride']),
        invoicePrefix: asString(j['invoicePrefix'], 'INV'),
        timezone: asString(j['timezone'], 'Asia/Kolkata'),
      );

  Map<String, dynamic> toJson() => {
        'companyName': companyName,
        'currencyCode': currencyCode,
        'currencySymbol': currencySymbol,
        'allowNegativeStock': allowNegativeStock,
        'lowStockAlerts': lowStockAlerts,
        'allowPriceOverride': allowPriceOverride,
        'invoicePrefix': invoicePrefix,
        'timezone': timezone,
      };
}

// ═══════════════════════════ Dashboard ═══════════════════════════

class TrendPoint {
  const TrendPoint(this.date, this.value, [this.secondary = 0]);
  final DateTime date;
  final double value;
  final double secondary;
}

class NamedValue {
  const NamedValue({required this.id, required this.name, required this.value, this.count = 0, this.subtitle});
  final String id;
  final String name;
  final double value;
  final int count;
  final String? subtitle;
}

class LowStockEntry {
  const LowStockEntry({required this.productId, required this.name, required this.sku, required this.quantity, required this.minimumStock, required this.location});
  final String productId;
  final String name;
  final String sku;
  final int quantity;
  final int minimumStock;
  final String location;
}

class DashboardData {
  const DashboardData({
    required this.role,
    required this.scope,
    required this.cards,
    required this.salesTrend,
    required this.storeSales,
    required this.topProducts,
    required this.stockMovement,
    required this.lowStock,
  });

  final String role;

  /// ALL · STORES · STORE
  final String scope;
  final Map<String, dynamic> cards;
  final List<TrendPoint> salesTrend;
  final List<NamedValue> storeSales;
  final List<NamedValue> topProducts;

  /// value = inbound, secondary = outbound
  final List<TrendPoint> stockMovement;
  final List<LowStockEntry> lowStock;

  int card(String key) => asInt(cards[key]);
  double money(String key) => asDouble(cards[key]);
  bool has(String key) => cards[key] != null;

  factory DashboardData.fromJson(Map<String, dynamic> j) {
    final charts = asMap(j['charts']);
    return DashboardData(
      role: asString(j['role']),
      scope: asString(j['scope']),
      cards: asMap(j['cards']),
      salesTrend: asList(charts['salesTrend']).map((e) {
        final m = asMap(e);
        return TrendPoint(asDate(m['date']) ?? DateTime.now(), asDouble(m['total']), asDouble(m['invoices']));
      }).toList(),
      storeSales: asList(charts['storeSales']).map((e) {
        final m = asMap(e);
        return NamedValue(id: asString(m['storeId']), name: asString(m['name']), value: asDouble(m['total']), count: asInt(m['invoices']));
      }).toList(),
      topProducts: asList(charts['topProducts']).map((e) {
        final m = asMap(e);
        return NamedValue(id: asString(m['productId']), name: asString(m['name']), value: asDouble(m['quantity']), subtitle: asString(m['sku']), count: asInt(m['quantity']));
      }).toList(),
      stockMovement: asList(charts['stockMovement']).map((e) {
        final m = asMap(e);
        return TrendPoint(asDate(m['date']) ?? DateTime.now(), asDouble(m['inbound']), asDouble(m['outbound']));
      }).toList(),
      lowStock: asList(charts['lowStockProducts']).map((e) {
        final m = asMap(e);
        return LowStockEntry(
          productId: asString(m['productId']),
          name: asString(m['name']),
          sku: asString(m['sku']),
          quantity: asInt(m['quantity']),
          minimumStock: asInt(m['minimumStock']),
          location: asString(m['location']),
        );
      }).toList(),
    );
  }
}

// ═══════════════════════════ Reports ═══════════════════════════

class ReportColumn {
  const ReportColumn({required this.key, required this.label, this.type = 'text'});
  final String key;
  final String label;

  /// text · number · money · date · datetime · status
  final String type;
  bool get isNumeric => type == 'number' || type == 'money';
}

class ReportData {
  const ReportData({required this.title, required this.columns, required this.rows, this.summary = const {}});
  final String title;
  final List<ReportColumn> columns;
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic> summary;

  factory ReportData.fromJson(Map<String, dynamic> j) => ReportData(
        title: asString(j['title']),
        columns: asList(j['columns']).map((e) {
          final m = asMap(e);
          return ReportColumn(key: asString(m['key']), label: asString(m['label']), type: asString(m['type'], 'text'));
        }).toList(),
        rows: asList(j['rows']).map((e) => asMap(e)).toList(),
        summary: asMap(j['summary']),
      );
}
