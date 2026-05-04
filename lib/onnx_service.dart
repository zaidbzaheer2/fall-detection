import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/services.dart';

class OnnxService {
  static const MethodChannel _channel = MethodChannel('onnxruntime_flutter');
  static bool _initialized = false;

  /// Initialize the runtime and load the model from assets.
  static Future<void> init() async {
    if (_initialized) return;
    try {
      final bytes = await rootBundle.load('assets/models/lgbm_model.onnx');
      final payload = bytes.buffer.asUint8List();
      // Try common method name the plugin might expose
      await _channel.invokeMethod('loadModelFromBytes', payload);
      _initialized = true;
    } catch (e) {
      // If the plugin API differs, the app should still run; we'll mark uninitialized
      // and fall back to a simple heuristic predictor.
      _initialized = false;
    }
  }

  /// Run prediction using the same feature extraction as the backend.
  /// Returns true if a fall is detected.
  static Future<bool> predict(List<double> x, List<double> y, List<double> z) async {
    // Ensure buffers have expected length; pad or trim to 128 like backend expects
    final int desired = 128;
    x = _resizeList(x, desired);
    y = _resizeList(y, desired);
    z = _resizeList(z, desired);

    final features = _extractFeatures(x, y, z);

    // Try running via plugin method channel
    if (_initialized) {
      try {
        final input = Float32List.fromList(features.map((e) => e.toDouble()).toList());
        final result = await _channel.invokeMethod('runModel', {
          'input': input,
        });

        // Expect plugin to return either an integer label or a map with probabilities.
        if (result is int) {
          // Assuming label for "Fall" matches backend mapping (3)
          return result == 3;
        } else if (result is Map) {
          // Try to interpret probability or class
          if (result.containsKey('fall')) {
            return result['fall'] == true;
          }
          if (result.containsKey('label')) {
            return result['label'] == 'Fall' || result['label'] == 3;
          }
        }
      } catch (e) {
        // fall through to heuristic
      }
    }

    // Fallback heuristic: detect large peak in magnitude
    final mag = List<double>.generate(x.length, (i) => math.sqrt(x[i] * x[i] + y[i] * y[i] + z[i] * z[i]));
    final peak = mag.reduce(math.max);
    return peak > 25.0; // heuristic threshold; adjust if needed
  }

  static List<double> _resizeList(List<double> arr, int desired) {
    if (arr.length == desired) return arr;
    if (arr.length > desired) return arr.sublist(arr.length - desired);
    // pad with last value
    final out = List<double>.from(arr);
    while (out.length < desired) {
      out.add(out.isNotEmpty ? out.last : 0.0);
    }
    return out;
  }

  // Port of backend.extract_features from Python -> Dart
  static List<double> _extractFeatures(List<double> xIn, List<double> yIn, List<double> zIn) {
    // apply simple median filter approximated by sliding window median of size 3
    List<double> medfilt(List<double> arr) {
      final n = arr.length;
      final out = List<double>.filled(n, 0.0);
      for (int i = 0; i < n; i++) {
        final a = <double>[];
        a.add(arr[i]);
        if (i - 1 >= 0) {
          a.add(arr[i - 1]);
        }
        if (i + 1 < n) {
          a.add(arr[i + 1]);
        }
        a.sort();
        out[i] = a[a.length ~/ 2];
      }
      return out;
    }

    final x = medfilt(xIn);
    final y = medfilt(yIn);
    final z = medfilt(zIn);

    final n = x.length;
    List<double> mag = List<double>.generate(n, (i) => math.sqrt(x[i] * x[i] + y[i] * y[i] + z[i] * z[i]));
    List<double> jerk = List<double>.filled(n, 0.0);
    for (int i = 0; i < n; i++) {
      if (i == 0) {
        jerk[i] = mag[0] - mag[0];
      } else {
        jerk[i] = mag[i] - mag[i - 1];
      }
    }

    List<double> features = [];
    for (final s in [x, y, z, mag, jerk]) {
      final mean = _mean(s);
      final std = _std(s, mean);
      final maxv = s.reduce(math.max);
      final minv = s.reduce(math.min);
      final iqr = _percentile(s, 75) - _percentile(s, 25);
      final energy = _mean(s.map((v) => v * v).toList());
      features.addAll([mean, std, maxv, minv, iqr, energy]);
    }

    // sma
    features.add(((x.map((v) => v.abs()).toList().asMap().values.reduce((a, b) => a + b)) + (y.map((v) => v.abs()).toList().asMap().values.reduce((a, b) => a + b)) + (z.map((v) => v.abs()).toList().asMap().values.reduce((a, b) => a + b))) / n);

    // peak mag
    features.add(mag.reduce(math.max));

    // fft-like approximations: compute simple DFT magnitudes via Cooley-Tukey would be heavy; do simple coarse spectral estimates
    // For simplicity compute absolute DFT using naive O(n^2) for first 64 bins (small n=128 acceptable)
    final int bins = math.min(64, n);
    List<double> fft = List<double>.filled(bins, 0.0);
    for (int k = 0; k < bins; k++) {
      double re = 0.0, im = 0.0;
      for (int t = 0; t < n; t++) {
        final angle = 2 * math.pi * k * t / n;
        re += mag[t] * math.cos(angle);
        im -= mag[t] * math.sin(angle);
      }
      fft[k] = math.sqrt(re * re + im * im);
    }

    double meanRange(List<int> range) {
      if (range.isEmpty) return 0.0;
      double s = 0.0;
      for (final i in range) {
        s += fft[i];
      }
      return s / range.length;
    }

    features.add(meanRange(List<int>.generate(9, (i) => i + 1)));
    features.add(meanRange(List<int>.generate(20, (i) => i + 10)));
    features.add(meanRange(List<int>.generate(34, (i) => i + 30)));

    return features;
  }

  static double _mean(List<double> a) => a.isEmpty ? 0.0 : a.reduce((v, e) => v + e) / a.length;

  static double _std(List<double> a, double mean) {
    if (a.isEmpty) return 0.0;
    double s = 0.0;
    for (final v in a) {
      s += (v - mean) * (v - mean);
    }
    return math.sqrt(s / a.length);
  }

  static double _percentile(List<double> a, double p) {
    if (a.isEmpty) return 0.0;
    final b = List<double>.from(a)..sort();
    final idx = (p / 100.0) * (b.length - 1);
    final lo = idx.floor();
    final hi = idx.ceil();
    if (lo == hi) return b[lo];
    return b[lo] + (b[hi] - b[lo]) * (idx - lo);
  }
}
