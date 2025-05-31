import 'package:flutter/material.dart';
// No es necesario importar 'package:flutter/services.dart' aquí si MethodChannel se maneja en las pantallas individuales.
// No es necesario importar 'dart:async' ni 'dart:convert' aquí.
// No es necesario importar 'package:shared_preferences/shared_preferences.dart' aquí.

import 'home_page.dart'; // Importar la nueva pantalla HomePage
import 'alarm_screen.dart'; // Importar la nueva pantalla AlarmScreen

// Mover la constante platform a los archivos donde se usa (HomePage y AlarmScreen)
// const platform = MethodChannel('com.example.the_good_alarm/alarm');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Good Alarm',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const HomePage(),
        '/alarm': (context) => AlarmScreen(
          arguments: ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?,
        ),
      },
    );
  }
}

// La clase Alarm se movió a home_page.dart
// Las clases HomePage y _HomePageState se movieron a home_page.dart
// Las clases AlarmScreen y _AlarmScreenState se movieron a alarm_screen.dart
