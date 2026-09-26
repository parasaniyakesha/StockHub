/// Tolerant JSON readers. The API returns decimals as strings ("199.50") and
/// counts as numbers; these helpers accept either and never throw.
Map<String, dynamic> asMap(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<dynamic> asList(Object? v) => v is List ? v : const [];

String asString(Object? v, [String fallback = '']) => v == null ? fallback : v.toString();

String? asStringOrNull(Object? v) => v == null ? null : v.toString();

int asInt(Object? v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.toInt() ?? fallback;
  return fallback;
}

int? asIntOrNull(Object? v) => v == null ? null : asInt(v);

double asDouble(Object? v, [double fallback = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

bool asBool(Object? v, [bool fallback = false]) {
  if (v is bool) return v;
  if (v is String) return v == 'true';
  return fallback;
}

DateTime? asDate(Object? v) {
  if (v is DateTime) return v.toLocal();
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toLocal();
  return null;
}

/// `{id, name, code}` reference objects embedded in many responses.
class Ref {
  const Ref({required this.id, required this.name, this.code});
  final String id;
  final String name;
  final String? code;

  static Ref? fromJson(Object? json) {
    final m = asMap(json);
    if (m['id'] == null) return null;
    return Ref(id: asString(m['id']), name: asString(m['name']), code: asStringOrNull(m['code'] ?? m['sku']));
  }

  String get label => code == null || code!.isEmpty ? name : '$name ($code)';
}
