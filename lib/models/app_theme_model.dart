import 'package:flutter/material.dart';

class AppThemeModel {
  final String id;
  final String name;
  final String backgroundColor;
  final String surfaceColor;
  final String textColor;
  final String primaryColor;
  final String secondaryColor;
  final String tertiaryColor;
  final double textScale;
  final int updatedAtMs;

  const AppThemeModel({
    required this.id,
    required this.name,
    required this.backgroundColor,
    required this.surfaceColor,
    required this.textColor,
    required this.primaryColor,
    required this.secondaryColor,
    required this.tertiaryColor,
    required this.textScale,
    required this.updatedAtMs,
  });

  static AppThemeModel defaultDark() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return AppThemeModel(
      id: 'default_dark',
      name: 'Oscuro (por defecto)',
      backgroundColor: '#FF000000',
      surfaceColor: '#FF111111',
      textColor: '#FFFFFFFF',
      primaryColor: '#FF00C853',
      secondaryColor: '#FFFF6D00',
      tertiaryColor: '#FFAA00FF',
      textScale: 1.0,
      updatedAtMs: now,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'backgroundColor': backgroundColor,
      'surfaceColor': surfaceColor,
      'textColor': textColor,
      'primaryColor': primaryColor,
      'secondaryColor': secondaryColor,
      'tertiaryColor': tertiaryColor,
      'textScale': textScale,
      'updatedAtMs': updatedAtMs,
    };
  }

  factory AppThemeModel.fromMap(Map<String, dynamic> map) {
    return AppThemeModel(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      backgroundColor: (map['backgroundColor'] ?? '#FF000000').toString(),
      surfaceColor: (map['surfaceColor'] ?? '#FF111111').toString(),
      textColor: (map['textColor'] ?? '#FFFFFFFF').toString(),
      primaryColor: (map['primaryColor'] ?? '#FF00C853').toString(),
      secondaryColor: (map['secondaryColor'] ?? '#FFFF6D00').toString(),
      tertiaryColor: (map['tertiaryColor'] ?? '#FFAA00FF').toString(),
      textScale: (map['textScale'] is num)
          ? (map['textScale'] as num).toDouble()
          : double.tryParse((map['textScale'] ?? '1.0').toString()) ?? 1.0,
      updatedAtMs: (map['updatedAtMs'] is num)
          ? (map['updatedAtMs'] as num).toInt()
          : int.tryParse((map['updatedAtMs'] ?? '0').toString()) ?? 0,
    );
  }

  AppThemeModel copyWith({
    String? id,
    String? name,
    String? backgroundColor,
    String? surfaceColor,
    String? textColor,
    String? primaryColor,
    String? secondaryColor,
    String? tertiaryColor,
    double? textScale,
    int? updatedAtMs,
  }) {
    return AppThemeModel(
      id: id ?? this.id,
      name: name ?? this.name,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      surfaceColor: surfaceColor ?? this.surfaceColor,
      textColor: textColor ?? this.textColor,
      primaryColor: primaryColor ?? this.primaryColor,
      secondaryColor: secondaryColor ?? this.secondaryColor,
      tertiaryColor: tertiaryColor ?? this.tertiaryColor,
      textScale: textScale ?? this.textScale,
      updatedAtMs: updatedAtMs ?? this.updatedAtMs,
    );
  }

  ThemeData toThemeData() {
    final bg = _parseHexColor(backgroundColor) ?? const Color(0xFF000000);
    final surface = _parseHexColor(surfaceColor) ?? const Color(0xFF111111);
    final onSurface = _parseHexColor(textColor) ?? const Color(0xFFFFFFFF);
    final primary = _parseHexColor(primaryColor) ?? const Color(0xFF00C853);
    final secondary = _parseHexColor(secondaryColor) ?? const Color(0xFFFF6D00);
    final tertiary = _parseHexColor(tertiaryColor) ?? const Color(0xFFAA00FF);

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        tertiary: tertiary,
        surface: surface,
        onSurface: onSurface,
        onPrimary: onSurface,
        onSecondary: onSurface,
        onTertiary: onSurface,
        outline: primary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: onSurface,
        iconTheme: IconThemeData(color: onSurface),
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: primary, width: 1),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return onSurface;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return primary.withOpacity(0.35);
          }
          return onSurface.withOpacity(0.2);
        }),
      ),
    );

    final scaledTextTheme = base.textTheme.apply(
      fontSizeFactor: textScale.clamp(0.6, 1.8),
      displayColor: onSurface,
      bodyColor: onSurface,
    );

    return base.copyWith(textTheme: scaledTextTheme);
  }

  static Color? _parseHexColor(String input) {
    final raw = input.trim().replaceAll('#', '');
    if (raw.isEmpty) return null;
    final normalized = (raw.length == 6) ? 'FF$raw' : raw;
    if (normalized.length != 8) return null;
    final value = int.tryParse(normalized, radix: 16);
    if (value == null) return null;
    return Color(value);
  }
}
