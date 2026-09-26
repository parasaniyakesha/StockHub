import 'dart:async';

import 'package:get/get.dart';

import '../../data/models/platform.dart';
import '../../data/repositories/repositories.dart';
import '../constants/app_config.dart';
import '../network/api_response.dart';

/// Keeps the unread badge in the header up to date and serves the header
/// dropdown with the latest notifications.
class NotificationCenter extends GetxService {
  NotificationCenter(this._repo);
  final PlatformRepository _repo;

  final unread = 0.obs;
  final latest = <AppNotification>[].obs;
  final loadingLatest = false.obs;
  Timer? _timer;

  void start() {
    stop();
    refreshCount();
    _timer = Timer.periodic(AppConfig.notificationPollInterval, (_) => refreshCount());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    unread.value = 0;
    latest.clear();
  }

  Future<void> refreshCount() async {
    try {
      unread.value = await _repo.unreadCount();
    } catch (_) {}
  }

  Future<void> loadLatest() async {
    loadingLatest.value = true;
    try {
      final page = await _repo.notifications(const ListQuery(limit: 8));
      latest.assignAll(page.items);
      unread.value = (page.extra['unread'] as num?)?.toInt() ?? unread.value;
    } catch (_) {
    } finally {
      loadingLatest.value = false;
    }
  }

  Future<void> markRead(AppNotification n) async {
    if (n.isRead) return;
    try {
      await _repo.markRead(n.id);
      final i = latest.indexWhere((x) => x.id == n.id);
      if (i >= 0) latest[i] = n.markRead();
      if (unread.value > 0) unread.value--;
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    try {
      await _repo.markAllRead();
      latest.assignAll(latest.map((n) => n.markRead()));
      unread.value = 0;
    } catch (_) {}
  }
}
