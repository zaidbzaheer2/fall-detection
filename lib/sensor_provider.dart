import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SensorProvider with ChangeNotifier {
  static const String baseUrl = 'http://192.168.100.91:8000'; // Laptop local IP
  
  final List<double> _xBuffer = [];
  final List<double> _yBuffer = [];
  final List<double> _zBuffer = [];
  
  int _newSamplesCount = 0;
  bool _isProcessing = false;
  bool _isInCooldown = false;
  String? _email;
  
  StreamSubscription<AccelerometerEvent>? _subscription;
  
  // Gravity components for High-Pass Filter
  double _gx = 0, _gy = 0, _gz = 0;
  static const double _alpha = 0.8;
  
  List<double> get xBuffer => _xBuffer;
  List<double> get yBuffer => _yBuffer;
  List<double> get zBuffer => _zBuffer;
  
  bool get isRecording => _subscription != null;

  SensorProvider() {
    _loadEmail();
  }

  Future<void> _loadEmail() async {
    final prefs = await SharedPreferences.getInstance();
    _email = prefs.getString('emergency_email');
  }

  void startListening() {
    if (_subscription != null) return;
    
    _xBuffer.clear();
    _yBuffer.clear();
    _zBuffer.clear();
    _newSamplesCount = 0;

    // accelerometerEventStream includes gravity
    _subscription = accelerometerEventStream(samplingPeriod: const Duration(milliseconds: 40)).listen((AccelerometerEvent event) {
      if (_isInCooldown) return;
      
      // // High-pass filter to remove gravity and get linear acceleration
      // _gx = _alpha * _gx + (1 - _alpha) * event.x;
      // _gy = _alpha * _gy + (1 - _alpha) * event.y;
      // _gz = _alpha * _gz + (1 - _alpha) * event.z;

      _xBuffer.add(event.x);
      _yBuffer.add(event.y);
      _zBuffer.add(event.z);
      
      // Keep only the last 128 samples for visualization/processing
      if (_xBuffer.length > 128) {
        _xBuffer.removeAt(0);
        _yBuffer.removeAt(0);
        _zBuffer.removeAt(0);
      }
      
      _newSamplesCount++;
      
      // Every 64 new samples, if we have a full buffer (128), send to backend
      if (_newSamplesCount >= 64 && _xBuffer.length == 128 && !_isProcessing) {
        _newSamplesCount = 0;
        _sendDataToBackend();
      }
      
      notifyListeners();
    });
  }

  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    notifyListeners();
  }

  Future<void> _sendDataToBackend() async {
    if (_email == null) {
      await _loadEmail();
      if (_email == null) return;
    }

    _isProcessing = true;
    
    // Copy current buffer to avoid race conditions if needed
    final x = List<double>.from(_xBuffer);
    final y = List<double>.from(_yBuffer);
    final z = List<double>.from(_zBuffer);

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/predict'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'x': x,
          'y': y,
          'z': z,
          'email': _email,
        }),
      ).timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);
        if (result['fall_detected'] == true) {
          // You might want to handle this globally or via a callback
          _onFallDetected();
        }
      }
    } catch (e) {
      debugPrint('Error sending data to backend: $e');
    } finally {
      _isProcessing = false;
    }
  }

  // Fall detection callback/event
  Function? onFallDetected;

  void _onFallDetected() {
    if (_isInCooldown) return;
    
    _isInCooldown = true;
    
    // Clear buffers and reset counter immediately
    _xBuffer.clear();
    _yBuffer.clear();
    _zBuffer.clear();
    _newSamplesCount = 0;
    
    if (onFallDetected != null) {
      onFallDetected!();
    }
    
    // Resume after 10 seconds (no API calls are sent during cooldown due to early return in listener)
    Timer(const Duration(seconds: 10), () {
      _isInCooldown = false;
      notifyListeners();
    });
    
    notifyListeners();
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
}
