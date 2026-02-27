import 'package:flutter/material.dart';

final MaterialColor customColor = Colors.green;

class ColorInputWidget extends StatefulWidget {
  final String? initialColor;
  final Function(String?) onColorChanged;
  final ValueChanged<Color?>? onParsedColorChanged;
  final String label;

  const ColorInputWidget({
    super.key,
    this.initialColor,
    required this.onColorChanged,
    this.onParsedColorChanged,
    this.label = 'Color',
  });

  @override
  State<ColorInputWidget> createState() => _ColorInputWidgetState();
}

class _ColorInputWidgetState extends State<ColorInputWidget> {
  final TextEditingController _controller = TextEditingController();
  Color? _previewColor;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.initialColor != null) {
      _controller.text = widget.initialColor!;
      // Diferir la validación hasta después del build para evitar setState durante build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _validateAndSetColor(widget.initialColor!);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _hslToColor(double h, double s, double l, double a) {
    // Normalizar el hue a un rango de 0-1
    h = h / 360.0;
    
    double r, g, b;
    
    if (s == 0) {
      // Escala de grises
      r = g = b = l;
    } else {
      double hue2rgb(double p, double q, double t) {
        if (t < 0) t += 1;
        if (t > 1) t -= 1;
        if (t < 1/6) return p + (q - p) * 6 * t;
        if (t < 1/2) return q;
        if (t < 2/3) return p + (q - p) * (2/3 - t) * 6;
        return p;
      }
      
      final double q = l < 0.5 ? l * (1 + s) : l + s - l * s;
      final double p = 2 * l - q;
      
      r = hue2rgb(p, q, h + 1/3);
      g = hue2rgb(p, q, h);
      b = hue2rgb(p, q, h - 1/3);
    }
    
    return Color.fromRGBO(
      (r * 255).round(),
      (g * 255).round(),
      (b * 255).round(),
      a,
    );
  }

  Color? _parseColor(String colorString) {
    try {
      String cleanColor = colorString.trim().toLowerCase();
      
      // Remover espacios y caracteres especiales
      cleanColor = cleanColor.replaceAll(' ', '');
      
      // Formato hexadecimal (#RRGGBB o #RGB)
      if (cleanColor.startsWith('#')) {
        cleanColor = cleanColor.substring(1);
        
        if (cleanColor.length == 3) {
          // Convertir #RGB a #RRGGBB
          cleanColor = cleanColor.split('').map((c) => c + c).join();
        }
        
        if (cleanColor.length == 6) {
          final int value = int.parse(cleanColor, radix: 16);
          return Color(0xFF000000 | value);
        }
        
        if (cleanColor.length == 8) {
          final int value = int.parse(cleanColor, radix: 16);
          return Color(value);
        }
      }
      
      // Formato RGB (rgb(r, g, b))
      if (cleanColor.startsWith('rgb(') && cleanColor.endsWith(')')) {
        final String values = cleanColor.substring(4, cleanColor.length - 1);
        final List<String> parts = values.split(',');
        
        if (parts.length == 3) {
          final int r = int.parse(parts[0].trim());
          final int g = int.parse(parts[1].trim());
          final int b = int.parse(parts[2].trim());
          
          if (r >= 0 && r <= 255 && g >= 0 && g <= 255 && b >= 0 && b <= 255) {
            return Color.fromRGBO(r, g, b, 1.0);
          }
        }
      }
      
      // Formato RGBA (rgba(r, g, b, a))
      if (cleanColor.startsWith('rgba(') && cleanColor.endsWith(')')) {
        final String values = cleanColor.substring(5, cleanColor.length - 1);
        final List<String> parts = values.split(',');
        
        if (parts.length == 4) {
          final int r = int.parse(parts[0].trim());
          final int g = int.parse(parts[1].trim());
          final int b = int.parse(parts[2].trim());
          final double a = double.parse(parts[3].trim());
          
          if (r >= 0 && r <= 255 && g >= 0 && g <= 255 && b >= 0 && b <= 255 && a >= 0.0 && a <= 1.0) {
            return Color.fromRGBO(r, g, b, a);
          }
        }
      }
      
      // Formato HSL (hsl(h, s%, l%))
      if (cleanColor.startsWith('hsl(') && cleanColor.endsWith(')')) {
        final String values = cleanColor.substring(4, cleanColor.length - 1);
        final List<String> parts = values.split(',');
        
        if (parts.length == 3) {
          final double h = double.parse(parts[0].trim());
          final double s = double.parse(parts[1].trim().replaceAll('%', '')) / 100.0;
          final double l = double.parse(parts[2].trim().replaceAll('%', '')) / 100.0;
          
          if (h >= 0 && h <= 360 && s >= 0.0 && s <= 1.0 && l >= 0.0 && l <= 1.0) {
            return _hslToColor(h, s, l, 1.0);
          }
        }
      }
      
      // Formato HSLA (hsla(h, s%, l%, a))
      if (cleanColor.startsWith('hsla(') && cleanColor.endsWith(')')) {
        final String values = cleanColor.substring(5, cleanColor.length - 1);
        final List<String> parts = values.split(',');
        
        if (parts.length == 4) {
          final double h = double.parse(parts[0].trim());
          final double s = double.parse(parts[1].trim().replaceAll('%', '')) / 100.0;
          final double l = double.parse(parts[2].trim().replaceAll('%', '')) / 100.0;
          final double a = double.parse(parts[3].trim());
          
          if (h >= 0 && h <= 360 && s >= 0.0 && s <= 1.0 && l >= 0.0 && l <= 1.0 && a >= 0.0 && a <= 1.0) {
            return _hslToColor(h, s, l, a);
          }
        }
      }
      
      // Colores predefinidos
      final Map<String, Color> namedColors = {
        'red': Colors.red,
        'blue': Colors.blue,
        'green': Colors.green,
        'yellow': Colors.yellow,
        'orange': Colors.orange,
        'purple': Colors.purple,
        'pink': Colors.pink,
        'cyan': Colors.cyan,
        'teal': Colors.teal,
        'indigo': Colors.indigo,
        'brown': Colors.brown,
        'grey': Colors.grey,
        'gray': Colors.grey,
        'black': Colors.black,
        'white': Colors.white,
        'transparent': Colors.transparent,
      };
      
      if (namedColors.containsKey(cleanColor)) {
        return namedColors[cleanColor];
      }
      
    } catch (e) {
      // Error al parsear
    }
    
    return null;
  }

  void _validateAndSetColor(String value) {
    if (value.isEmpty) {
      setState(() {
        _previewColor = null;
        _errorMessage = null;
      });
      widget.onColorChanged(null);
      widget.onParsedColorChanged?.call(null);
      return;
    }

    final Color? color = _parseColor(value);
    
    if (color != null) {
      setState(() {
        _previewColor = color;
        _errorMessage = null;
      });
      widget.onColorChanged(value);
      widget.onParsedColorChanged?.call(color);
    } else {
      setState(() {
        _previewColor = null;
        _errorMessage = 'Formato de color inválido';
      });
      widget.onColorChanged(null);
      widget.onParsedColorChanged?.call(null);
    }
  }

  String _getHelpText() {
    return 'Formatos soportados:\n'
           '• Hexadecimal: #FF0000, #F00\n'
           '• RGB: rgb(255, 0, 0)\n'
           '• RGBA: rgba(255, 0, 0, 1.0)\n'
           '• HSL: hsl(0, 100%, 50%)\n'
           '• HSLA: hsla(0, 100%, 50%, 1.0)\n'
           '• Nombres: red, blue, green, etc.';
  }

  Future<void> _openTopColorPicker() async {
    FocusScope.of(context).unfocus();
    final workingColor = _previewColor ?? customColor.shade600;
    final selectedString = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => _ColorPickerScreen(
          initialColor: workingColor,
          initialFormat: 'HEX',
        ),
      ),
    );
    if (selectedString != null && selectedString.isNotEmpty) {
      _controller.text = selectedString;
      _validateAndSetColor(selectedString);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final primary = scheme.primary;
    final onSurface = scheme.onSurface;
    final surface = scheme.surface;
    final outline = scheme.outline;
    final surfaceContainer = theme.colorScheme.surfaceContainerHighest;
    final swatches = <Color>[
      Colors.black,
      Colors.white,
      customColor.shade50,
      customColor.shade100,
      customColor.shade200,
      customColor.shade300,
      customColor.shade400,
      customColor.shade500,
      customColor.shade600,
      customColor.shade700,
      customColor.shade800,
      customColor.shade900,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: swatches.map((c) {
            final selected = _previewColor?.toARGB32() == c.toARGB32();
            return InkWell(
              onTap: () {
                final hex = '#${c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase()}';
                _controller.text = hex;
                _validateAndSetColor(hex);
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    width: selected ? 3 : 1,
                    color: selected ? primary : outline,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _controller,
                decoration: InputDecoration(
                  labelText: widget.label,
                  labelStyle: TextStyle(color: onSurface.withOpacity(0.8)),
                  filled: true,
                  fillColor: surfaceContainer,
                  prefixIcon: Icon(Icons.palette, color: primary),
                  errorText: _errorMessage,
                  suffixIcon: _previewColor != null
                      ? GestureDetector(
                          onTap: _openTopColorPicker,
                          child: Container(
                            margin: const EdgeInsets.all(8),
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: _previewColor,
                              border: Border.all(color: primary),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        )
                      : null,
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: outline.withOpacity(0.6)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: primary, width: 2),
                  ),
                ),
                style: TextStyle(color: onSurface),
                onChanged: _validateAndSetColor,
                validator: (value) {
                  if (value != null && value.isNotEmpty && _previewColor == null) {
                    return 'Formato de color inválido';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: primary, width: 1),
                    ),
                    title: Text(
                      'Formatos de Color',
                      style: TextStyle(color: onSurface, fontWeight: FontWeight.bold),
                    ),
                    content: Text(
                      _getHelpText(),
                      style: TextStyle(color: onSurface.withOpacity(0.8)),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(foregroundColor: onSurface),
                        child: const Text('Cerrar'),
                      ),
                    ],
                  ),
                );
              },
              icon: Icon(Icons.help_outline, color: primary),
              tooltip: 'Ver formatos soportados',
            ),
          ],
        ),
        if (_previewColor != null) ...[
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            height: 40,
            decoration: BoxDecoration(
              color: _previewColor,
              border: Border.all(color: primary),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                'Vista previa del color',
                style: TextStyle(
                  color: _previewColor!.computeLuminance() > 0.5 
                      ? Colors.black 
                      : Colors.white,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SpectrumIndicatorPainter extends CustomPainter {
  final double x;
  final double y;
  final Color color;
  final Color borderColor;

  _SpectrumIndicatorPainter({
    required this.x,
    required this.y,
    required this.color,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = borderColor;
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color;
    const radius = 10.0;
    final center = Offset(x, y);
    canvas.drawCircle(center, radius, fill);
    canvas.drawCircle(center, radius + 1.5, border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _ColorPickerScreen extends StatefulWidget {
  const _ColorPickerScreen({
    required this.initialColor,
    required this.initialFormat,
  });

  final Color initialColor;
  final String initialFormat;

  @override
  State<_ColorPickerScreen> createState() => _ColorPickerScreenState();
}

class _ColorPickerScreenState extends State<_ColorPickerScreen> {
  late double _hue = HSVColor.fromColor(widget.initialColor).hue;
  late double _sat = HSVColor.fromColor(widget.initialColor).saturation;
  late double _val = HSVColor.fromColor(widget.initialColor).value;
  late double _alpha = widget.initialColor.alpha / 255.0;
  late String _format = widget.initialFormat;

  String _hexFor(Color c, {required bool includeAlpha}) {
    final argb = c.toARGB32();
    final a = ((argb >> 24) & 0xff).toRadixString(16).padLeft(2, '0');
    final r = ((argb >> 16) & 0xff).toRadixString(16).padLeft(2, '0');
    final g = ((argb >> 8) & 0xff).toRadixString(16).padLeft(2, '0');
    final b = (argb & 0xff).toRadixString(16).padLeft(2, '0');
    return includeAlpha ? '#$a$r$g$b'.toUpperCase() : '#$r$g$b'.toUpperCase();
  }

  String _formatColorString(Color color, String format) {
    final r = color.red;
    final g = color.green;
    final b = color.blue;
    final a = (color.alpha / 255.0).clamp(0.0, 1.0);
    switch (format) {
      case 'RGB':
        return 'rgb($r, $g, $b)';
      case 'RGBA':
        return 'rgba($r, $g, $b, ${a.toStringAsFixed(2)})';
      case 'HSL':
        final hsl = HSLColor.fromColor(color);
        final h = hsl.hue.round();
        final s = (hsl.saturation * 100).round();
        final l = (hsl.lightness * 100).round();
        return 'hsl($h, $s%, $l%)';
      case 'HSLA':
        final hsl = HSLColor.fromColor(color);
        final h = hsl.hue.round();
        final s = (hsl.saturation * 100).round();
        final l = (hsl.lightness * 100).round();
        return 'hsla($h, $s%, $l%, ${a.toStringAsFixed(2)})';
      case 'HEX':
      default:
        return _hexFor(color, includeAlpha: a < 1.0);
    }
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required Color activeColor,
    required Color labelColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: labelColor.withOpacity(0.85),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: (max - min) == 360 ? 360 : 100,
          onChanged: onChanged,
          activeColor: activeColor,
          inactiveColor: activeColor.withOpacity(0.3),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final primary = scheme.primary;
    final surface = scheme.surface;
    final onSurface = scheme.onSurface;
    final border = scheme.outline.withOpacity(0.35);
    final preview = HSVColor.fromAHSV(_alpha, _hue, _sat, _val).toColor();
    final previewTextColor =
        preview.computeLuminance() > 0.5 ? Colors.black : Colors.white;

    List<Color> hueStops() {
      final stops = <double>[0, 60, 120, 180, 240, 300, 360];
      return stops.map((h) => HSVColor.fromAHSV(1.0, h, 1.0, 1.0).toColor()).toList();
    }

    Widget hueStrip() {
      return LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final x = (_hue / 360.0) * w;
          void update(Offset p) {
            final dx = p.dx.clamp(0.0, w);
            setState(() => _hue = (dx / w) * 360.0);
          }

          return GestureDetector(
            onPanStart: (d) => update(d.localPosition),
            onPanUpdate: (d) => update(d.localPosition),
            onTapDown: (d) => update(d.localPosition),
            child: Stack(
              children: [
                Container(
                  height: 24,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: border),
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: hueStops(),
                    ),
                  ),
                ),
                Positioned(
                  left: x - 8,
                  top: 2,
                  child: Container(
                    width: 16,
                    height: 20,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: primary, width: 2),
                      color: Colors.white.withOpacity(0.75),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    Widget spectrumSV() {
      return LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = constraints.maxHeight;
          final indicatorX = (_sat.clamp(0.0, 1.0)) * w;
          final indicatorY = (1.0 - _val.clamp(0.0, 1.0)) * h;

          void update(Offset local) {
            final dx = local.dx.clamp(0.0, w);
            final dy = local.dy.clamp(0.0, h);
            setState(() {
              _sat = (dx / w).clamp(0.0, 1.0);
              _val = (1.0 - (dy / h)).clamp(0.0, 1.0);
            });
          }

          final pureHue = HSVColor.fromAHSV(1.0, _hue, 1.0, 1.0).toColor();

          return GestureDetector(
            onPanStart: (d) => update(d.localPosition),
            onPanUpdate: (d) => update(d.localPosition),
            onTapDown: (d) => update(d.localPosition),
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: border),
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [Colors.white, pureHue],
                    ),
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black],
                    ),
                  ),
                ),
                CustomPaint(
                  painter: _SpectrumIndicatorPainter(
                    x: indicatorX,
                    y: indicatorY,
                    color: preview,
                    borderColor: primary,
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Selector de color'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 26, 16),
          children: [
            Container(
              height: 70,
              decoration: BoxDecoration(
                border: Border.all(color: primary, width: 2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CustomPaint(painter: _CheckerPainter()),
                    Container(color: preview),
                    Center(
                      child: Text(
                        _formatColorString(preview, _format),
                        style: TextStyle(
                          color: previewTextColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            hueStrip(),
            const SizedBox(height: 16),
            SizedBox(height: 220, child: spectrumSV()),
            const SizedBox(height: 16),
            _buildSliderRow(
              label: 'Brillo',
              value: _val,
              min: 0,
              max: 1,
              onChanged: (v) => setState(() => _val = v),
              activeColor: primary,
              labelColor: onSurface,
            ),
            _buildSliderRow(
              label: 'Opacidad',
              value: _alpha,
              min: 0,
              max: 1,
              onChanged: (v) => setState(() => _alpha = v),
              activeColor: primary,
              labelColor: onSurface,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: primary.withOpacity(0.25)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _format,
                    dropdownColor: surface,
                    style: TextStyle(color: onSurface),
                    isDense: true,
                    icon: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'HEX', child: Text('HEX')),
                      DropdownMenuItem(value: 'RGB', child: Text('RGB')),
                      DropdownMenuItem(value: 'RGBA', child: Text('RGBA')),
                      DropdownMenuItem(value: 'HSL', child: Text('HSL')),
                      DropdownMenuItem(value: 'HSLA', child: Text('HSLA')),
                    ],
                    onChanged: (v) => setState(() => _format = v ?? 'HEX'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primary,
                      side: BorderSide(color: primary),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Cancelar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(
                      _formatColorString(preview, _format),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Aplicar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const cell = 10.0;
    final light = Paint()..color = const Color(0xFFEFEFEF);
    final dark = Paint()..color = const Color(0xFFCCCCCC);
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final isDark = (((x / cell).floor() + (y / cell).floor()) % 2) == 0;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), isDark ? dark : light);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
