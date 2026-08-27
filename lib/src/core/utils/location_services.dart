import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

import '../error/exceptions.dart';
import '../error/failures.dart';
import 'result.dart';
import 'logger.dart';

/// Model chứa thông tin vị trí đã được geocode.
class LocationData {
  /// Vĩ độ (latitude).
  final double latitude;

  /// Kinh độ (longitude).
  final double longitude;

  /// Địa chỉ đầy đủ (ví dụ: "123 Nguyễn Huệ, Quận 1, TP.HCM").
  final String? formattedAddress;

  /// Tên đường / địa điểm (subThoroughfare + thoroughfare).
  final String? street;

  /// Quận / huyện (subLocality).
  final String? district;

  /// Thành phố / tỉnh (locality hoặc administrativeArea).
  final String? city;

  /// Quốc gia.
  final String? country;

  /// Mã bưu chính.
  final String? postalCode;

  const LocationData({
    required this.latitude,
    required this.longitude,
    this.formattedAddress,
    this.street,
    this.district,
    this.city,
    this.country,
    this.postalCode,
  });

  @override
  String toString() =>
      'LocationData(lat: $latitude, lng: $longitude, address: $formattedAddress)';
}

/// Service lấy vị trí GPS hiện tại và chuyển đổi thành thông tin địa điểm
/// thông qua reverse geocoding.
///
/// **Sử dụng:**
/// ```dart
/// final service = LocationService();
/// final result = await service.getCurrentLocation();
/// result.fold(
///   (failure) => print('Lỗi: ${failure.message}'),
///   (data)    => print('Vị trí: ${data.formattedAddress}'),
/// );
/// ```
class LocationService {
  static const _tag = 'LocationService';

  final LoggerService _logger;

  LocationService({LoggerService? logger})
      : _logger = logger ?? LoggerService();

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Lấy vị trí GPS hiện tại và thực hiện reverse geocoding để lấy địa chỉ.
  ///
  /// Trả về [Result]:
  /// - [Success] với [LocationData] nếu thành công.
  /// - [FailureResult] với [LocationFailure] nếu xảy ra lỗi.
  Future<Result<LocationData, LocationFailure>> getCurrentLocation() async {
    try {
      final position = await _determinePosition();
      final locationData = await _geocodePosition(
        _FakePosition(
            latitude: position.latitude, longitude: position.longitude),
      );
      _logger
          .i('$_tag: Lấy vị trí thành công → ${locationData.formattedAddress}');
      return Success(locationData);
    } on LocationException catch (e, st) {
      _logger.e('$_tag: LocationException', e, st);
      return FailureResult(
          LocationFailure(e.message ?? 'Không thể lấy vị trí'));
    } catch (e, st) {
      _logger.e('$_tag: Unexpected error', e, st);
      return FailureResult(
          const LocationFailure('Lỗi không xác định khi lấy vị trí'));
    }
  }

  static Position? _lastKnownPosition;
  static DateTime? _lastKnownAt;

  /// Request đang bay. Hai chỗ gọi cùng lúc (prefetch lúc mở camera và lần chụp
  /// đầu) phải dùng chung một lần xin fix GPS, thay vì mở hai request song song.
  static Future<Result<Position, LocationFailure>>? _inFlight;

  /// Coi toạ độ còn dùng được trong khoảng này. Ảnh của một phiên chụp xe đều
  /// chụp tại cùng một chỗ nên không cần fix mới cho từng ảnh.
  static const _positionMaxAge = Duration(minutes: 2);

  /// Vị trí GPS vừa lấy thành công gần đây nhất trong phiên làm việc.
  static Position? get lastKnownPosition => _lastKnownPosition;

  /// Toạ độ đã lấy được và vẫn còn "tươi" (trong [maxAge]), hoặc null nếu chưa
  /// có. **Đồng bộ** — dùng ở đường tới hạn (khoảnh khắc chụp ảnh) để không bao
  /// giờ phải chờ GPS.
  static Position? freshPosition({Duration maxAge = _positionMaxAge}) {
    final at = _lastKnownAt;
    if (_lastKnownPosition == null || at == null) return null;
    return DateTime.now().difference(at) <= maxAge ? _lastKnownPosition : null;
  }

