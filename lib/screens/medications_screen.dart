import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/medication_models.dart';
import '../services/medication_repository.dart';
import '../services/medication_scheduler.dart';
import '../settings_screen.dart';
import 'medication_edit_screen.dart';
import 'medication_history_screen.dart';

class MedicationsScreen extends StatefulWidget {
  final bool embedInShell;
  final bool manageCloudSync;

  const MedicationsScreen({
    super.key,
    this.embedInShell = false,
    this.manageCloudSync = true,
  });

  @override
  State<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends State<MedicationsScreen> {
  final MedicationRepository _repo = MedicationRepository();
  final MedicationScheduler _scheduler = MedicationScheduler();

  bool _loading = true;
  bool _cloudSyncEnabled = false;
  User? _user;
  List<MedicationModel> _medications = const [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _repo.stopAllCloudSync();
    super.dispose();
  }

  Future<void> _init() async {
    print('[MedicationsScreen] init');
    setState(() => _loading = true);

    final prefs = await SharedPreferences.getInstance();
    _cloudSyncEnabled = prefs.getBool(SettingsScreen.cloudSyncKey) ?? false;
    _user = FirebaseAuth.instance.currentUser;
    final userId = _user?.uid;

    if (userId != null && widget.manageCloudSync && _cloudSyncEnabled) {
      try {
        await _repo.reconcile(userId: userId);
        await _repo.startCloudSync(
          userId: userId,
          onMedicationsBatchApplied: (_) async {
            if (!mounted) return;
            await _reloadLocal();
            await _scheduleAll();
          },
        );
      } catch (e) {
        print('[MedicationsScreen] cloud sync error: $e');
      }
    }

    await _reloadLocal();
    await _scheduleAll();

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reloadLocal() async {
    final meds = await _repo.loadLocalMedications();
    if (mounted) setState(() => _medications = meds);
  }

  Future<void> _scheduleAll() async {
    print('[MedicationsScreen] scheduleAll start');
    final userId = _user?.uid;
    for (final med in _medications) {
      if (!med.isActive || med.deletedAt != null) continue;
      final next = _scheduler.nextOccurrenceLocal(med, DateTime.now());
      if (next == null) continue;
      final updated = med.copyWith(nextScheduledAtLocal: next);
      try {
        await _repo.upsertMedication(
          medication: updated,
          cloudSyncEnabled: _cloudSyncEnabled,
          userId: userId,
        );
        await _scheduler.scheduleOccurrence(med: updated, whenLocal: next);
        print('[MedicationsScreen] programado: ${med.medicationName} -> ${next.toIso8601String()}');
      } catch (e) {
        print('[MedicationsScreen] error programando ${med.id}: $e');
      }
    }
  }

  Future<void> _deleteMedication(MedicationModel med) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar medicamento'),
        content: Text('¿Eliminar "${med.medicationName}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Eliminar',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    print('[MedicationsScreen] eliminando ${med.id}');

    try {
      if (med.nextScheduledAtLocal != null) {
        final key = _scheduler.occurrenceKeyFor(med.id, med.nextScheduledAtLocal!);
        await _scheduler.cancelOccurrence(occurrenceKey: key);
        await _scheduler.cancelConfirmation(occurrenceKey: key);
      }
    } catch (_) {}

    final userId = _user?.uid;
    await _repo.deleteMedication(
      medicationId: med.id,
      cloudSyncEnabled: _cloudSyncEnabled,
      userId: userId,
    );
    await _reloadLocal();
  }

  Future<void> _openEdit([MedicationModel? med]) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MedicationEditScreen(medication: med),
      ),
    );
    if (result == true) {
      await _reloadLocal();
      await _scheduleAll();
    }
  }

  Future<void> _openHistory(MedicationModel med) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MedicationHistoryScreen(medication: med),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: widget.embedInShell
          ? null
          : AppBar(title: const Text('Medicamentos')),
      body: _medications.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.medication_outlined,
                      size: 72, color: scheme.onSurface.withOpacity(0.3)),
                  const SizedBox(height: 16),
                  Text('Sin medicamentos registrados',
                      style: TextStyle(color: scheme.onSurface.withOpacity(0.5))),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _openEdit(),
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar medicamento'),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
              itemCount: _medications.length,
              itemBuilder: (context, index) {
                final med = _medications[index];
                return _MedicationCard(
                  med: med,
                  onEdit: () => _openEdit(med),
                  onDelete: () => _deleteMedication(med),
                  onHistory: () => _openHistory(med),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'medications_add_fab',
        onPressed: () => _openEdit(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _MedicationCard extends StatelessWidget {
  final MedicationModel med;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onHistory;

  const _MedicationCard({
    required this.med,
    required this.onEdit,
    required this.onDelete,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cardColor = med.colorHex.isNotEmpty
        ? Color(int.tryParse(med.colorHex.replaceFirst('#', '0xFF')) ?? scheme.surface.value)
        : scheme.surface;
    final isLight = ThemeData.estimateBrightnessForColor(cardColor) == Brightness.light;
    final onCard = isLight ? Colors.black87 : Colors.white;

    String nextText = 'Sin programar';
    if (med.nextScheduledAtLocal != null) {
      final dt = med.nextScheduledAtLocal!;
      nextText =
          'Próximo: ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} '
          '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    return Dismissible(
      key: Key(med.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      child: Card(
        color: cardColor,
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          onTap: onEdit,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  med.isActive ? Icons.medication : Icons.medication_outlined,
                  color: med.isActive ? onCard : onCard.withOpacity(0.4),
                  size: 32,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        med.medicationName,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: med.isActive ? onCard : onCard.withOpacity(0.5),
                        ),
                      ),
                      if (med.dosageAmount.isNotEmpty)
                        Text(
                          '${med.dosageAmount} ${med.dosageUnit}',
                          style: TextStyle(
                              fontSize: 13,
                              color: onCard.withOpacity(0.75)),
                        ),
                      Text(
                        nextText,
                        style: TextStyle(
                            fontSize: 12,
                            color: onCard.withOpacity(0.6)),
                      ),
                    ],
                  ),
                ),
                if (!med.isActive)
                  Chip(
                    label: const Text('Inactivo', style: TextStyle(fontSize: 11)),
                    backgroundColor: Colors.grey.shade300,
                    padding: EdgeInsets.zero,
                  ),
                IconButton(
                  icon: Icon(Icons.history,
                      color: onCard.withValues(alpha: 0.7)),
                  tooltip: 'Ver historial',
                  onPressed: onHistory,
                ),
                IconButton(
                  icon: Icon(Icons.edit_outlined,
                      color: onCard.withValues(alpha: 0.7)),
                  onPressed: onEdit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
