/// In-memory session cache. Lives as long as the process; reset when
/// a new SDK session starts (call [clear] from AICycleOnDevice.initState).
class SessionCache {
  SessionCache._();
  static final SessionCache _instance = SessionCache._();
  static SessionCache get instance => _instance;

  String? claimId;

  /// `kvp.claimBuyMe.baseUrlOnPremise` lấy từ API `/bearer` lúc khởi tạo SDK.
  String? baseUrlOnPremise;

  void clear() {
    claimId = null;
    baseUrlOnPremise = null;
  }
}
