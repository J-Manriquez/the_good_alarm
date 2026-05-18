import 'package:flutter/material.dart';

import '../models/medication_models.dart';
import '../services/medication_repository.dart';

class MedicationHistoryScreen extends StatefulWidget {
  final MedicationModel medication;

  const MedicationHistoryScreen({super.key, required this.medication});

  @override
  State<MedicationHistoryScreen> createState() =>
      _MedicationHistoryScreenState();
}

class _MedicationHistoryScreenState extends State<MedicationHistoryScreen> {
  final MedicationRepository _repo = MedicationRepository();

  bool _loading = true;
  List<MedicationCompletionModel> _completions = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    print('[MedicationHistoryScreen] cargando historial para ${widget.medication.id}');
    setState(() => _loading = true);
    try {
      final items = await _repo.loadLocalCompletionsForMedication(
        widget.medication.id,
      );
      print('[MedicationHistoryScreen] ${items.length} registros cargados');
      if (mounted) setState(() => _completions = items);
    } catch (e) {
      print('[MedicationHistoryScreen] error cargando historial: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final med = widget.medication;

    // Color de la tarjeta del medicamento
    final headerColor = med.colorHex.isNotEmpty
        ? Color(int.tryParse(med.colorHex.replaceFirst('#', '0xFF')) ??
            scheme.primaryContainer.value)
        : scheme.primaryContainer;
    final isLight =
        ThemeData.estimateBrightnessForColor(headerColor) == Brightness.light;
    final onHeader = isLight ? Colors.black87 : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: Text('Historial · ${med.medicationName}'),
        backgroundColor: headerColor,
        foregroundColor: onHeader,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _completions.isEmpty
              ? _buildEmpty(scheme)
              : _buildList(scheme, med),
    );
  }

  Widget _buildEmpty(ColorScheme scheme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.history, size: 72,
              color: scheme.onSurface.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            'Sin registros aún',
            style: TextStyle(
                fontSize: 16, color: scheme.onSurface.withValues(alpha: 0.5)),
          ),
          const SizedBox(height: 8),
          Text(
            'Los registros aparecerán aquí\ncuando recibas y respondas los recordatorios.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.4)),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ColorScheme scheme, MedicationModel med) {
    // Estadísticas rápidas
    final taken = _completions.where((c) => c.status == 'taken').length;
    final missed = _completions.where((c) => c.status == 'missed').length;
    final skipped = _completions.where((c) => c.status == 'skipped').length;
    final total = _completions.length;
    final takenPct = total > 0 ? (taken / total * 100).round() : 0;

    return Column(
      children: [
        // Banner estadísticas
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          color: scheme.surfaceContainerHighest,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _Stat(label: 'Tomados', value: '$taken', color: Colors.green),
              _Stat(label: 'Olvidados', value: '$missed', color: Colors.red),
              _Stat(label: 'Omitidos', value: '$skipped', color: Colors.orange),
              _Stat(
                  label: 'Adherencia',
                  value: '$takenPct%',
                  color: takenPct >= 80
                      ? Colors.green
                      : takenPct >= 50
                          ? Colors.orange
                          : Colors.red),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
            itemCount: _completions.length,
            itemBuilder: (context, i) {
              return _HistoryTile(
                completion: _completions[i],
                medication: med,
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Tile de historial ────────────────────────────────────

class _HistoryTile extends StatelessWidget {
  final MedicationCompletionModel completion;
  final MedicationModel medication;

  const _HistoryTile(
      {required this.completion, required this.medication});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = completion;

    final statusConfig = _statusConfig(c.status);
    final scheduledDt = c.scheduledAtLocal;
    final confirmedDt = c.confirmedAtLocal;

    final scheduledText =
        '${_weekdayName(scheduledDt.weekday)} ${scheduledDt.day.toString().padLeft(2, '0')}/${scheduledDt.month.toString().padLeft(2, '0')}/${scheduledDt.year}  '
        '${scheduledDt.hour.toString().padLeft(2, '0')}:${scheduledDt.minute.toString().padLeft(2, '0')}';

    String? confirmedText;
    if (confirmedDt != null) {
      confirmedText =
          '${confirmedDt.hour.toString().padLeft(2, '0')}:${confirmedDt.minute.toString().padLeft(2, '0')}';
    }

    // Calcular dosis mostrada
    final doseText = () {
      final amount = c.dosageAmountTaken.isNotEmpty
          ? c.dosageAmountTaken
          : medication.dosageAmount;
      final unit = c.dosageUnitTaken.isNotEmpty
          ? c.dosageUnitTaken
          : medication.dosageUnit;
      if (amount.isEmpty) return '';
      return '$amount $unit';
    }();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icono de estado
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: statusConfig.color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(statusConfig.icon,
                  color: statusConfig.color, size: 22),
            ),
            const SizedBox(width: 12),
            // Contenido
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Fecha programada + estado
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          scheduledText,
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusConfig.color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          statusConfig.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: statusConfig.color,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Dosis
                  if (doseText.isNotEmpty)
                    _InfoRow(
                      icon: Icons.colorize_outlined,
                      text: 'Dosis: $doseText',
                    ),
                  // Hora de confirmación
                  if (confirmedText != null)
                    _InfoRow(
                      icon: Icons.check_circle_outline,
                      text: c.status == 'taken'
                          ? 'Tomado a las $confirmedText'
                          : 'Respondido a las $confirmedText',
                    ),
                  // Pospuestos
                  if (c.snoozeCount > 0)
                    _InfoRow(
                      icon: Icons.snooze,
                      text: c.snoozeCount == 1
                          ? 'Pospuesto 1 vez antes de responder'
                          : 'Pospuesto ${c.snoozeCount} veces antes de responder',
                      color: Colors.orange.shade700,
                    ),
                  // Confirmado via recordatorio de confirmación
                  if (c.confirmedViaReminder)
                    _InfoRow(
                      icon: Icons.notifications_active_outlined,
                      text: 'Respondido en el recordatorio de confirmación',
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _StatusConfig _statusConfig(String status) {
    switch (status) {
      case 'taken':
        return _StatusConfig(
            icon: Icons.check_circle, color: Colors.green, label: 'Tomado');
      case 'skipped':
        return _StatusConfig(
            icon: Icons.skip_next, color: Colors.orange, label: 'Omitido');
      case 'missed':
        return _StatusConfig(
            icon: Icons.cancel_outlined, color: Colors.red, label: 'Olvidado');
      default:
        return _StatusConfig(
            icon: Icons.schedule, color: Colors.grey, label: 'Pendiente');
    }
  }

  String _weekdayName(int weekday) {
    const days = ['', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    return weekday >= 1 && weekday <= 7 ? days[weekday] : '';
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const _InfoRow({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final effectiveColor = color ?? scheme.onSurface.withValues(alpha: 0.65);
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 14, color: effectiveColor),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: effectiveColor),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Stat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(label,
            style: TextStyle(
                fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6))),
      ],
    );
  }
}

class _StatusConfig {
  final IconData icon;
  final Color color;
  final String label;
  const _StatusConfig(
      {required this.icon, required this.color, required this.label});
}
