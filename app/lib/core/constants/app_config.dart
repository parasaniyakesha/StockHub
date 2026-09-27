/// Build-time configuration. Nothing here is secret - the desktop client never
/// holds database credentials, JWT secrets or admin passwords.
///
/// Override at build/run time:
///   flutter run -d windows --dart-define=API_BASE_URL=https://api.example.com/api
class AppConfig {
  AppConfig._();

  static const String appName = 'StockHub';

  /// REST API base URL (including the `/api` prefix).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://stockhub-bfrt.onrender.com/api',
  );

  static const String environment = String.fromEnvironment('APP_ENV', defaultValue: 'development');

  static bool get isProduction => environment == 'production';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 45);

  /// How often the header refreshes the unread notification count.
  static const Duration notificationPollInterval = Duration(seconds: 60);

  static const int defaultPageSize = 20;
  static const List<int> pageSizes = [10, 20, 50, 100];
}
