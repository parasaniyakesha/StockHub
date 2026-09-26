import 'package:get/get.dart';

import '../../data/models/platform.dart';
import '../../data/repositories/repositories.dart';
import '../utils/formatters.dart';

/// Company-wide settings (name, currency...) loaded after sign-in.
class SettingsService extends GetxService {
  SettingsService(this._repo);
  final PlatformRepository _repo;

  final settings = const AppSettings().obs;

  Future<void> load() async {
    try {
      apply(await _repo.settings());
    } catch (_) {
      // Keep defaults; screens still work.
    }
  }

  void apply(AppSettings value) {
    settings.value = value;
    Fmt.currencySymbol = value.currencySymbol;
  }
}
