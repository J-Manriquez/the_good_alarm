import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'firebase_options.dart';
import 'home_page.dart';
import 'alarm_screen.dart';
import 'calendar_screen.dart';
import 'settings_screen.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/app_theme_controller.dart';
import 'widgets/app_theme_provider.dart';
import 'screens/medication_alert_screen.dart';
import 'screens/medication_confirm_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('alarms_box');
  await Hive.openBox('alarm_sync_box');
  await Hive.openBox('habits_box');
  await Hive.openBox('habit_completions_box');
  await Hive.openBox('habit_sync_box');
  await Hive.openBox('medications_box');
  await Hive.openBox('medication_completions_box');
  await Hive.openBox('medication_sync_box');
  await Hive.openBox('calendars_box');
  await Hive.openBox('calendar_events_box');
  await Hive.openBox('calendar_overrides_box');
  await Hive.openBox('calendar_occurrences_box');
  await Hive.openBox('calendar_sync_box');
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return _ThemedApp();
  }
}

class _ThemedApp extends StatefulWidget {
  @override
  State<_ThemedApp> createState() => _ThemedAppState();
}

class _ThemedAppState extends State<_ThemedApp> {
  final AppThemeController _themeController = AppThemeController();

  @override
  void initState() {
    super.initState();
    _themeController.init();
  }

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppThemeProvider(
      controller: _themeController,
      child: AnimatedBuilder(
        animation: _themeController,
        builder: (context, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'The Good Alarm',
            theme: _themeController.themeData,
            initialRoute: '/home',
            routes: {
              '/home': (context) => const HomeShell(),
              '/login': (context) => const LoginScreen(),
              '/alarm': (context) => AlarmScreen(
                arguments:
                    ModalRoute.of(context)?.settings.arguments
                        as Map<String, dynamic>?,
              ),
              '/calendar': (context) => const HomeShell(initialTabIndex: 0),
              '/settings': (context) => const SettingsScreen(),
              '/medication': (context) => MedicationAlertScreen(
                arguments: ModalRoute.of(context)?.settings.arguments
                    as Map<String, dynamic>?,
              ),
              '/medication_confirm': (context) => MedicationConfirmScreen(
                arguments: ModalRoute.of(context)?.settings.arguments
                    as Map<String, dynamic>?,
              ),
            },
          );
        },
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData) {
          return const HomeShell();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}

// La clase Alarm se movió a home_page.dart
// Las clases HomePage y _HomePageState se movieron a home_page.dart
// Las clases AlarmScreen y _AlarmScreenState se movieron a alarm_screen.dart
