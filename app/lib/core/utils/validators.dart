/// Form validators. They mirror the server rules so users get instant feedback;
/// the server re-validates everything.
typedef Validator = String? Function(String? value);

class V {
  V._();

  static Validator required(String label) => (v) => (v == null || v.trim().isEmpty) ? '$label is required' : null;

  static Validator maxLength(int max) => (v) => (v != null && v.length > max) ? 'Must be at most $max characters' : null;

  static Validator minLength(int min, String label) =>
      (v) => (v != null && v.trim().isNotEmpty && v.trim().length < min) ? '$label must be at least $min characters' : null;

  static String? email(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim()) ? null : 'Enter a valid email address';
  }

  static String? phone(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return RegExp(r'^[0-9+\-\s]{6,20}$').hasMatch(v.trim()) ? null : 'Enter a valid phone number';
  }

  static String? code(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    return RegExp(r'^[A-Za-z0-9_-]{2,30}$').hasMatch(v.trim()) ? null : '2–30 letters, numbers, - or _';
  }

  static String? password(String? v) {
    if (v == null || v.isEmpty) return 'Password is required';
    if (v.length < 8) return 'At least 8 characters';
    if (!RegExp('[a-z]').hasMatch(v)) return 'Include a lowercase letter';
    if (!RegExp('[A-Z]').hasMatch(v)) return 'Include an uppercase letter';
    if (!RegExp('[0-9]').hasMatch(v)) return 'Include a number';
    return null;
  }

  static Validator integer({String label = 'Quantity', int? min, int? max}) => (v) {
        if (v == null || v.trim().isEmpty) return null;
        final n = int.tryParse(v.trim());
        if (n == null) return '$label must be a whole number';
        if (min != null && n < min) return min == 1 ? '$label must be greater than 0' : '$label must be at least $min';
        if (max != null && n > max) return '$label cannot exceed $max';
        return null;
      };

  static Validator decimal({String label = 'Amount', double min = 0, double? max}) => (v) {
        if (v == null || v.trim().isEmpty) return null;
        final n = double.tryParse(v.trim());
        if (n == null) return '$label must be a number';
        if (n < min) return '$label cannot be less than $min';
        if (max != null && n > max) return '$label cannot exceed $max';
        return null;
      };

  static String? url(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    final uri = Uri.tryParse(v.trim());
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty ? null : 'Enter a valid URL';
  }

  /// Runs validators in order and returns the first error.
  static Validator all(List<Validator> validators) => (v) {
        for (final validate in validators) {
          final r = validate(v);
          if (r != null) return r;
        }
        return null;
      };
}
