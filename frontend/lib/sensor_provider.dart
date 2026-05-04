import 'dart:async';
import 'package:flutter/foundation.dart';
import 'onnx_service.dart';
import 'email_service.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SensorProvider with ChangeNotifier {
  
  final List<double> _xBuffer = [];
  final List<double> _yBuffer = [];
  final List<double> _zBuffer = [];
  
  int _newSamplesCount = 0;
  bool _isProcessing = false;
  bool _isPaused = false; // Pause recording but keep readings
  bool _emailSent = false;
  
  int _emailCountdown = 0;
  Timer? _emailCountdownTimer;
  
  StreamSubscription<AccelerometerEvent>? _subscription;
  
  // Gravity components for High-Pass Filter
  double _gx = 0, _gy = 0, _gz = 0;
  static const double _alpha = 0.8;
  
  List<double> get xBuffer => _xBuffer;
  List<double> get yBuffer => _yBuffer;
  List<double> get zBuffer => _zBuffer;
  
  bool get isRecording => _subscription != null;
  bool get isPaused => _isPaused;
  int get emailCountdown => _emailCountdown;
  bool get emailSent => _emailSent;

  SensorProvider() {
    // initialize onnx model in background
    OnnxService.init();
  }

  void startListening() {
    if (_subscription != null) return;
    
    _xBuffer.clear();
    _yBuffer.clear();
    _zBuffer.clear();
    _newSamplesCount = 0;
    _isPaused = false;
    _emailCountdown = 0;
    _emailSent = false;

    // accelerometerEventStream includes gravity
    _subscription = accelerometerEventStream(samplingPeriod: const Duration(milliseconds: 40)).listen((AccelerometerEvent event) {
      // Always add to buffer for visualization (even during pause)
      _xBuffer.add(event.x);
      _yBuffer.add(event.y);
      _zBuffer.add(event.z);
      
      // Keep only the last 128 samples for visualization/processing
      if (_xBuffer.length > 128) {
        _xBuffer.removeAt(0);
        _yBuffer.removeAt(0);
        _zBuffer.removeAt(0);
      }
      
      // Only process/record if not paused
      if (!_isPaused) {
        _newSamplesCount++;
        
        // Every 64 new samples, if we have a full buffer (128), send to backend
        if (_newSamplesCount >= 64 && _xBuffer.length == 128 && !_isProcessing) {
          _newSamplesCount = 0;
          _runLocalInference();
        }
      }
      
      notifyListeners();
    });
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    notifyListeners();
  }

  Future<void> _runLocalInference() async {
    _isProcessing = true;

    // Copy current buffer to avoid race conditions if needed
    final x = List<double>.from(_xBuffer);
    final y = List<double>.from(_yBuffer);
    final z = List<double>.from(_zBuffer);

    try {
      final fall = await OnnxService.predict(x, y, z);
      if (fall) {
        _onFallDetected();
      }
    } catch (e) {
      debugPrint('Error running local inference: $e');
    } finally {
      _isProcessing = false;
    }
  }

  // Fall detection callback/event
  Function? onFallDetected;

  void _onFallDetected() {
    _isPaused = true;
    _emailCountdown = 10;
    _emailSent = false;
    
    if (onFallDetected != null) {
      onFallDetected!();
    }
    
    // Start countdown timer for email sending
    _emailCountdownTimer?.cancel();
    _emailCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _emailCountdown--;
      notifyListeners();
      
      if (_emailCountdown <= 0) {
        timer.cancel();
        if (!_emailSent) {
          _sendFallAlertEmail();
        }
      }
    });
    
    notifyListeners();
  }
  
  /// Cancel the pending email and resume normal operation
  Future<void> dismissAlert() async {
    _emailCountdownTimer?.cancel();
    _isPaused = false;
    _emailCountdown = 0;
    _emailSent = true; // Mark as handled to prevent sending
    _newSamplesCount = 0;
    notifyListeners();
  }
  
  /// Send the fall alert email to the emergency contact
  Future<void> _sendFallAlertEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final emergencyEmail = prefs.getString('emergency_email');
      
      if (emergencyEmail != null && emergencyEmail.isNotEmpty) {
        final success = await EmailService.sendFallAlert(emergencyEmail, 'User');
        if (success) {
          _emailSent = true;
          debugPrint('Fall alert email sent successfully to $emergencyEmail');
        }
      }
    } catch (e) {
      debugPrint('Error sending fall alert email: $e');
    }
    
    // Resume after the full 10 seconds pause
    Timer(const Duration(seconds: 10), () {
      _isPaused = false;
      notifyListeners();
    });
    
    notifyListeners();
  }

  @override
  void dispose() {
    stopListening();
    _emailCountdownTimer?.cancel();
    super.dispose();
  }
}
