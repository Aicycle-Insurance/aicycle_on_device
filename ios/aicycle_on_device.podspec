#
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint aicycle_on_device.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'aicycle_on_device'
  s.version          = '0.0.4'
  s.summary          = 'AICycle On-Device SDK for Flutter (embeds YOLO inference).'
  s.description      = <<-DESC
AICycle On-Device SDK for Flutter. Bundles the YOLO multi-task camera inference
(object detection + classification) used by the AICycle inspection flow, based on
Ultralytics YOLO.
                       DESC
  s.homepage         = 'https://github.com/Aicycle-Insurance'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'AICycle' => 'info@aicycle.ai' }
  s.source           = { :path => '.' }
  s.source_files = 'aicycle_on_device/Sources/aicycle_on_device/**/*.{swift,h,m}'
  s.dependency 'Flutter'
  s.dependency 'UltralyticsYOLO', '>= 8.9.5', '< 9.0'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  s.resource_bundles = {'aicycle_on_device_privacy' => ['aicycle_on_device/Sources/aicycle_on_device/PrivacyInfo.xcprivacy']}
end