  static void _cachePosition(Position position) {
    _lastKnownPosition = position;
    _lastKnownAt = DateTime.now();
  }

  /// Lấy vị trí GPS hiện tại với [timeLimit] ngắn (mặc định 3s).
  ///
  /// Trả về ngay toạ độ đã cache nếu còn trong [maxAge] — trên Android
  /// `getCurrentPosition` xin một fix MỚI (requestLocationUpdates rồi chờ
  /// callback đầu tiên), tốn từ vài trăm ms tới trọn [timeLimit] khi máy chưa có
  /// fix; iOS thì trả fix đã warm gần như tức thì. Không cache thì mỗi lần gọi
  /// đều phải trả giá đó.
  ///
  /// Nếu bị timeout hoặc có lỗi, tự động fallback về [_lastKnownPosition]
  /// hoặc vị trí gần nhất từ Geolocator để không làm chậm UX.
  Future<Result<Position, LocationFailure>> getFastCurrentPosition({
    Duration timeLimit = const Duration(seconds: 3),
    Duration maxAge = _positionMaxAge,
  }) {
    final cached = freshPosition(maxAge: maxAge);
    if (cached != null) return Future.value(Success(cached));

    final pending = _inFlight;
    if (pending != null) return pending;

    final started = _fetchFastPosition(timeLimit);
    _inFlight = started;
    started.whenComplete(() {
      if (_inFlight == started) _inFlight = null;
    });
    return started;
  }

  Future<Result<Position, LocationFailure>> _fetchFastPosition(
    Duration timeLimit,
  ) async {
    try {
      final position = await _determinePosition(timeLimit: timeLimit);
      _cachePosition(position);
      _logger.i(
          '$_tag: Fast toạ độ → lat=${position.latitude}, lng=${position.longitude}');
      return Success(position);
    } catch (e, st) {
      _logger.w('$_tag: Fast location failed/timeout ($e), thử fallback...');
      if (_lastKnownPosition != null) {
        _logger.i(
            '$_tag: Dùng _lastKnownPosition cache → lat=${_lastKnownPosition!.latitude}, lng=${_lastKnownPosition!.longitude}');
        return Success(_lastKnownPosition!);
      }
      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null) {
          _cachePosition(lastKnown);
          _logger.i(
              '$_tag: Dùng Geolocator.getLastKnownPosition() → lat=${lastKnown.latitude}, lng=${lastKnown.longitude}');
          return Success(lastKnown);
        }
      } catch (_) {}

