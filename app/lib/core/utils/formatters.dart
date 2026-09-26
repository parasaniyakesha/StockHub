import 'package:intl/intl.dart';

/// Display formatting. Currency symbol/code are set from company settings after login.
class Fmt {
  Fmt._();

  static String currencySymbol = '₹';
  static String locale = 'en_IN';

  static final _date = DateFormat('dd MMM yyyy');
  static final _dateTime = DateFormat('dd MMM yyyy, hh:mm a');
  static final _time = DateFormat('hh:mm a');
  static final _shortDate = DateFormat('dd MMM');

  static String money(num? value, {int decimals = 2}) {
    final f = NumberFormat.currency(locale: locale, symbol: currencySymbol, decimalDigits: decimals);
    return f.format(value ?? 0);
  }

  /// Compact money for chart axes and KPI tiles (₹1.2L, ₹3.4Cr, ₹12.5K).
  static String moneyCompact(num? value) {
    final v = (value ?? 0).toDouble();
    final abs = v.abs();
    String s;
    if (abs >= 1e7) {
      s = '${(v / 1e7).toStringAsFixed(abs >= 1e8 ? 0 : 1)}Cr';
    } else if (abs >= 1e5) {
      s = '${(v / 1e5).toStringAsFixed(abs >= 1e6 ? 0 : 1)}L';
    } else if (abs >= 1e3) {
      s = '${(v / 1e3).toStringAsFixed(abs >= 1e4 ? 0 : 1)}K';
    } else {
      s = v.toStringAsFixed(0);
    }
    return '$currencySymbol$s';
  }

  static String number(num? value, {int decimals = 0}) =>
      NumberFormat.decimalPatternDigits(locale: locale, decimalDigits: decimals).format(value ?? 0);

  static String signed(num value) => value > 0 ? '+${number(value)}' : number(value);

  static String percent(num? value, {int decimals = 0}) => '${(value ?? 0).toStringAsFixed(decimals)}%';

  static String date(DateTime? d) => d == null ? '—' : _date.format(d);
  static String dateTime(DateTime? d) => d == null ? '—' : _dateTime.format(d);
  static String time(DateTime? d) => d == null ? '—' : _time.format(d);
  static String shortDate(DateTime? d) => d == null ? '—' : _shortDate.format(d);

  static String relative(DateTime? d) {
    if (d == null) return '—';
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return date(d);
  }

  /// SNAKE_CASE enum → "Snake case".
  static String enumLabel(String? value) {
    if (value == null || value.isEmpty) return '—';
    final s = value.replaceAll('_', ' ').toLowerCase();
    return s[0].toUpperCase() + s.substring(1);
  }

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
