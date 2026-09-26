import '../utils/json.dart';

class Pagination {
  const Pagination({required this.page, required this.limit, required this.total, required this.totalPages});

  final int page;
  final int limit;
  final int total;
  final int totalPages;

  static const empty = Pagination(page: 1, limit: 20, total: 0, totalPages: 0);

  factory Pagination.fromJson(Object? json) {
    final m = asMap(json);
    final limit = asInt(m['limit'], 20);
    final total = asInt(m['total']);
    return Pagination(
      page: asInt(m['page'], 1),
      limit: limit,
      total: total,
      totalPages: asInt(m['totalPages'], limit > 0 ? (total / limit).ceil() : 0),
    );
  }
}

/// One page of a server-side paginated list.
class PageResult<T> {
  const PageResult({required this.items, required this.pagination, this.extra = const {}});

  final List<T> items;
  final Pagination pagination;

  /// Any additional top-level response fields (e.g. `summary`, `unread`).
  final Map<String, dynamic> extra;

  factory PageResult.fromResponse(Map<String, dynamic> body, T Function(Map<String, dynamic>) parse) {
    final extra = Map<String, dynamic>.from(body)..removeWhere((k, _) => const {'success', 'message', 'data', 'pagination'}.contains(k));
    return PageResult(
      items: asList(body['data']).map((e) => parse(asMap(e))).toList(),
      pagination: Pagination.fromJson(body['pagination']),
      extra: extra,
    );
  }
}

/// Standard list query (?page&limit&search&status&storeId&...&sortBy&sortOrder).
class ListQuery {
  const ListQuery({
    this.page = 1,
    this.limit = 20,
    this.search,
    this.sortBy,
    this.sortOrder,
    this.filters = const {},
  });

  final int page;
  final int limit;
  final String? search;
  final String? sortBy;
  final String? sortOrder;

  /// Any other query parameters (status, storeId, categoryId, startDate, ...).
  final Map<String, Object?> filters;

  Map<String, dynamic> toParams() {
    final params = <String, dynamic>{'page': page, 'limit': limit};
    if (search != null && search!.trim().isNotEmpty) params['search'] = search!.trim();
    if (sortBy != null) params['sortBy'] = sortBy;
    if (sortOrder != null) params['sortOrder'] = sortOrder;
    filters.forEach((key, value) {
      if (value == null) return;
      if (value is String && value.isEmpty) return;
      if (value is DateTime) {
        params[key] = value.toIso8601String().substring(0, 10);
      } else {
        params[key] = value.toString();
      }
    });
    return params;
  }

  ListQuery copyWith({int? page, int? limit}) =>
      ListQuery(page: page ?? this.page, limit: limit ?? this.limit, search: search, sortBy: sortBy, sortOrder: sortOrder, filters: filters);
}
