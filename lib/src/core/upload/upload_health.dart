import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'photo_upload_queue.dart';

/// Why the user is being warned about uploads.
enum UploadAlert {
  /// The device has no network connection.
  offline,

  /// Requests fail (no connection to the server, 5xx, timeouts).
  server,

  /// Nothing reached the server for too long without a clear failure.
  stalled,
}

/// Cached device connectivity. Assumes online when the plugin is unavailable
/// (tests, unsupported platforms) so a missing plugin never blocks uploads.
class NetworkStatus {
  NetworkStatus._();
  static final NetworkStatus instance = NetworkStatus._();

  final _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _online = true;

  bool get isOnline => _online;

  /// Starts listening (idempotent) and returns the current state.
  Future<bool> refresh() async {
    try {
      _subscription ??= _connectivity.onConnectivityChanged.listen(
        (results) => _online = _isOnline(results),
        onError: (_) {},
      );
      _online = _isOnline(await _connectivity.checkConnectivity());
    } catch (_) {
      _online = true;
    }
    return _online;
  }

  static bool _isOnline(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);
}

/// Phase 1 (user still capturing): decides when to show a dialog.
///
/// - Offline for [offlineDelay] → [UploadAlert.offline]: the user may keep
///   capturing (shown once per outage, closes by itself when back online) or
///   cancel the session.
/// - [failedPhotoThreshold] different photos failing in a row, failing for at
///   least [serverFailingDuration] → [UploadAlert.server]: the session ends.
///   This alert never clears by itself.
/// - Safety net for failures native never reports: [failedPhotoThreshold]
///   captured photos waiting longer than [silenceLimit] while the server has
///   not answered anything for [silenceLimit] → [UploadAlert.server].
class CaptureUploadAlertPolicy {
  CaptureUploadAlertPolicy({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now {
    _silenceBaseline = _clock();
  }

  static const offlineDelay = Duration(seconds: 30);
  static const failedPhotoThreshold = 3;
  static const serverFailingDuration = Duration(seconds: 30);
  static const silenceLimit = Duration(seconds: 60);

  final DateTime Function() _clock;

  UploadAlert? _alert;
  DateTime? _offlineSince;
  bool _offlineAlertShown = false;
  int? _ignoredStreakSince;

  /// Waiting time and server silence count from here at the earliest: start,
  /// network back, "Chụp tiếp" (uploads were paused meanwhile).
  late DateTime _silenceBaseline;

  UploadAlert? get alert => _alert;

  /// Returns true when the network just came back, so the caller can reset
  /// the native failure streak (failures while offline must not count).
  bool update({
    required bool online,
    UploadFailureStreak? streak,
    int? lastResponseAtMillis,
    List<int> pendingQueuedAtMillis = const [],
  }) {
    if (_alert == UploadAlert.server) return false;
    final now = _clock();
    if (!online) {
      _offlineSince ??= now;
      if (!_offlineAlertShown &&
          _alert == null &&
          now.difference(_offlineSince!) >= offlineDelay) {
        _offlineAlertShown = true;
        _alert = UploadAlert.offline;
      }
      return false;
    }

    if (_offlineSince != null) {
      _offlineSince = null;
      _offlineAlertShown = false;
      if (_alert == UploadAlert.offline) _alert = null;
      _ignoredStreakSince = streak?.sinceMillis;
      _silenceBaseline = now;
      return true;
    }
    if (_alert != null) return false;

    if (streak != null && streak.sinceMillis != _ignoredStreakSince) {
      final failingFor = now.difference(
        DateTime.fromMillisecondsSinceEpoch(streak.sinceMillis),
      );
      if (streak.itemIds.length >= failedPhotoThreshold &&
          failingFor >= serverFailingDuration) {
        _alert = UploadAlert.server;
        return false;
      }
    }

    if (_isStuck(now, lastResponseAtMillis, pendingQueuedAtMillis)) {
      _alert = UploadAlert.server;
    }
    return false;
  }

  bool _isStuck(
    DateTime now,
    int? lastResponseAtMillis,
    List<int> pendingQueuedAtMillis,
  ) {
    final nowMillis = now.millisecondsSinceEpoch;
    final baseline = _silenceBaseline.millisecondsSinceEpoch;
    final limit = silenceLimit.inMilliseconds;
    final lastHeard = (lastResponseAtMillis ?? 0) > baseline
        ? lastResponseAtMillis!
        : baseline;
    if (nowMillis - lastHeard < limit) return false;
    final waitingTooLong = pendingQueuedAtMillis.where((queuedAt) {
      final since = queuedAt > baseline ? queuedAt : baseline;
      return nowMillis - since >= limit;
    }).length;
    return waitingTooLong >= failedPhotoThreshold;
  }

  /// "Chụp tiếp" on the offline dialog: not shown again for this outage.
  void dismiss() {
    if (_alert != UploadAlert.offline) return;
    _alert = null;
    _silenceBaseline = _clock();
  }
}

/// Phase 2 (user waits on the upload screen): decides when to stop the
/// spinner and show the error screen.
class UploadWaitAlertPolicy {
  UploadWaitAlertPolicy({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now {
    reset();
  }

  static const offlineDelay = Duration(seconds: 5);
  static const maxFailures = 3;
  static const maxTimeouts = 2;
  static const maxFailingDuration = Duration(seconds: 30);
  static const stallTimeout = Duration(seconds: 90);

  final DateTime Function() _clock;

  DateTime? _offlineSince;
  late DateTime _lastProgressAt;
  int? _lastPending;
  int? _lastSuccessAt;
  int? _lastResponseAt;

  /// Start (or "Thử lại"): every threshold counts from now.
  void reset() {
    _offlineSince = null;
    _lastProgressAt = _clock();
    _lastPending = null;
    _lastSuccessAt = null;
    _lastResponseAt = null;
  }

  UploadAlert? evaluate({
    required bool online,
    required int pending,
    required UploadHealthSnapshot health,
    bool reportOfflineImmediately = false,
  }) {
    final now = _clock();

    // Progress = a photo finished or the server answered anything.
    if (pending != _lastPending ||
        health.lastSuccessAtMillis != _lastSuccessAt ||
        health.lastResponseAtMillis != _lastResponseAt) {
      if (_lastPending != null) _lastProgressAt = now;
      _lastPending = pending;
      _lastSuccessAt = health.lastSuccessAtMillis;
      _lastResponseAt = health.lastResponseAtMillis;
    }

    if (!online) {
      _offlineSince ??= now;
      if (reportOfflineImmediately ||
          now.difference(_offlineSince!) >= offlineDelay) {
        return UploadAlert.offline;
      }
      return null;
    }
    _offlineSince = null;

    final streak = health.streak;
    if (streak != null) {
      final failingFor = now.difference(
        DateTime.fromMillisecondsSinceEpoch(streak.sinceMillis),
      );
      if (streak.count >= maxFailures ||
          streak.timeoutCount >= maxTimeouts ||
          failingFor >= maxFailingDuration) {
        return UploadAlert.server;
      }
    }

    if (now.difference(_lastProgressAt) >= stallTimeout) {
      return UploadAlert.stalled;
    }
    return null;
  }
}

/// Polls the queue during capture and exposes [CaptureUploadAlertPolicy]'s
/// alert to the camera UI.
class CaptureUploadWatcher extends ChangeNotifier {
  CaptureUploadWatcher({
    required this.sessionId,
    this.interval = const Duration(seconds: 1),
  });

  final String sessionId;
  final Duration interval;
  final _policy = CaptureUploadAlertPolicy();
  Timer? _timer;
  bool _ticking = false;
  bool _disposed = false;

  UploadAlert? get alert => _policy.alert;

  void start() {
    _timer ??= Timer.periodic(interval, (_) => unawaited(_tick()));
    unawaited(NetworkStatus.instance.refresh());
  }

  void dismiss() {
    if (_policy.alert == null) return;
    _policy.dismiss();
    notifyListeners();
  }

  Future<void> _tick() async {
    if (_ticking || _disposed) return;
    _ticking = true;
    try {
      final health =
          await PhotoUploadQueue.instance.healthForSession(sessionId);
      if (_disposed) return;
      final before = _policy.alert;
      final reconnected = _policy.update(
        online: NetworkStatus.instance.isOnline,
        streak: health.streak,
        lastResponseAtMillis: health.lastResponseAtMillis,
        pendingQueuedAtMillis: health.pendingQueuedAtMillis,
      );
      if (reconnected) {
        unawaited(PhotoUploadQueue.instance.resetFailureStreak());
      }
      if (_policy.alert != before) notifyListeners();
    } catch (error) {
      debugPrint('AICycle upload watcher tick failed: $error');
    } finally {
      _ticking = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
