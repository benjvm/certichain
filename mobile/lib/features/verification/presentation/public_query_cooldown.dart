import 'dart:async';

import 'package:flutter/foundation.dart';

/// Shared by the public route so leaving/reopening it does not reset Retry-After.
class PublicQueryCooldown extends ChangeNotifier {
  PublicQueryCooldown({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final DateTime Function() _clock;
  DateTime? _retryAt;
  Timer? _timer;
  bool _disposed = false;
  int get waitSeconds {
    final ms = _retryAt?.difference(_clock()).inMilliseconds ?? 0;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  void block(Duration duration) {
    if (_disposed) return;
    final deadline = _clock().add(duration);
    if (_retryAt == null || deadline.isAfter(_retryAt!)) _retryAt = deadline;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (waitSeconds == 0) _timer?.cancel();
      if (!_disposed) notifyListeners();
    });
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
