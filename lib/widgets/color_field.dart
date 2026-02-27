import 'package:flutter/material.dart';

/// Campo de color empresarial reutilizable
/// - Mantiene la misma estructura y estilos del ColorInputWidget existente
/// - Añade un modal superior con selector de color dinámico al tocar el cuadrado de color
class ColorField extends StatefulWidget {
  final String? initialColor;
  final ValueChanged<String> onColorChanged; // Siempre devuelve un color (no null)
  final String label;

  const ColorField({
    super.key,
    this.initialColor,
    required this.onColorChanged,
    this.label = 'Color',
  });

  @override
  State<ColorField> createState() => _ColorFieldState();
}

class _ColorFieldState extends State<ColorField> {
  final TextEditingController _controller = TextEditingController();
  Color? _previewColor;
  String? _errorMessage;
  String _lastValidColorString = '#00000000'; // Siempre mantenemos un color válido
  final FocusNode _focusNode = FocusNode();
  bool _isActiveEffect = false; // efecto animado (focus o texto no vacío)

  @override
  void initState() {
    super.initState();
    // Inicialización con color inicial o color del tema como respaldo
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scheme = Theme.of(context).colorScheme;
      final fallback = _colorToHex(scheme.primary);
      _lastValidColorString = widget.initialColor?.trim().isNotEmpty == true
          ? widget.initialColor!.trim()
          : fallback;

      _controller.text = _lastValidColorString;
      final c = _parseColor(_lastValidColorString);
      setState(() {
        _previewColor = c ?? scheme.primary;
        _errorMessage = null;
        // Animación desactivada al abrir (sin depender del texto)
        _isActiveEffect = false;
      });
      widget.onColorChanged(_lastValidColorString);
    });

    _focusNode.addListener(() {
      setState(() {
        // Solo depende del foco
        _isActiveEffect = _focusNode.hasFocus;
      });
    });
    // Eliminamos el listener del controller para que el efecto no dependa del texto
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Color _hslToColor(double h, double s, double l, double a) {
    h = h / 360.0;
    double r, g, b;
    if (s == 0) {
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
      String cleanColor = colorString.trim().toLowerCase().replaceAll(' ', '');
      if (cleanColor.startsWith('#')) {
        cleanColor = cleanColor.substring(1);
        if (cleanColor.length == 3) {
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
    } catch (_) {}
    return null;
  }

  String _colorToHex(Color color, {bool includeAlpha = false}) {
    final r = color.red.toRadixString(16).padLeft(2, '0');
    final g = color.green.toRadixString(16).padLeft(2, '0');
    final b = color.blue.toRadixString(16).padLeft(2, '0');
    if (includeAlpha) {
      final a = color.alpha.toRadixString(16).padLeft(2, '0');
      return '#$a$r$g$b'.toUpperCase();
    }
    return '#$r$g$b'.toUpperCase();
  }

  void _validateAndSetColor(String value) {
    if (value.isEmpty) {
      setState(() {
        _errorMessage = null;
      });
      // No cambiamos el color seleccionado al vaciar; mantenemos el último válido
      _controller.text = _lastValidColorString;
      return;
    }
    final Color? color = _parseColor(value);
    if (color != null) {
      setState(() {
        _previewColor = color;
        _errorMessage = null;
        _lastValidColorString = value;
      });
      widget.onColorChanged(_lastValidColorString);
    } else {
      setState(() {
        _errorMessage = 'Formato de color inválido';
      });
      // No emitimos valor inválido; mantenemos el último color válido
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

  String _formatColorString(Color color, String format) {
    final r = color.red;
    final g = color.green;
    final b = color.blue;
    final a = (color.alpha / 255.0);
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
        return _colorToHex(color, includeAlpha: color.alpha < 255);
    }
  }

  void _openColorPicker() async {
    FocusScope.of(context).unfocus();
    final workingColor = _previewColor ?? Theme.of(context).colorScheme.primary;
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

  Widget _buildSliderRow(
    BuildContext context, {
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final primary = scheme.primary;
    final onSurface = scheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: onSurface,
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
          activeColor: primary,
          inactiveColor: primary.withOpacity(0.3),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = scheme.primary;
    final onSurface = scheme.onSurface;
    final surface = scheme.surface;
    final outline = scheme.outline;
    final surfaceContainer = scheme.surfaceContainerHighest;

    final suffix = _previewColor != null
        ? GestureDetector(
            onTap: _openColorPicker,
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
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            color: surfaceContainer,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: outline.withOpacity(0.6),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1 * (_isActiveEffect ? 1.0 : 0.0)),
                blurRadius: 6 * (_isActiveEffect ? 1.0 : 0.0),
                offset: Offset(0, 8 * (_isActiveEffect ? 1.0 : 0.0)),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _controller,
                    focusNode: _focusNode,
                    decoration: InputDecoration(
                      labelText: widget.label,
                      labelStyle: TextStyle(color: onSurface.withOpacity(0.7)),
                      border: InputBorder.none,
                      prefixIcon: Icon(Icons.palette, color: primary),
                      errorText: _errorMessage,
                      suffixIcon: suffix,
                    ),
                    style: TextStyle(color: onSurface),
                    onChanged: _validateAndSetColor,
                    onTapOutside: (_) => _focusNode.unfocus(),
                    validator: (value) {
                      if (value != null && value.isNotEmpty && _parseColor(value) == null) {
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
          ),
        ),
        if (_previewColor != null) ...[
          const SizedBox(height: 12),
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
                  color: _previewColor!.computeLuminance() > 0.5 ? Colors.black : Colors.white,
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
  late double hue = HSVColor.fromColor(widget.initialColor).hue;
  late double sat = HSVColor.fromColor(widget.initialColor).saturation;
  late double val = HSVColor.fromColor(widget.initialColor).value;
  late double alpha = widget.initialColor.alpha / 255.0;
  late String format = widget.initialFormat;

  String _colorToHex(Color color, {bool includeAlpha = false}) {
    final r = color.red.toRadixString(16).padLeft(2, '0');
    final g = color.green.toRadixString(16).padLeft(2, '0');
    final b = color.blue.toRadixString(16).padLeft(2, '0');
    if (includeAlpha) {
      final a = color.alpha.toRadixString(16).padLeft(2, '0');
      return '#$a$r$g$b'.toUpperCase();
    }
    return '#$r$g$b'.toUpperCase();
  }

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final primary = scheme.primary;
    final onSurface = scheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: onSurface, fontSize: 13, fontWeight: FontWeight.w500),
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: (max - min) == 360 ? 360 : 100,
          onChanged: onChanged,
          activeColor: primary,
          inactiveColor: primary.withOpacity(0.3),
        ),
      ],
    );
  }

  List<Color> _hueStops() {
    final stops = <double>[0, 60, 120, 180, 240, 300, 360];
    return stops.map((h) => HSVColor.fromAHSV(1.0, h, 1.0, 1.0).toColor()).toList();
  }

  Widget _hueStrip() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scheme = Theme.of(context).colorScheme;
        final primary = scheme.primary;
        final border = scheme.outline.withOpacity(0.35);
        final w = constraints.maxWidth;
        final x = (hue / 360.0) * w;
        void update(Offset p) {
          final dx = p.dx.clamp(0.0, w);
          setState(() {
            hue = (dx / w) * 360.0;
          });
        }

        return GestureDetector(
          onHorizontalDragStart: (d) => update(d.localPosition),
          onHorizontalDragUpdate: (d) => update(d.localPosition),
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
                    colors: _hueStops(),
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
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _spectrumSV() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scheme = Theme.of(context).colorScheme;
        final primary = scheme.primary;
        final border = scheme.outline.withOpacity(0.35);
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final indicatorX = sat.clamp(0.0, 1.0) * w;
        final indicatorY = (1.0 - val.clamp(0.0, 1.0)) * h;

        void update(Offset local) {
          final dx = local.dx.clamp(0.0, w);
          final dy = local.dy.clamp(0.0, h);
          setState(() {
            sat = (dx / w).clamp(0.0, 1.0);
            val = (1.0 - (dy / h)).clamp(0.0, 1.0);
          });
        }

        final pureHue = HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
        final preview = HSVColor.fromAHSV(alpha, hue, sat, val).toColor();

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

  String _formatColorString(Color color, String format) {
    final r = color.red;
    final g = color.green;
    final b = color.blue;
    final a = (color.alpha / 255.0);
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
        return _colorToHex(color, includeAlpha: color.alpha < 255);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final primary = scheme.primary;
    final surface = scheme.surface;
    final onSurface = scheme.onSurface;
    final preview = HSVColor.fromAHSV(alpha, hue, sat, val).toColor();
    final textColor = preview.computeLuminance() > 0.5 ? Colors.black : Colors.white;

    return Scaffold(
      backgroundColor: surface,
      appBar: AppBar(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        title: const Text('Selector de color'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 34, 24),
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
                        _formatColorString(preview, format),
                        style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _hueStrip(),
            const SizedBox(height: 16),
            SizedBox(height: 200, child: _spectrumSV()),
            const SizedBox(height: 16),
            _buildSliderRow(
              label: 'Brillo',
              value: val,
              min: 0,
              max: 1,
              onChanged: (v) => setState(() => val = v),
            ),
            _buildSliderRow(
              label: 'Opacidad',
              value: alpha,
              min: 0,
              max: 1,
              onChanged: (v) => setState(() => alpha = v),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: primary.withOpacity(0.2)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: format,
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
                    onChanged: (v) => setState(() => format = v ?? 'HEX'),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
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
                    onPressed: () {
                      final chosen = HSVColor.fromAHSV(alpha, hue, sat, val).toColor();
                      Navigator.of(context).pop(_formatColorString(chosen, format));
                    },
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
    final Paint border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = borderColor;

    final Paint fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color;

    final double radius = 10;
    final Offset center = Offset(x, y);
    canvas.drawCircle(center, radius, fill);
    canvas.drawCircle(center, radius + 1.5, border);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const double cell = 10.0;
    final Paint light = Paint()..color = const Color(0xFFEFEFEF);
    final Paint dark = Paint()..color = const Color(0xFFCCCCCC);
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        final bool isDark = (((x / cell).floor() + (y / cell).floor()) % 2) == 0;
        canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), isDark ? dark : light);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
