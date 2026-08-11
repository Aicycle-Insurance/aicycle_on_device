/// In-memory session cache. Lives as long as the process; reset when
/// a new SDK session starts (call [clear] from AICycleOnDevice.initState).
class SessionCache {
  SessionCache._();
  static final SessionCache _instance = SessionCache._();
  static SessionCache get instance => _instance;

  String? claimId;

  void clear() {
    claimId = null;
  }
}
