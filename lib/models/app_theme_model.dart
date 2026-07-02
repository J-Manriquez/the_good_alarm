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
  final AppTypographyScale typography;
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
    required this.typography,
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
      typography: const AppTypographyScale.defaults(),
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
      'typography': typography.toMap(),
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
      typography: AppTypographyScale.fromMap(
        map['typography'] is Map
            ? Map<String, dynamic>.from(map['typography'] as Map)
            : null,
      ),
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
    AppTypographyScale? typography,
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
      typography: typography ?? this.typography,
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
    final normalizedTypography = typography.normalized();

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
          fontSize: normalizedTypography.medium,
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

    final scaledTextTheme = base.textTheme
        .copyWith(
          bodySmall: base.textTheme.bodySmall?.copyWith(
            fontSize: normalizedTypography.small,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            fontSize: normalizedTypography.body,
          ),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(
            fontSize: normalizedTypography.medium,
          ),
          labelSmall: base.textTheme.labelSmall?.copyWith(
            fontSize: normalizedTypography.small,
          ),
          labelMedium: base.textTheme.labelMedium?.copyWith(
            fontSize: normalizedTypography.body,
          ),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontSize: normalizedTypography.body,
          ),
          titleSmall: base.textTheme.titleSmall?.copyWith(
            fontSize: normalizedTypography.medium,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontSize: normalizedTypography.medium,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontSize: normalizedTypography.title,
          ),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontSize: normalizedTypography.display,
          ),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontSize: normalizedTypography.display,
          ),
          headlineLarge: base.textTheme.headlineLarge?.copyWith(
            fontSize: normalizedTypography.display,
          ),
          displaySmall: base.textTheme.displaySmall?.copyWith(
            fontSize: normalizedTypography.display,
          ),
          displayMedium: base.textTheme.displayMedium?.copyWith(
            fontSize: normalizedTypography.display,
          ),
          displayLarge: base.textTheme.displayLarge?.copyWith(
            fontSize: normalizedTypography.display,
          ),
        )
        .apply(displayColor: onSurface, bodyColor: onSurface);

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

class AppTypographyScale {
  final double small;
  final double body;
  final double medium;
  final double title;
  final double display;

  const AppTypographyScale({
    required this.small,
    required this.body,
    required this.medium,
    required this.title,
    required this.display,
  });

  const AppTypographyScale.defaults()
    : small = 12,
      body = 16,
      medium = 20,
      title = 28,
      display = 40;

  factory AppTypographyScale.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const AppTypographyScale.defaults();
    const defaults = AppTypographyScale.defaults();
    return AppTypographyScale(
      small: _parseSize(map['small'], defaults.small),
      body: _parseSize(map['body'], defaults.body),
      medium: _parseSize(map['medium'], defaults.medium),
      title: _parseSize(map['title'], defaults.title),
      display: _parseSize(map['display'], defaults.display),
    ).normalized();
  }

  Map<String, dynamic> toMap() {
    return {
      'small': small,
      'body': body,
      'medium': medium,
      'title': title,
      'display': display,
    };
  }

  AppTypographyScale copyWith({
    double? small,
    double? body,
    double? medium,
    double? title,
    double? display,
  }) {
    return AppTypographyScale(
      small: small ?? this.small,
      body: body ?? this.body,
      medium: medium ?? this.medium,
      title: title ?? this.title,
      display: display ?? this.display,
    );
  }

  AppTypographyScale normalized() {
    final nextSmall = _sanitize(small, min: 10, max: 16, fallback: 12);
    final nextBody = _sanitize(body, min: nextSmall + 1, max: 20, fallback: 16);
    final nextMedium = _sanitize(
      medium,
      min: nextBody + 1,
      max: 24,
      fallback: 20,
    );
    final nextTitle = _sanitize(
      title,
      min: nextMedium + 1,
      max: 36,
      fallback: 28,
    );
    final nextDisplay = _sanitize(
      display,
      min: nextTitle + 1,
      max: 60,
      fallback: 40,
    );
    return AppTypographyScale(
      small: nextSmall,
      body: nextBody,
      medium: nextMedium,
      title: nextTitle,
      display: nextDisplay,
    );
  }

  double resolve(double originalFontSize) {
    final source = originalFontSize.isFinite && originalFontSize > 0
        ? originalFontSize
        : body;
    final normalizedScale = normalized();
    if (source <= 12.5) return normalizedScale.small;
    if (source <= 16.5) return normalizedScale.body;
    if (source <= 22.5) return normalizedScale.medium;
    if (source <= 30.5) return normalizedScale.title;
    return normalizedScale.display;
  }

  static double _parseSize(Object? raw, double fallback) {
    final value = (raw is num)
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '');
    return value ?? fallback;
  }

  static double _sanitize(
    double value, {
    required double min,
    required double max,
    required double fallback,
  }) {
    final safeValue = value.isFinite ? value : fallback;
    return safeValue.clamp(min, max).roundToDouble();
  }
}

class AppTypographyTextScaler extends TextScaler {
  const AppTypographyTextScaler({
    required this.typography,
    required this.textScale,
  });

  final AppTypographyScale typography;
  final double textScale;

  @override
  double scale(double fontSize) {
    return typography.resolve(fontSize) * textScaleFactor;
  }

  @override
  double get textScaleFactor => textScale.clamp(0.6, 1.8);
}
