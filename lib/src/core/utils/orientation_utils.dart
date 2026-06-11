import 'package:native_device_orientation/native_device_orientation.dart';

class OrientationUtils {
  OrientationUtils._();

  /// Chuyển đổi [NativeDeviceOrientation] thành số quý (quarter turns) để sử dụng với [RotatedBox].
  static int getQuarterTurns(NativeDeviceOrientation orientation) {
    switch (orientation) {
      case NativeDeviceOrientation.portraitUp:
        return 0;
      case NativeDeviceOrientation.landscapeLeft:
        return 1;
      case NativeDeviceOrientation.portraitDown:
        return 2;
      case NativeDeviceOrientation.landscapeRight:
        return 3;
      default:
        return 0;
    }
  }

  /// Chuyển đổi [NativeDeviceOrientation] thành số vòng quay (turns) để sử dụng với [Transform.rotate].
  static double getTurns(NativeDeviceOrientation orientation) {
    switch (orientation) {
      case NativeDeviceOrientation.portraitUp:
        return 0;
      case NativeDeviceOrientation.landscapeLeft:
        return 0.25;
      case NativeDeviceOrientation.portraitDown:
        return 0.5;
      case NativeDeviceOrientation.landscapeRight:
        return 0.75;
      default:
        return 0;
    }
  }
}
