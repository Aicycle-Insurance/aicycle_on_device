//  LicensePlateOCR — standalone CoreML license-plate recognizer (CCT model).
//
//  This is NOT a YOLO detector: it expects an already-cropped license-plate image
//  and returns the recognized plate string. Ported from the reference pipeline in
//  license_plate_ocr/coreml/license_plate_ocr_coreml.py.
//
//  Input : MLMultiArray [1, 64, 128, 3] float32, raw 0–255, RGB, NHWC.
//  Output: MLMultiArray reshapeable to [1, 12, 39] (12 char slots × 39 alphabet).

import CoreImage
import CoreML
import CoreVideo
import Foundation
import UIKit

final class LicensePlateOCR {
  // Geometry / vocabulary — must match the trained model.
  private let imgWidth = 128
  private let imgHeight = 64
  private let numSlots = 12
  private let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-._")
  private let padChar: Character = "_"
  private let specialChars = ["NG", "NN"]

  /// Minimum mean digit-confidence for a read to be accepted.
  var threshold: Double

  private let model: MLModel
  private let inputName: String
  private let outputName: String

  /// TODO(remove before production): ensures only one debug input image is saved.
  private static var didSaveDebugInput = false

  /// Shared CIContext — creating one per frame is expensive.
  private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

  /// Loads (and compiles, if needed) the CoreML model at [url]. Heavy — call off
  /// the main thread.
  init?(modelURL url: URL, threshold: Double = 0.85) {
    self.threshold = threshold
    do {
      let loaded: MLModel
      if url.pathExtension.lowercased() == "mlmodelc" {
        loaded = try MLModel(contentsOf: url)
      } else {
        let compiled = try MLModel.compileModel(at: url)
        loaded = try MLModel(contentsOf: compiled)
      }
      self.model = loaded

      let desc = loaded.modelDescription
      guard let inName = desc.inputDescriptionsByName.keys.first,
        let outName = desc.outputDescriptionsByName.keys.first
      else {
        NSLog("LicensePlateOCR: model has no input/output descriptions")
        return nil
      }
      self.inputName = inName
      self.outputName = outName
    } catch {
      NSLog("LicensePlateOCR: failed to load model: %@", error.localizedDescription)
      return nil
    }
  }

  // MARK: - Public API

  /// Recognizes a plate inside [pixelBuffer] limited to the normalized [region]
  /// (top-left origin, values in [0,1] relative to the buffer). Returns the
  /// formatted plate string and its confidence, or nil if nothing valid is read.
  func read(pixelBuffer: CVPixelBuffer, region: CGRect) -> (plate: String, score: Double)? {
    guard let input = makeInput(from: pixelBuffer, region: region) else { return nil }
    do {
      let provider = try MLDictionaryFeatureProvider(dictionary: [inputName: input])
      let out = try model.prediction(from: provider)
      guard let tensor = out.featureValue(for: outputName)?.multiArrayValue else {
        return nil
      }
      return postprocess(tensor)
    } catch {
      NSLog("LicensePlateOCR: inference failed: %@", error.localizedDescription)
      return nil
    }
  }

  // MARK: - Preprocess

  /// Crops [region] from the buffer, resizes to 128×64, and packs RGB float32
  /// (raw 0–255, NHWC) into an MLMultiArray [1,64,128,3].
  private func makeInput(from pixelBuffer: CVPixelBuffer, region: CGRect) -> MLMultiArray? {
    let bw = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
    let bh = CGFloat(CVPixelBufferGetHeight(pixelBuffer))

    // Clamp the normalized region to the buffer and convert to pixels (top-left).
    let nx = max(0, min(1, region.minX))
    let ny = max(0, min(1, region.minY))
    let nmaxX = max(0, min(1, region.maxX))
    let nmaxY = max(0, min(1, region.maxY))
    let px = nx * bw
    let py = ny * bh
    let pw = (nmaxX - nx) * bw
    let ph = (nmaxY - ny) * bh
    guard pw >= 1, ph >= 1 else { return nil }

    let ci = CIImage(cvPixelBuffer: pixelBuffer)
    // CIImage uses a bottom-left origin; flip the crop rect's Y accordingly.
    let cropRect = CGRect(x: px, y: bh - py - ph, width: pw, height: ph)
    guard let cg = ciContext.createCGImage(ci, from: cropRect) else { return nil }

    return packRGB(from: cg)
  }

