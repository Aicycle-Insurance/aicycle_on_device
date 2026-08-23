## Unreleased

* Add a thermal governor: native watches the device thermal state and throttles
  each model's inference rate as the device heats up (carDamage 10/5/2.5 fps,
  carCorner, carPart and license-plate OCR scaled alongside). Behaviour at the
  normal tier is unchanged. The current tier is streamed to Dart as a
  `type == "thermal"` event and exposed via `CameraController.thermalStatus`.
* Split the camera overlay rebuilds: damage boxes and car-part labels now ride
  their own `ValueNotifier`s, so a per-frame inference result no longer rebuilds
  the top bar, bottom bar, progress ring, tooltip and capture overlays.
* Resolve the bottom-bar thumbnail path once per capture instead of running two
  `File.existsSync()` calls on every rebuild.

## 0.1.11

- Slow down auto-capture pacing so users have time to prepare

## 0.1.10

- update AppColor

## 0.1.9

- Enhance damage detection logic

## 0.1.8

- Update capture effects and timing for better user experience

## 0.1.7

- Add SDK flag to upload data

## 0.1.6

- Improve photo upload queue management with better error handling and response delivery.
- Update AI model management to streamline model validation and path preparation processes.
- Refactor camera controller logic to optimize OCR reading and user prompts for clearer instructions.

## 0.1.5

- Enhance CameraFrameCorners success indication and timing for photo captures
- Update timing for continueOrChange message and related scanning delays

## 0.1.4

- Improve camera inspection tooltip timing and priority handling
- Update damage inspection auto-capture flow and detail-photo guidance
- Fix progress ring completion state when 4-angle panoramic capture is disabled

## 0.1.3

- Fix bugs and update auto capture flow

## 0.1.2

- Update OCR viewport margins for improved license plate detection accuracy

## 0.1.1

- Add License Plate OCR functionality
- Implement phase-based gating for OCR and carDamage models
- Enhance OCR functionality with improved CPU handling and user guidance

## 0.1.0

- Prevent uploading to AICycle server twice

## 0.0.9

- Add filter model output to viewport

## 0.0.8

- Fix download models issue

## 0.0.7

- Fix bugs and enhance performance

## 0.0.6

- Fix bugs and enhance performance

## 0.0.5

- Move aicycle_yolo to local
- Fix bugs and enhance performance

## 0.0.4

- Un-public PhotoSessionCache
- Update README.md

## 0.0.3

- Update README.md

## 0.0.2

- Update new UI/UX
- Fix bugs

## 0.0.1

- AICycle On Device