      _logger.e('$_tag: Fast location exception, không có fallback', e, st);
      return FailureResult(LocationFailure(e.toString()));
    }
  }

  /// Chỉ lấy toạ độ GPS (không geocode), hữu ích khi chỉ cần lat/lng.
  ///
  /// Trả về [Result]:
  /// - [Success] với [Position] nếu thành công.
  /// - [FailureResult] với [LocationFailure] nếu xảy ra lỗi.
  Future<Result<Position, LocationFailure>> getCurrentPosition() async {
    try {
      final position = await _determinePosition();
      _logger.i(
          '$_tag: Toạ độ → lat=${position.latitude}, lng=${position.longitude}');
      return Success(position);
    } on LocationException catch (e, st) {
      _logger.e('$_tag: LocationException', e, st);
      return FailureResult(
          LocationFailure(e.message ?? 'Không thể lấy toạ độ'));
    } catch (e, st) {
      _logger.e('$_tag: Unexpected error', e, st);
      return FailureResult(
          const LocationFailure('Lỗi không xác định khi lấy toạ độ'));
    }
  }

  /// Reverse geocoding từ toạ độ cho trước, không cần GPS.
  ///
  /// Trả về [Result]:
  /// - [Success] với [LocationData] nếu thành công.
  /// - [FailureResult] với [LocationFailure] nếu xảy ra lỗi.
  Future<Result<LocationData, LocationFailure>> getAddressFromCoordinates({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final locationData = await _geocodePosition(
        _FakePosition(latitude: latitude, longitude: longitude),
      );
      _logger.i(
          '$_tag: Geocode ($latitude, $longitude) → ${locationData.formattedAddress}');
      return Success(locationData);
    } on LocationException catch (e, st) {
      _logger.e('$_tag: LocationException', e, st);
      return FailureResult(
          LocationFailure(e.message ?? 'Không thể geocode toạ độ'));
    } catch (e, st) {
      _logger.e('$_tag: Unexpected error', e, st);
      return FailureResult(
          const LocationFailure('Lỗi không xác định khi geocode'));
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Kiểm tra quyền và trả về [Position] hiện tại.
  Future<Position> _determinePosition({
    Duration timeLimit = const Duration(seconds: 15),
  }) async {
    // 1. Kiểm tra location service có bật không
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const LocationException(
        'Dịch vụ vị trí bị tắt. Vui lòng bật GPS trên thiết bị.',
      );
    }

    // 2. Kiểm tra quyền truy cập
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const LocationException(
          'Quyền truy cập vị trí bị từ chối.',
        );
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationException(
        'Quyền truy cập vị trí bị từ chối vĩnh viễn. '
        'Vui lòng cấp quyền trong Cài đặt ứng dụng.',
      );
    }

    // 3. Lấy vị trí
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeLimit,
        ),
      );
      _cachePosition(pos);
      return pos;
    } catch (e) {
      throw LocationException('Không thể lấy vị trí GPS: $e');
    }
  }

  /// Reverse geocode một [_PositionLike] (lat/lng) thành [LocationData].
  Future<LocationData> _geocodePosition(_PositionLike pos) async {
    List<Placemark> placemarks;
    try {
      placemarks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
    } catch (e) {
      _logger.w('$_tag: Geocoding thất bại, trả về toạ độ thô. Error: $e');
      // Nếu geocoding thất bại, vẫn trả về toạ độ mà không có địa chỉ
      return LocationData(
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
    }

    if (placemarks.isEmpty) {
      return LocationData(
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
    }

    final place = placemarks.first;
    final street = _buildStreet(place);
    final city = place.locality?.isNotEmpty == true
        ? place.locality
        : place.administrativeArea;

    final formattedAddress = _buildFormattedAddress(place);

    return LocationData(
      latitude: pos.latitude,
      longitude: pos.longitude,
      formattedAddress: formattedAddress,
      street: street,
      district: place.subLocality,
      city: city,
      country: place.country,
      postalCode: place.postalCode,
    );
  }

  String? _buildStreet(Placemark place) {
    final parts = [
      if (place.subThoroughfare?.isNotEmpty == true) place.subThoroughfare,
      if (place.thoroughfare?.isNotEmpty == true) place.thoroughfare,
    ];
    return parts.isEmpty ? null : parts.join(' ');
  }

  String? _buildFormattedAddress(Placemark place) {
    final parts = [
      if (place.subThoroughfare?.isNotEmpty == true) place.subThoroughfare,
      if (place.thoroughfare?.isNotEmpty == true) place.thoroughfare,
      if (place.subLocality?.isNotEmpty == true) place.subLocality,
      if (place.locality?.isNotEmpty == true)
        place.locality
      else if (place.administrativeArea?.isNotEmpty == true)
        place.administrativeArea,
      if (place.country?.isNotEmpty == true) place.country,
    ];
    if (parts.isEmpty) return null;
    return parts.join(', ');
  }
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Interface tối giản cho lat/lng, dùng nội bộ để tránh phụ thuộc
/// vào [Position] khi gọi [getAddressFromCoordinates].
abstract class _PositionLike {
  double get latitude;
  double get longitude;
}

class _FakePosition implements _PositionLike {
  @override
  final double latitude;
  @override
  final double longitude;
  const _FakePosition({required this.latitude, required this.longitude});
}