  /// Draws [cgImage] into a 128×64 RGBA8 context and copies the RGB channels into
  /// a float32 MLMultiArray [1,64,128,3] (raw 0–255).
  private func packRGB(from cgImage: CGImage) -> MLMultiArray? {
    let w = imgWidth
    let h = imgHeight
    let bytesPerRow = w * 4
    var pixels = [UInt8](repeating: 0, count: w * h * 4)

    guard
      let ctx = CGContext(
        data: &pixels,
        width: w,
        height: h,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }

    // Bilinear resize via the draw call (matches cv2.INTER_LINEAR closely enough).
    ctx.interpolationQuality = .high
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

    // TODO(remove before production): dump the exact 128×64 model input once so
    // the crop+resize can be eyeballed in the Photos app.
    if !Self.didSaveDebugInput, let dbg = ctx.makeImage() {
      Self.didSaveDebugInput = true
      let img = UIImage(cgImage: dbg)
      DispatchQueue.main.async {
        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
        NSLog("[OCR] saved debug input (128x64) to Photos")
      }
    }

    guard let array = try? MLMultiArray(shape: [1, NSNumber(value: h), NSNumber(value: w), 3], dataType: .float32)
    else { return nil }
    let ptr = array.dataPointer.bindMemory(to: Float32.self, capacity: array.count)

    var dst = 0
    var src = 0
    for _ in 0..<h {
      for _ in 0..<w {
        // RGBA source → RGB destination, raw 0–255 (no normalization).
        ptr[dst] = Float32(pixels[src])      // R
        ptr[dst + 1] = Float32(pixels[src + 1])  // G
        ptr[dst + 2] = Float32(pixels[src + 2])  // B
        dst += 3
        src += 4
      }
    }
    return array
  }

  // MARK: - Postprocess

  /// Decodes the [1,12,39] logits into a validated Vietnamese plate string.
  private func postprocess(_ tensor: MLMultiArray) -> (plate: String, score: Double)? {
    let classes = alphabet.count  // 39
    guard tensor.count >= numSlots * classes else { return nil }
    let ptr = tensor.dataPointer.bindMemory(to: Float32.self, capacity: tensor.count)

    var rawChars: [Character] = []
    var scores: [Double] = []
    for t in 0..<numSlots {
      var bestIdx = 0
      var bestVal = -Float.greatestFiniteMagnitude
      let base = t * classes
      for k in 0..<classes {
        let v = ptr[base + k]
        if v > bestVal {
          bestVal = v
          bestIdx = k
        }
      }
      let ch = alphabet[bestIdx]
      if ch == padChar { continue }  // drop padding
      rawChars.append(ch)
      scores.append(Double(bestVal))
    }

    let joined = String(rawChars)
    let cleaned = joined.filter { $0 != "." && $0 != "-" && $0 != "_" }

    // TODO(remove before production): raw OCR decode log.
    NSLog("[OCR] raw=\"%@\" cleaned=\"%@\"", joined, cleaned)

    if cleaned.count < 7 {
      NSLog("[OCR] reject: len<7 (%d)", cleaned.count)
      return nil
    }
    if cleaned.count == 7 && rawChars.contains(".") {
      NSLog("[OCR] reject: 7 chars but dot present")
      return nil
    }

    // Format: 2 digits + 1–2 letters, then the remaining digits → "30H 12345".
    var finalPlate: String? = nil
    if let m = matchVietnamPlate(cleaned) {
      finalPlate = "\(m.0) \(m.1)"
    } else if specialChars.contains(where: { joined.contains($0) }) {
      finalPlate = cleaned
    }
    guard let plate = finalPlate else {
      NSLog("[OCR] reject: no VN plate format")
      return nil
    }

    // Confidence = mean score over the DIGIT characters only.
    var digitScores: [Double] = []
    for (ch, s) in zip(rawChars, scores) where ch.isNumber {
      digitScores.append(s)
    }
    guard !digitScores.isEmpty else {
      NSLog("[OCR] reject: no digit scores")
      return nil
    }
    let finalScore = digitScores.reduce(0, +) / Double(digitScores.count)

    // TODO(remove before production): final score vs threshold.
    NSLog("[OCR] plate=\"%@\" score=%.3f thr=%.2f -> %@",
      plate, finalScore, threshold, finalScore > threshold ? "ACCEPT" : "below-thr")

    return finalScore > threshold ? (plate, finalScore) : nil
  }

  /// Matches `^(\d{2}[A-Za-z]{1,2})(\d+)$`, returning the two capture groups.
  private func matchVietnamPlate(_ s: String) -> (String, String)? {
    let pattern = "^(\\d{2}[A-Za-z]{1,2})(\\d+)$"
    guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(s.startIndex..<s.endIndex, in: s)
    guard let match = re.firstMatch(in: s, range: range),
      let r1 = Range(match.range(at: 1), in: s),
      let r2 = Range(match.range(at: 2), in: s)
    else { return nil }
    return (String(s[r1]), String(s[r2]))
  }
}
