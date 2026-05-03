import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'sensor_provider.dart';
import 'onboarding_screen.dart';
import 'main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final prefs = await SharedPreferences.getInstance();
  final bool onboardingCompleted = prefs.getBool('onboarding_completed') ?? false;
  
  runApp(MyApp(onboardingCompleted: onboardingCompleted));
}

class MyApp extends StatefulWidget {
  final bool onboardingCompleted;
  const MyApp({super.key, required this.onboardingCompleted});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late SensorProvider _sensorProvider;

  @override
  void initState() {
    super.initState();
    _sensorProvider = SensorProvider();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fall Detection',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.redAccent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      initialRoute: widget.onboardingCompleted ? '/main' : '/onboarding',
      routes: {
        '/onboarding': (context) => const OnboardingScreen(),
        '/main': (context) => MainScreen(provider: _sensorProvider),
      },
    );
  }

  @override
  void dispose() {
    _sensorProvider.dispose();
    super.dispose();
  }
}
