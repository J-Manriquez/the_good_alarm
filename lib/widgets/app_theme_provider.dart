import 'package:flutter/material.dart';

import '../services/app_theme_controller.dart';

class AppThemeProvider extends InheritedNotifier<AppThemeController> {
  const AppThemeProvider({
    super.key,
    required AppThemeController controller,
    required Widget child,
  }) : super(notifier: controller, child: child);

  static AppThemeController of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<AppThemeProvider>();
    if (provider == null || provider.notifier == null) {
      throw StateError('AppThemeProvider no encontrado en el árbol de widgets');
    }
    return provider.notifier!;
  }
}

