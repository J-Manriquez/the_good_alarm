import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:the_good_alarm/games/modelo_juegos.dart';
import 'package:the_good_alarm/modelo_alarm.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'services/alarm_firebase_service.dart';
import 'services/alarm_local_service.dart';
import 'services/alarm_repository.dart';
import 'services/auth_service.dart';
import 'services/calendar_alarm_scheduler.dart';
import 'services/calendar_local_service.dart';
import 'services/calendar_repository.dart';
import 'services/habit_repository.dart';
import 'services/habit_scheduler.dart';
import 'services/habit_local_service.dart';
import 'services/sistema_firebase_service.dart';
import 'widgets/device_name_modal.dart';

import 'alarm_screen.dart'; // Importar AlarmScreen si es necesario para la navegación
import 'calendar_screen.dart';
import 'habit_alert_screen.dart';
import 'habits_screen.dart';
import 'models/habit_models.dart';
import 'settings_screen.dart'; // Importar SettingsScreen
import 'alarm_edit_screen.dart';
import 'widgets/volume_control_button.dart'; // Importar VolumeControlButton
import 'widgets/synchronized_volume_control_button.dart'; // Importar SynchronizedVolumeControlButton
import 'package:intl/intl.dart';
import 'screens/medication_alert_screen.dart';
import 'screens/medication_confirm_screen.dart';
import 'screens/medications_screen.dart';
import 'services/medication_repository.dart';
import 'services/medication_scheduler.dart';

class HomeShell extends StatefulWidget {
  final bool shouldSyncLocalAlarms;
  final int initialTabIndex;

  const HomeShell({
    super.key,
    this.shouldSyncLocalAlarms = false,
    this.initialTabIndex = 1,
  });

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final GlobalKey<_HomePageState> _homeKey = GlobalKey<_HomePageState>();
  final HabitRepository _habitRepository = HabitRepository();
  final HabitScheduler _habitScheduler = HabitScheduler();
  final CalendarAlarmScheduler _calendarAlarmScheduler = CalendarAlarmScheduler();
  StreamSubscription<User?>? _habitsAuthSub;
  StreamSubscription<User?>? _calendarAuthSub;
  StreamSubscription<User?>? _medicationsAuthSub;
  User? _habitsUser;
  User? _calendarUser;
  User? _medicationsUser;
  bool _habitsCloudSyncEnabled = false;
  bool _calendarCloudSyncEnabled = false;
  bool _medicationsCloudSyncEnabled = false;
  final MedicationRepository _medicationRepository = MedicationRepository();
  final MedicationScheduler _medicationScheduler = MedicationScheduler();
  late int _tabIndex;
  String _leftScreen = 'habits';
  late PageController _pageController;
  bool _calendarFabExpanded = false;
  Offset? _fabOffset;
  static const double _fabSize = 56;
  static const double _fabMargin = 16;

  @override
  void initState() {
    super.initState();
    final i = widget.initialTabIndex;
    if (i < 0) {
      _tabIndex = 0;
    } else if (i > 2) {
      _tabIndex = 2;
    } else {
      _tabIndex = i;
    }

    _loadLeftScreenPreference();
    _startHabitsBackground();
    _startCalendarAlarmsBackground();
    _startMedicationsBackground();
    _pageController = PageController(initialPage: _tabIndex);
  }

  @override
  void dispose() {
    _habitsAuthSub?.cancel();
    _habitsAuthSub = null;
    _calendarAuthSub?.cancel();
    _calendarAuthSub = null;
    _medicationsAuthSub?.cancel();
    _medicationsAuthSub = null;
    _habitRepository.stopAllCloudSync();
    _medicationRepository.stopAllCloudSync();
    _pageController.dispose();
    super.dispose();
  }

  void _startHabitsBackground() {
    _habitsAuthSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      await _setupHabitsForUser(user);
    });
    unawaited(_setupHabitsForUser(FirebaseAuth.instance.currentUser));
  }

  void _startCalendarAlarmsBackground() {
    _calendarAuthSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      await _setupCalendarAlarmsForUser(user);
    });
    unawaited(_setupCalendarAlarmsForUser(FirebaseAuth.instance.currentUser));
  }

  void _startMedicationsBackground() {
    _medicationsAuthSub = FirebaseAuth.instance.authStateChanges().listen((user) async {
      await _setupMedicationsForUser(user);
    });
    unawaited(_setupMedicationsForUser(FirebaseAuth.instance.currentUser));
  }

  Future<void> _loadLeftScreenPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final leftScreen = prefs.getString(SettingsScreen.leftScreenSelectionKey) ?? 'habits';
    print('[HomeShell] pantalla izquierda cargada: $leftScreen');
    if (mounted) {
      setState(() {
        _leftScreen = leftScreen;
      });
    }
  }

  Widget _buildLeftScreenWidget(String screen) {
    switch (screen) {
      case 'calendar':
        return const CalendarScreen(embedInShell: true);
      case 'medications':
        return const _MedicationsShellScreen();
      case 'habits':
      default:
        return const HabitsScreen(embedInShell: true, manageCloudSync: false);
    }
  }

  IconData _leftScreenIcon(String screen) {
    switch (screen) {
      case 'calendar':
        return Icons.calendar_month;
      case 'medications':
        return Icons.medication;
      case 'habits':
      default:
        return Icons.psychology;
    }
  }

  String _leftScreenName(String screen) {
    switch (screen) {
      case 'calendar':
        return 'Calendario';
      case 'medications':
        return 'Medicamentos';
      case 'habits':
      default:
        return 'Hábitos';
    }
  }

  Future<void> _setupMedicationsForUser(User? user) async {
    await _medicationRepository.stopAllCloudSync();
    _medicationsUser = user;

    final userId = user?.uid;
    if (userId == null) return;

    final prefs = await SharedPreferences.getInstance();
    _medicationsCloudSyncEnabled = prefs.getBool(SettingsScreen.cloudSyncKey) ?? false;

    if (_medicationsCloudSyncEnabled) {
      await _medicationRepository.reconcile(userId: userId);
      await _medicationRepository.startCloudSync(
        userId: userId,
        onMedicationsBatchApplied: (_) async {
          await _scheduleMedicationsFromLocal();
        },
      );
    }

    await _scheduleMedicationsFromLocal();
  }

  Future<void> _scheduleMedicationsFromLocal() async {
    final meds = await _medicationRepository.loadLocalMedications();
    final now = DateTime.now();
    final userId = _medicationsUser?.uid;
    print('[HomeShell] scheduleMedicationsFromLocal count=${meds.length}');

    for (final med in meds) {
      final prev = med.nextScheduledAtLocal;

      if (!med.isActive || med.deletedAt != null) {
        if (prev != null) {
          final prevKey = _medicationScheduler.occurrenceKeyFor(med.id, prev);
          try {
            await _medicationScheduler.cancelOccurrence(occurrenceKey: prevKey);
          } catch (_) {}
          await _medicationRepository.upsertMedication(
            medication: med.copyWith(nextScheduledAtLocal: null),
            cloudSyncEnabled: _medicationsCloudSyncEnabled,
            userId: userId,
          );
        }
        continue;
      }

      final next = _medicationScheduler.nextOccurrenceLocal(med, now);
      if (next == null) {
        if (prev != null) {
          final prevKey = _medicationScheduler.occurrenceKeyFor(med.id, prev);
          try {
            await _medicationScheduler.cancelOccurrence(occurrenceKey: prevKey);
          } catch (_) {}
          await _medicationRepository.upsertMedication(
            medication: med.copyWith(nextScheduledAtLocal: null),
            cloudSyncEnabled: _medicationsCloudSyncEnabled,
            userId: userId,
          );
        }
        continue;
      }

      if (prev != null && prev != next) {
        final prevKey = _medicationScheduler.occurrenceKeyFor(med.id, prev);
        try {
          await _medicationScheduler.cancelOccurrence(occurrenceKey: prevKey);
        } catch (_) {}
      }

      if (prev == null || prev != next) {
        await _medicationRepository.upsertMedication(
          medication: med.copyWith(nextScheduledAtLocal: next),
          cloudSyncEnabled: _medicationsCloudSyncEnabled,
          userId: userId,
        );
      }

      try {
        await _medicationScheduler.scheduleOccurrence(med: med, whenLocal: next);
        print('[HomeShell] programado: ${med.medicationName} -> ${next.toIso8601String()}');
      } catch (e) {
        print('[HomeShell] error programando ${med.id}: $e');
      }
    }
  }

  Future<void> _setupHabitsForUser(User? user) async {
    await _habitRepository.stopAllCloudSync();
    _habitsUser = user;

    final userId = user?.uid;
    if (userId == null) return;

    final prefs = await SharedPreferences.getInstance();
    _habitsCloudSyncEnabled = prefs.getBool(SettingsScreen.cloudSyncKey) ?? false;

    if (_habitsCloudSyncEnabled) {
      await _habitRepository.reconcile(userId: userId);
      await _habitRepository.startCloudSync(
        userId: userId,
        onHabitsBatchApplied: (_) async {
          await _scheduleHabitsFromLocal();
        },
        onCompletionsApplied: () async {},
      );
    }

    await _scheduleHabitsFromLocal();
  }

  Future<void> _setupCalendarAlarmsForUser(User? user) async {
    _calendarUser = user;
    final userId = user?.uid;
    if (userId == null) return;

    final prefs = await SharedPreferences.getInstance();
    _calendarCloudSyncEnabled = prefs.getBool(SettingsScreen.cloudSyncKey) ?? false;
    try {
      await _calendarAlarmScheduler.rescheduleAllForUser(
        userId: userId,
        cloudSyncEnabled: _calendarCloudSyncEnabled,
      );
    } catch (_) {}
    _homeKey.currentState?._reloadNextCalendarAlarmFromPrefs(prefs: prefs);
    _homeKey.currentState?._startOrUpdateCountdown();
  }

  Future<void> _scheduleHabitsFromLocal() async {
    final List<HabitModel> habits = await _habitRepository.loadLocalHabits();
    final now = DateTime.now();
    final userId = _habitsUser?.uid;

    for (final habit in habits) {
      final prev = habit.nextScheduledAtLocal;

      if (!habit.isActive || habit.deletedAt != null) {
        if (prev != null) {
          final prevKey = _habitScheduler.occurrenceKeyFor(habit.id, prev);
          try {
            await _habitScheduler.cancelOccurrence(occurrenceKey: prevKey);
          } catch (_) {}
          await _habitRepository.upsertHabit(
            habit: habit.copyWith(nextScheduledAtLocal: null),
            cloudSyncEnabled: _habitsCloudSyncEnabled,
            userId: userId,
          );
        }
        continue;
      }

      final next = _habitScheduler.nextOccurrenceLocal(habit, now);
      if (next == null) {
        if (prev != null) {
          final prevKey = _habitScheduler.occurrenceKeyFor(habit.id, prev);
          try {
            await _habitScheduler.cancelOccurrence(occurrenceKey: prevKey);
          } catch (_) {}
          await _habitRepository.upsertHabit(
            habit: habit.copyWith(nextScheduledAtLocal: null),
            cloudSyncEnabled: _habitsCloudSyncEnabled,
            userId: userId,
          );
        }
        continue;
      }

      if (prev != null && prev != next) {
        final prevKey = _habitScheduler.occurrenceKeyFor(habit.id, prev);
        try {
          await _habitScheduler.cancelOccurrence(occurrenceKey: prevKey);
        } catch (_) {}
      }

      if (prev == null || prev != next) {
        await _habitRepository.upsertHabit(
          habit: habit.copyWith(nextScheduledAtLocal: next),
          cloudSyncEnabled: _habitsCloudSyncEnabled,
          userId: userId,
        );
      }

      try {
        await _habitScheduler.scheduleOccurrence(habit: habit, whenLocal: next);
      } catch (_) {}
    }
  }

  String _currentTabName() {
    switch (_tabIndex) {
      case 0:
        return _leftScreenName(_leftScreen);
      case 1:
        return 'Alarmas';
      case 2:
        return 'Más';
      default:
        return 'Alarmas';
    }
  }

  void _goToTab(int index) {
    print('[HomeShell] navegando al tab $index');
    setState(() => _tabIndex = index);
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
    if (index == 1) {
      _homeKey.currentState?._reloadNextCalendarAlarmFromPrefs();
      _homeKey.currentState?._startOrUpdateCountdown();
    }
  }

  AppBar _buildHomeAppBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return AppBar(
      automaticallyImplyLeading: false,
      title: Padding(
        padding: const EdgeInsets.only(left: 85),
        child: Text(
          'The Good Alarm',
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, fontSize: 25),
        ),
      ),
      actions: [
        Theme(
          data: Theme.of(context).copyWith(
            popupMenuTheme: PopupMenuThemeData(
              shape: RoundedRectangleBorder(
                side: BorderSide(color: scheme.primary, width: 2.0),
                borderRadius: BorderRadius.circular(4.0),
              ),
            ),
          ),
          child: PopupMenuButton<String>(
            color: scheme.surface,
            icon: const Icon(Icons.more_vert, size: 30),
            onSelected: (String value) async {
              switch (value) {
                case 'settings':
                  await Navigator.pushNamed(context, '/settings');
                  _homeKey.currentState?._loadSettingsAndAlarms();
                  await _setupHabitsForUser(FirebaseAuth.instance.currentUser);
                  await _setupCalendarAlarmsForUser(FirebaseAuth.instance.currentUser);
                  await _loadLeftScreenPreference();
                  print('[HomeShell] regresando de configuracion, pantalla izquierda: $_leftScreen');
                  break;
              }
            },
            itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'settings',
                child: Row(
                  children: [
                    Icon(Icons.settings, color: scheme.onSurface),
                    const SizedBox(width: 8),
                    Text(
                      'Configuración',
                      style: TextStyle(color: scheme.onSurface),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentName = _currentTabName();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: _buildHomeAppBar(context),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final initial = Offset(
            size.width - _fabSize - _fabMargin,
            size.height - _fabSize - _fabMargin,
          );
          final current = _fabOffset ?? initial;
          final clamped = Offset(
            current.dx.clamp(_fabMargin, size.width - _fabSize - _fabMargin),
            current.dy.clamp(_fabMargin, size.height - _fabSize - _fabMargin),
          );
          _fabOffset = clamped;

          final fab = FloatingActionButton(
            heroTag: 'home_shell_add_alarm_fab',
            onPressed: () {
              _homeKey.currentState?._setAlarm();
            },
            tooltip: 'Añadir alarma',
            focusColor: scheme.onPrimary,
            foregroundColor: scheme.onPrimary,
            backgroundColor: scheme.primary,
            child: const Icon(Icons.add),
          );

          return Stack(
            children: [
              PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  if (_tabIndex == index) return;
                  print('[HomeShell] swipe al tab $index');
                  setState(() => _tabIndex = index);
                  if (index == 1) {
                    _homeKey.currentState?._reloadNextCalendarAlarmFromPrefs();
                    _homeKey.currentState?._startOrUpdateCountdown();
                  }
                },
                children: [
                  _buildLeftScreenWidget(_leftScreen),
                  HomePage(
                    key: _homeKey,
                    shouldSyncLocalAlarms: widget.shouldSyncLocalAlarms,
                    embedInShell: true,
                  ),
                  _SecondaryMenuScreen(selectedLeftScreen: _leftScreen),
                ],
              ),
              if (_tabIndex == 1)
                Positioned(
                  left: clamped.dx,
                  top: clamped.dy,
                  child: GestureDetector(
                    onPanUpdate: (details) {
                      final next = Offset(
                        (_fabOffset!.dx + details.delta.dx).clamp(
                          _fabMargin,
                          size.width - _fabSize - _fabMargin,
                        ),
                        (_fabOffset!.dy + details.delta.dy).clamp(
                          _fabMargin,
                          size.height - _fabSize - _fabMargin,
                        ),
                      );
                      setState(() {
                        _fabOffset = next;
                      });
                    },
                    child: fab,
                  ),
                ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            border: Border(top: BorderSide(color: scheme.primary, width: 1)),
          ),
          padding: const EdgeInsets.only(top: 9, bottom: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                onPressed: () => _goToTab(0),
                iconSize: 36,
                icon: Icon(
                  _leftScreenIcon(_leftScreen),
                  color: _tabIndex == 0 ? scheme.primary : scheme.onSurface,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: () => _goToTab(1),
                    iconSize: 36,
                    icon: Icon(
                      Icons.home,
                      color: _tabIndex == 1 ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                  Text(
                    currentName,
                    style: TextStyle(
                      color: scheme.primary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              IconButton(
                onPressed: () => _goToTab(2),
                iconSize: 36,
                icon: Icon(
                  Icons.apps,
                  color: _tabIndex == 2 ? scheme.primary : scheme.onSurface,
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pushNamed(context, '/ai_assistant'),
                iconSize: 36,
                tooltip: 'Asistente IA',
                icon: Icon(Icons.mic, color: scheme.tertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExtrasScreen extends StatelessWidget {
  const _ExtrasScreen();

  @override
  Widget build(BuildContext context) {
    return const HabitsScreen(embedInShell: true, manageCloudSync: false);
  }
}

class _MedicationsShellScreen extends StatelessWidget {
  const _MedicationsShellScreen();

  @override
  Widget build(BuildContext context) {
    return const MedicationsScreen(embedInShell: true, manageCloudSync: false);
  }
}

class _SecondaryMenuScreen extends StatelessWidget {
  final String selectedLeftScreen;

  const _SecondaryMenuScreen({required this.selectedLeftScreen});

  List<String> _remainingScreens() {
    const ordered = ['calendar', 'habits', 'medications'];
    return ordered.where((s) => s != selectedLeftScreen).toList();
  }

  String _screenTitle(String screen) {
    switch (screen) {
      case 'habits':
        return 'Hábitos';
      case 'calendar':
        return 'Calendario';
      case 'medications':
        return 'Medicamentos';
      default:
        return '';
    }
  }

  String _screenSubtitle(String screen) {
    switch (screen) {
      case 'habits':
        return 'Gestiona tus rutinas y hábitos diarios';
      case 'calendar':
        return 'Organiza tus eventos y alarmas del calendario';
      case 'medications':
        return 'Controla tus recordatorios de medicamentos';
      default:
        return '';
    }
  }

  IconData _screenIcon(String screen) {
    switch (screen) {
      case 'habits':
        return Icons.psychology;
      case 'calendar':
        return Icons.calendar_month;
      case 'medications':
        return Icons.medication;
      default:
        return Icons.apps;
    }
  }

  Widget _buildFullScreen(String screen) {
    switch (screen) {
      case 'habits':
        return const HabitsScreen(embedInShell: false, manageCloudSync: false);
      case 'calendar':
        return const CalendarScreen(embedInShell: false);
      case 'medications':
        return const MedicationsScreen(embedInShell: false, manageCloudSync: false);
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = _remainingScreens();
    final scheme = Theme.of(context).colorScheme;
    print('[SecondaryMenuScreen] pantallas disponibles: ${screens.join(", ")}');
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      children: [
        for (final screen in screens) ...[
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: scheme.primary.withOpacity(0.4), width: 1),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                print('[SecondaryMenuScreen] abriendo pantalla: $screen');
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _buildFullScreen(screen),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: scheme.primary.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(_screenIcon(screen), size: 36, color: scheme.primary),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _screenTitle(screen),
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _screenSubtitle(screen),
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: scheme.primary),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

class HomePage extends StatefulWidget {
  final bool shouldSyncLocalAlarms;
  final bool embedInShell;
  
  const HomePage({
    super.key,
    this.shouldSyncLocalAlarms = false,
    this.embedInShell = false,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin<HomePage> {
  final List<Alarm> _alarms = [];
  static const platform = MethodChannel('com.andodevs.the_good_alarm/alarm');

  AlarmGroupingOption _currentGroupingOption = AlarmGroupingOption.none;
  Map<String, bool> _groupExpansionState =
      {}; // Para controlar la expansión de cada grupo
  Map<String, bool> _groupShowActiveOnlyState =
      {}; // Para controlar si se muestran solo activas por grupo
  bool _showNextAlarmSection =
      true; // Nuevo estado para la sección de próxima alarma
  static const String _showNextAlarmKey =
      'show_next_alarm'; // Key para SharedPreferences

  // NUEVO: Variables para controlar la alarma que está sonando
  bool _isAlarmRinging = false;
  int? _ringingAlarmId;
  String _ringingAlarmTitle = '';
  String _ringingAlarmMessage = '';
  int _ringingAlarmSnoozeCount = 0;
  int _ringingAlarmMaxSnoozes = 3;
  int _ringingAlarmSnoozeDuration = 5;

  // NUEVO: Variables para controlar el estado de la aplicación
  final bool _isAppInForeground = true;
  final bool _hasUnhandledAlarm = false;

  // Guard para evitar doble push de pantallas de medicamento
  final Set<String> _showingMedicationScreens = {};

  // Variables de configuración de volumen
  int maxVolumePercent = 100;
  int volumeRampUpDurationSeconds = 30;
  int tempVolumeReductionPercent = 50;
  int tempVolumeReductionDurationSeconds = 30;

  // Servicios de Firebase
  final AlarmFirebaseService _alarmFirebaseService = AlarmFirebaseService();
  final AlarmLocalService _alarmLocalService = AlarmLocalService();
  late final AlarmRepository _alarmRepository = AlarmRepository(
    local: _alarmLocalService,
    cloud: _alarmFirebaseService,
  );
  final AuthService _authService = AuthService();
  final SistemaFirebaseService _sistemaFirebaseService =
      SistemaFirebaseService();
  final CalendarRepository _calendarRepository = CalendarRepository();
  final CalendarLocalService _calendarLocalService = CalendarLocalService();
  final HabitRepository _habitRepository = HabitRepository();
  final HabitLocalService _habitLocalService = HabitLocalService();
  User? _currentUser;
  bool _isAlarmCloudSyncing = false;
  bool _cloudSyncEnabled = false;
  int? _pendingAlarmId;

  bool moreAlarms = false; // Oculto por defecto
  Offset? _fabOffset;
  static const double _fabSize = 56;
  static const double _fabMargin = 16;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    platform.setMethodCallHandler(_handleNativeCalls);
    _loadSettingsAndAlarms(); // Cargar configuración primero
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingMedicationScreen();
    });
  }

  Future<void> _checkPendingMedicationScreen() async {
    try {
      final raw = await platform.invokeMethod<String>('getPendingMedicationScreen');
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final timestamp = (data['timestamp'] as num?)?.toInt() ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      // Ignorar pending si tiene más de 1 hora (dato obsoleto)
      if (now - timestamp > 60 * 60 * 1000) {
        print('[HomePage] pending_medication_screen obsoleto (${(now - timestamp) ~/ 60000} min), ignorando');
        return;
      }
      final medicationId = data['medicationId'] as String?;
      final occurrenceKey = data['occurrenceKey'] as String?;
      if (medicationId == null || occurrenceKey == null) return;
      final scheduledAtLocalMillis =
          (data['scheduledAtLocalMillis'] as num?)?.toInt() ??
              DateTime.now().millisecondsSinceEpoch;
      final isConfirmation = data['isConfirmation'] as bool? ?? false;
      final screenRoute = data['screenRoute'] as String? ?? '/medication';
      print('[HomePage] checkPending: medicationId=$medicationId screen=$screenRoute isConfirmation=$isConfirmation');
      if (!mounted) return;
      if (_showingMedicationScreens.contains(occurrenceKey)) {
        print('[HomePage] checkPending: $occurrenceKey ya está mostrándose, ignorando');
        return;
      }
      if (isConfirmation || screenRoute == '/medication_confirm') {
        _showingMedicationScreens.add(occurrenceKey);
        Navigator.of(context)
            .push(MaterialPageRoute(
              builder: (context) => MedicationConfirmScreen(
                arguments: {
                  'medicationId': medicationId,
                  'occurrenceKey': occurrenceKey,
                  'scheduledAtLocalMillis': scheduledAtLocalMillis,
                  ...Map<String, dynamic>.from(data),
                },
              ),
            ))
            .then((_) => _showingMedicationScreens.remove(occurrenceKey));
      } else {
        _showingMedicationScreens.add(occurrenceKey);
        Navigator.of(context)
            .push(MaterialPageRoute(
              builder: (context) => MedicationAlertScreen(
                arguments: {
                  'medicationId': medicationId,
                  'occurrenceKey': occurrenceKey,
                  'scheduledAtLocalMillis': scheduledAtLocalMillis,
                  ...Map<String, dynamic>.from(data),
                },
              ),
            ))
            .then((_) => _showingMedicationScreens.remove(occurrenceKey));
      }
    } catch (e) {
      print('[HomePage] checkPendingMedicationScreen error: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alarmRepository.stopCloudSync();
    _countdownTimer?.cancel();
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _consumeNativeAlarmEvents();
      _reloadNextCalendarAlarmFromPrefs();
      _checkPendingMedicationScreen();
    }
  }

  @override
  bool get wantKeepAlive => true;

  List<int> _normalizeRepeatDaysForAlarm(Alarm alarm) {
    if (alarm.repeatDays.isNotEmpty) return List<int>.from(alarm.repeatDays);
    if (alarm.isDaily) return const [1, 2, 3, 4, 5, 6, 7];
    if (alarm.isWeekend) return const [6, 7];
    if (alarm.isWeekly) return [alarm.time.weekday];
    return const [];
  }

  bool _isRepeatingAlarm(Alarm alarm) => _normalizeRepeatDaysForAlarm(alarm).isNotEmpty;

  Map<String, dynamic> _deriveRepeatFlags(List<int> repeatDays) {
    final normalized = repeatDays.toSet();
    final isDaily = normalized.length == 7 &&
        normalized.containsAll(const {1, 2, 3, 4, 5, 6, 7});
    final isWeekend = normalized.length == 2 && normalized.containsAll(const {6, 7});
    final isWeekly = normalized.length == 1;
    return {
      'isDaily': isDaily,
      'isWeekly': isWeekly,
      'isWeekend': isWeekend,
    };
  }

  Future<void> _consumeNativeAlarmEvents() async {
    try {
      final raw = await platform.invokeMethod('getAndClearAlarmEvents');
      if (raw is! List) return;

      for (final item in raw) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final type = map['type'] as String?;
        final alarmId = (map['alarmId'] as num?)?.toInt();
        if (type == null || alarmId == null) continue;

        if (type == 'stopped') {
          await _handleAlarmStopped(alarmId);
        } else if (type == 'snoozed') {
          final newTimeInMillis = (map['newTimeInMillis'] as num?)?.toInt();
          if (newTimeInMillis != null) {
            await _handleAlarmSnoozed(alarmId, newTimeInMillis);
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _loadSettingsAndAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final groupingIndex =
        prefs.getInt(SettingsScreen.alarmGroupingKey) ??
        AlarmGroupingOption.none.index;
    _currentGroupingOption = AlarmGroupingOption.values[groupingIndex];
    _showNextAlarmSection =
        prefs.getBool(_showNextAlarmKey) ?? true; // Cargar preferencia

    // Cargar configuración de sincronización en la nube
    _cloudSyncEnabled = prefs.getBool(SettingsScreen.cloudSyncKey) ?? false;
    _currentUser = FirebaseAuth.instance.currentUser;

    await _loadAlarms(); // Cargar alarmas después de la configuración
    await _consumeNativeAlarmEvents();

    // Inicializar escucha de dispositivos activos (siempre activada si hay usuario)
    if (_currentUser != null) {
      await _initializeDeviceStatusListener();
      
      // Verificar si se necesita mostrar el modal de nombre de dispositivo
      _checkDeviceNameModal();
      
      // Sincronizar alarmas locales existentes si es necesario
      if (widget.shouldSyncLocalAlarms) {
        await syncAllLocalAlarmsOnLogin();
      }
    }

    // Leer el estado de sincronización de alarmas desde SharedPreferences
    final alarmSyncEnabled = prefs.getBool('alarm_sync_enabled') ?? false;
    
    // Inicializar sincronización de alarmas con Firebase si está habilitada
    if (_cloudSyncEnabled && _currentUser != null && alarmSyncEnabled) {
      await _initializeFirebaseSync();
    }
    
    // Configurar listener para cambios en el estado de sincronización
    _setupSyncStateListener();

    // Inicializar el estado de expansión para los grupos si es necesario
    if (_currentGroupingOption != AlarmGroupingOption.none) {
      _initializeGroupStates();
    }

    if (mounted) setState(() {});
    _reloadNextCalendarAlarmFromPrefs(prefs: prefs);
    _startOrUpdateCountdown();
  }

  void _reloadNextCalendarAlarmFromPrefs({SharedPreferences? prefs}) {
    final effectivePrefs = prefs;
    if (effectivePrefs == null) {
      SharedPreferences.getInstance().then((value) {
        if (!mounted) return;
        _reloadNextCalendarAlarmFromPrefs(prefs: value);
      });
      return;
    }

    final raw = effectivePrefs.getString('calendarAlarms');
    if (raw == null || raw.trim().isEmpty) {
      setState(() {
        _nextCalendarAlarmTimeLocal = null;
        _nextCalendarAlarmTitle = '';
        _nextCalendarAlarmMessage = '';
      });
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      int? bestMillis;
      String bestTitle = '';
      String bestMessage = '';

      for (final item in decoded) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final millis = (map['timeInMillis'] as num?)?.toInt();
        if (millis == null) continue;
        if (millis <= now) continue;
        if (bestMillis == null || millis < bestMillis) {
          bestMillis = millis;
          bestTitle = (map['title'] as String?) ?? '';
          bestMessage = (map['message'] as String?) ?? '';
        }
      }

      setState(() {
        _nextCalendarAlarmTimeLocal =
            bestMillis == null ? null : DateTime.fromMillisecondsSinceEpoch(bestMillis);
        _nextCalendarAlarmTitle = bestTitle;
        _nextCalendarAlarmMessage = bestMessage;
      });
    } catch (_) {}
  }

  void _initializeGroupStates() {
    final groups = _getGroupedAlarms();
    _groupExpansionState = {
      for (var group in groups.keys) group: false,
    }; // Por defecto colapsados
    _groupShowActiveOnlyState = {
      for (var group in groups.keys) group: false,
    }; // Por defecto mostrar todas
  }

  // Inicializar sincronización con Firebase
  Future<void> _initializeFirebaseSync() async {
    if (_currentUser == null) return;

    try {
      await _alarmRepository.reconcile(userId: _currentUser!.uid);
      await _reloadAlarmsFromLocal();

      await _alarmRepository.startCloudSync(
        userId: _currentUser!.uid,
        onBatchApplied: (batch) async {
          for (final alarm in batch.effectiveAlarms) {
            final isDeleted =
                alarm.deletedAt != null || alarm.extras['deleted'] == true;
            if (isDeleted) {
              await platform.invokeMethod('cancelAlarm', {'alarmId': alarm.id});
              continue;
            }
            if (alarm.isActive) {
              await _setNativeAlarm(alarm);
            } else {
              await platform.invokeMethod('cancelAlarm', {'alarmId': alarm.id});
            }
          }

          await _reloadAlarmsFromLocal();
          if (!mounted) return;
          if (_currentGroupingOption != AlarmGroupingOption.none) {
            _initializeGroupStates();
          }
          _startOrUpdateCountdown();
        },
      );
      _isAlarmCloudSyncing = true;
    } catch (e) {
      print('Error al inicializar sincronización con Firebase: $e');
    }
  }

  // Verificar si se necesita mostrar el modal de nombre de dispositivo
  Future<void> _checkDeviceNameModal() async {
    if (!mounted) return;

    final shouldShow = await shouldShowDeviceNameModal();
    if (shouldShow && mounted) {
      // Mostrar modal sin posibilidad de cerrarlo hasta ingresar el nombre
      await showDeviceNameModal(
        context,
        canDismiss: false,
        onDeviceNameSet: () {
          // Actualizar el estado de sincronización si es necesario
          if (_cloudSyncEnabled && _currentUser != null) {
            _initializeFirebaseSync();
          }
        },
      );
    }

    await _promptLocalCalendarsAndHabitsSyncIfNeeded();
  }

  Future<void> _promptLocalCalendarsAndHabitsSyncIfNeeded() async {
    if (!mounted) return;
    final user = _currentUser;
    if (user == null) return;

    final prefs = await SharedPreferences.getInstance();
    final deviceName = prefs.getString('device_name');
    if (deviceName == null || deviceName.trim().isEmpty) return;

    final key = 'local_data_sync_decision_${user.uid}';
    if (prefs.containsKey(key)) return;

    final shouldUploadLocal = await _showLocalDataSyncDecisionDialog();
    if (!mounted) return;

    await prefs.setBool(key, shouldUploadLocal);
    await _runPostLoginCloudPrefetch(uploadLocalToCloud: shouldUploadLocal);
  }

  Future<bool> _showLocalDataSyncDecisionDialog() async {
    final scheme = Theme.of(context).colorScheme;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Sincronización de calendarios'),
          content: const Text(
            '¿Quieres sincronizar tus calendarios y hábitos locales con tu cuenta?\n\n'
            'Si eliges "Sí", se subirán tus datos locales a Firebase y se descargará tu información de la nube.\n'
            'Si eliges "No", se descargará tu información de la nube sin subir lo local.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('No', style: TextStyle(color: scheme.onSurface)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Sí'),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  Future<void> _runPostLoginCloudPrefetch({required bool uploadLocalToCloud}) async {
    final userId = _currentUser?.uid;
    if (userId == null) return;

    try {
      if (uploadLocalToCloud) {
        final localCalendars = await _calendarRepository.loadLocalCalendars(includeDeleted: true);
        for (final calendar in localCalendars) {
          if (calendar.ownerUid.trim().isNotEmpty && calendar.ownerUid == userId) continue;
          await _calendarRepository.upsertCalendar(
            calendar: calendar.copyWith(ownerUid: userId),
            cloudSyncEnabled: false,
            userId: null,
          );
        }

        final localHabits = await _habitRepository.loadLocalHabits(includeDeleted: true);
        for (final habit in localHabits) {
          final needsOwner = habit.ownerUid.trim().isEmpty || habit.ownerUid != userId;
          final needsSyncToCloud = !habit.syncToCloud;
          if (!needsOwner && !needsSyncToCloud) continue;
          await _habitRepository.upsertHabit(
            habit: habit.copyWith(ownerUid: userId, syncToCloud: true),
            cloudSyncEnabled: false,
            userId: null,
          );
        }

        await _calendarRepository.pushPendingChanges(userId: userId);
        await _habitRepository.pushPendingChanges(userId: userId);
      } else {
        for (final id in await _calendarLocalService.getEntityIdsWithDirtyFields('calendar')) {
          await _calendarLocalService.clearDirty('calendar', id);
        }
        for (final id in await _calendarLocalService.getEntityIdsWithDirtyFields('event')) {
          await _calendarLocalService.clearDirty('event', id);
        }
        for (final id in await _calendarLocalService.getEntityIdsWithDirtyFields('override')) {
          await _calendarLocalService.clearDirty('override', id);
        }

        final localHabits = await _habitRepository.loadLocalHabits(includeDeleted: true);
        for (final habit in localHabits) {
          if (habit.ownerUid.trim().isNotEmpty) continue;
          if (!habit.syncToCloud) continue;
          await _habitRepository.upsertHabit(
            habit: habit.copyWith(syncToCloud: false),
            cloudSyncEnabled: false,
            userId: null,
          );
        }
        for (final id in await _habitLocalService.getEntityIdsWithDirtyFields('habit')) {
          await _habitLocalService.clearDirty('habit', id);
        }
        for (final id in await _habitLocalService.getEntityIdsWithDirtyFields('completion')) {
          await _habitLocalService.clearDirty('completion', id);
        }
      }

      await _calendarRepository.pullOnce(userId: userId);
      await _habitRepository.pullOnce(userId: userId);
    } catch (e) {
      print('Error al sincronizar datos post-login: $e');
    }
  }

  Future<void> _showDeviceNameModal() async {
    if (!mounted) return;

    await showDeviceNameModal(
      context,
      canDismiss: true,
      onDeviceNameSet: () {
        // Mostrar mensaje de confirmación
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Nombre del dispositivo actualizado'),
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
        );
      },
    );
  }

  // Sincronizar todas las alarmas locales existentes al iniciar sesión
  Future<void> syncAllLocalAlarmsOnLogin() async {
    if (_currentUser == null) return;

    try {
      for (int i = 0; i < _alarms.length; i++) {
        final updated = _alarms[i].copyWith(syncToCloud: true);
        _alarms[i] = updated;

        final json = Map<String, dynamic>.from(updated.toJson());
        json.remove('createdAt');
        json.remove('updatedAt');
        json.remove('revision');
        json.remove('fieldUpdatedAt');
        await _alarmLocalService.upsertAlarm(updated);
        await _alarmLocalService.markDirtyFields(updated.id, json.keys.toSet());
      }

      await _alarmRepository.pushPendingChanges(userId: _currentUser!.uid);
      
      print('Todas las alarmas locales sincronizadas con Firebase');
    } catch (e) {
      print('Error al sincronizar todas las alarmas locales: $e');
    }
  }

  // NUEVO: Inicializar escucha de dispositivos activos (siempre activada)
  Future<void> _initializeDeviceStatusListener() async {
    if (_currentUser == null) return;
    
    try {
      // Asegurar que el dispositivo esté registrado
      await _ensureDeviceRegistered();
      print('Escucha de dispositivos activos inicializada');
    } catch (e) {
      print('Error al inicializar escucha de dispositivos: $e');
    }
  }

  // NUEVO: Asegurar que el dispositivo esté registrado
  Future<void> _ensureDeviceRegistered() async {
    if (_currentUser == null) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceName = prefs.getString('device_name');
      
      if (deviceName != null && deviceName.isNotEmpty) {
        // Registrar o actualizar el dispositivo en Firebase
        await _sistemaFirebaseService.updateDeviceStatus(
          _currentUser!.uid,
          deviceName,
          true, // Marcar como activo al iniciar sesión
        );
        print('Dispositivo registrado como activo: $deviceName');
      }
    } catch (e) {
      print('Error al registrar dispositivo: $e');
    }
  }

  // Método público para activar/desactivar sincronización desde settings
  Future<void> updateCloudSyncStatus(bool enabled) async {
    _cloudSyncEnabled = enabled;
    _currentUser = FirebaseAuth.instance.currentUser;

    if (enabled && _currentUser != null) {
      // Verificar también el estado de sincronización de alarmas
      final prefs = await SharedPreferences.getInstance();
      final alarmSyncEnabled = prefs.getBool('alarm_sync_enabled') ?? false;
      
      if (alarmSyncEnabled) {
        // Solo inicializar sincronización de alarmas si también está habilitada
        await _initializeFirebaseSync();
        print('Sincronización de alarmas activada');
      }
    } else {
      // Solo cancelar sincronización de alarmas, mantener escucha de dispositivos
      await _alarmRepository.stopCloudSync();
      _isAlarmCloudSyncing = false;
      print('Sincronización de alarmas desactivada');
    }
    
    // La escucha de dispositivos activos permanece siempre activada
    // mientras haya un usuario autenticado
  }

  // Método para manejar cambios de autenticación
  Future<void> handleAuthStateChange() async {
    final newUser = FirebaseAuth.instance.currentUser;

    if (newUser != _currentUser) {
      // Cancelar suscripción anterior
      await _alarmRepository.stopCloudSync();
      _isAlarmCloudSyncing = false;

      _currentUser = newUser;

      // Inicializar escucha de dispositivos si hay usuario
      if (_currentUser != null) {
        await _initializeDeviceStatusListener();
      }

      // Reinicializar sincronización de alarmas si está habilitada y hay usuario
      if (_cloudSyncEnabled && _currentUser != null) {
        await _initializeFirebaseSync();
      }
    }
  }

  // Configurar listener para cambios en el estado de sincronización
  void _setupSyncStateListener() {
    // Crear un timer que verifique periódicamente el estado de sincronización
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      final prefs = await SharedPreferences.getInstance();
      final alarmSyncEnabled = prefs.getBool('alarm_sync_enabled') ?? false;
      
      // Verificar si el estado ha cambiado
      final isCurrentlySyncing = _isAlarmCloudSyncing;
      
      if (alarmSyncEnabled && !isCurrentlySyncing && _cloudSyncEnabled && _currentUser != null) {
        // Activar sincronización
        await _initializeFirebaseSync();
        print('Sincronización de alarmas activada automáticamente');
      } else if (!alarmSyncEnabled && isCurrentlySyncing) {
        // Desactivar sincronización
        await _alarmRepository.stopCloudSync();
        _isAlarmCloudSyncing = false;
        print('Sincronización de alarmas desactivada automáticamente');
      }
    });
  }

  // NUEVO: Obtener alarmas pospuestas
  List<Alarm> _getSnoozedAlarms() {
    return _alarms
        .where((alarm) => alarm.snoozeCount > 0 && alarm.isActive)
        .toList();
  }

  // NUEVA: Función para calcular la hora real de una alarma pospuesta
  DateTime _calculateSnoozedAlarmTime(Alarm alarm) {
    if (alarm.snoozeCount == 0) {
      return alarm.time;
    }

    // Calcular la hora original + (minutos de posposición * número de posposiciones)
    final totalSnoozeMinutes = alarm.snoozeDurationMinutes * alarm.snoozeCount;
    return alarm.time.add(Duration(minutes: totalSnoozeMinutes));
  }

  // NUEVA: Función para calcular tiempo faltante para alarma pospuesta
  Duration _calculateTimeUntilSnoozedAlarm(Alarm alarm) {
    final now = DateTime.now();
    final snoozedTime = _calculateSnoozedAlarmTime(alarm);
    return snoozedTime.difference(now);
  }

  // MODIFICADA: Función para calcular correctamente el tiempo hasta la próxima alarma
  Duration _calculateTimeUntilAlarm(Alarm alarm) {
    final now = DateTime.now();

    if (!alarm.isRepeating()) {
      // Para alarmas no repetitivas, usar la lógica anterior
      DateTime alarmTime = alarm.time;

      if (alarmTime.isBefore(now) ||
          (alarmTime.hour < now.hour ||
              (alarmTime.hour == now.hour && alarmTime.minute <= now.minute))) {
        alarmTime = DateTime(
          now.year,
          now.month,
          now.day + 1,
          alarm.time.hour,
          alarm.time.minute,
        );
      }

      return alarmTime.difference(now);
    }

    // Para alarmas repetitivas
    DateTime nextAlarmTime = _getNextRepeatAlarmTime(alarm, now);
    return nextAlarmTime.difference(now);
  }

  // NUEVA: Función para calcular la próxima vez que sonará una alarma repetitiva
  DateTime _getNextRepeatAlarmTime(Alarm alarm, DateTime now) {
    DateTime todayAlarmTime = DateTime(
      now.year,
      now.month,
      now.day,
      alarm.time.hour,
      alarm.time.minute,
    );

    if (alarm.isDaily) {
      // Si es diaria y aún no ha pasado hoy, es hoy
      if (todayAlarmTime.isAfter(now)) {
        return todayAlarmTime;
      }
      // Si ya pasó, es mañana
      return todayAlarmTime.add(const Duration(days: 1));
    }

    if (alarm.isWeekend) {
      // Fin de semana: sábado (6) y domingo (7)
      int currentWeekday = now.weekday;

      // Si es sábado o domingo y aún no ha pasado la hora
      if ((currentWeekday == 6 || currentWeekday == 7) &&
          todayAlarmTime.isAfter(now)) {
        return todayAlarmTime;
      }

      // Calcular días hasta el próximo fin de semana
      int daysUntilSaturday;
      if (currentWeekday == 7) {
        // Domingo
        daysUntilSaturday = 6; // Próximo sábado
      } else {
        daysUntilSaturday = 6 - currentWeekday; // Días hasta sábado
      }

      return todayAlarmTime.add(Duration(days: daysUntilSaturday));
    }

    if (alarm.isWeekly) {
      // Semanal: mismo día de la semana
      int currentWeekday = now.weekday;
      int alarmWeekday = alarm.time.weekday;

      // Si es el mismo día y aún no ha pasado la hora
      if (currentWeekday == alarmWeekday && todayAlarmTime.isAfter(now)) {
        return todayAlarmTime;
      }

      // Calcular días hasta la próxima semana
      int daysUntilNextWeek = 7 - ((currentWeekday - alarmWeekday) % 7);
      if (daysUntilNextWeek == 7 && currentWeekday == alarmWeekday) {
        daysUntilNextWeek = 7; // Próxima semana
      }

      return todayAlarmTime.add(Duration(days: daysUntilNextWeek));
    }

    if (alarm.repeatDays.isNotEmpty) {
      // Días personalizados
      int currentWeekday = now.weekday;

      // Verificar si hoy está en los días de repetición y aún no ha pasado
      if (alarm.repeatDays.contains(currentWeekday) &&
          todayAlarmTime.isAfter(now)) {
        return todayAlarmTime;
      }

      // Buscar el próximo día de repetición
      List<int> sortedDays = List.from(alarm.repeatDays)..sort();

      // Buscar el próximo día en esta semana
      for (int day in sortedDays) {
        if (day > currentWeekday) {
          int daysUntil = day - currentWeekday;
          return todayAlarmTime.add(Duration(days: daysUntil));
        }
      }

      // Si no hay días restantes esta semana, usar el primer día de la próxima semana
      int firstDay = sortedDays.first;
      int daysUntilNextWeek = 7 - currentWeekday + firstDay;
      return todayAlarmTime.add(Duration(days: daysUntilNextWeek));
    }

    // Fallback: mañana
    return todayAlarmTime.add(const Duration(days: 1));
  }

  void _handleShowAlarmScreen(MethodCall call) {
    final arguments = call.arguments as Map<String, dynamic>;
    final alarmId = arguments['alarmId'] as int;
    final title = arguments['title'] as String? ?? 'Alarma';
    final message = arguments['message'] as String? ?? '¡Es hora de despertar!';
    final maxSnoozes = arguments['maxSnoozes'] as int? ?? 3;
    final snoozeDurationMinutes =
        arguments['snoozeDurationMinutes'] as int? ?? 5;
    final snoozeCount = arguments['snoozeCount'] as int? ?? 0;

    // Buscar la alarma para obtener los datos de juegos
    final alarm = _alarms.firstWhere(
      (alarm) => alarm.id == alarmId,
      orElse: () => Alarm(
        id: alarmId,
        time: DateTime.now(),
        title: title,
        message: message,
      ),
    );

    Navigator.pushNamed(
      context,
      '/alarm',
      arguments: {
        'alarmId': alarmId,
        'title': title,
        'message': message,
        'maxSnoozes': maxSnoozes,
        'snoozeDurationMinutes': snoozeDurationMinutes,
        'snoozeCount': snoozeCount,
        'requireGame': alarm.requireGame, // Agregar
        'gameConfig': alarm.gameConfig, // Agregar
        'maxVolumePercent': alarm.maxVolumePercent,
        'volumeRampUpDurationSeconds': alarm.volumeRampUpDurationSeconds,
        'tempVolumeReductionPercent': alarm.tempVolumeReductionPercent,
        'tempVolumeReductionDurationSeconds': alarm.tempVolumeReductionDurationSeconds,
        'enableTts': alarm.enableTts,
        'ttsLanguage': alarm.ttsLanguage,
        'ttsVolume': alarm.ttsVolume,
        'ttsPitch': alarm.ttsPitch,
        'ttsRepeatCount': alarm.ttsRepeatCount,
        'ttsRepeatDelaySeconds': alarm.ttsRepeatDelaySeconds,
        'ttsUsePrefix': alarm.ttsUsePrefix,
        'ttsVoice': alarm.ttsVoice,
        'piperVoice': alarm.piperVoice,
      },
    );
  }

  Future<void> _handleNativeCalls(MethodCall call) async {
    print('=== HANDLE NATIVE CALLS START ===');
    print('Method: ${call.method}');
    print('Arguments: ${call.arguments}');

    final args = call.arguments != null
        ? Map<String, dynamic>.from(call.arguments)
        : {};
    final alarmId = args['alarmId'] as int?;

    switch (call.method) {
      case 'showAlarmScreen':
        final alarmId = call.arguments['alarmId'] as int;
        final title = call.arguments['title'] as String;
        final message = call.arguments['message'] as String;

        // NUEVO: Marcar que hay una alarma sonando
        setState(() {
          _isAlarmRinging = true;
          _ringingAlarmId = alarmId;
          _ringingAlarmTitle = title;
          _ringingAlarmMessage = message;
        });

        final maxSnoozesArg = (call.arguments['maxSnoozes'] as num?)?.toInt() ?? 3;
        final snoozeDurationArg =
            (call.arguments['snoozeDurationMinutes'] as num?)?.toInt() ?? 5;
        final snoozeCountArg = (call.arguments['snoozeCount'] as num?)?.toInt() ?? 0;
        final maxVolumePercentArg =
            (call.arguments['maxVolumePercent'] as num?)?.toInt() ?? 100;
        final volumeRampUpDurationSecondsArg =
            (call.arguments['volumeRampUpDurationSeconds'] as num?)?.toInt() ?? 30;
        final tempVolumeReductionPercentArg =
            (call.arguments['tempVolumeReductionPercent'] as num?)?.toInt() ?? 30;
        final tempVolumeReductionDurationSecondsArg =
            (call.arguments['tempVolumeReductionDurationSeconds'] as num?)?.toInt() ?? 60;

        final index = _alarms.indexWhere((a) => a.id == alarmId);
        final alarm = index != -1
            ? _alarms[index]
            : Alarm(
                id: alarmId,
                time: DateTime.now(),
                title: title,
                message: message,
                snoozeCount: snoozeCountArg,
                maxSnoozes: maxSnoozesArg,
                snoozeDurationMinutes: snoozeDurationArg,
                maxVolumePercent: maxVolumePercentArg,
                volumeRampUpDurationSeconds: volumeRampUpDurationSecondsArg,
                tempVolumeReductionPercent: tempVolumeReductionPercentArg,
                tempVolumeReductionDurationSeconds: tempVolumeReductionDurationSecondsArg,
              );

        setState(() {
          _ringingAlarmSnoozeCount = alarm.snoozeCount;
          _ringingAlarmMaxSnoozes = alarm.maxSnoozes;
          _ringingAlarmSnoozeDuration = alarm.snoozeDurationMinutes;
        });

        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => AlarmScreen(
                arguments: {
                  'alarmId': alarmId,
                  'title': title,
                  'message': message,
                  'snoozeCount': alarm.snoozeCount,
                  'maxSnoozes': alarm.maxSnoozes,
                  'snoozeDurationMinutes': alarm.snoozeDurationMinutes,
                  'requireGame': alarm.requireGame, // Agregar
                  'gameConfig': alarm.gameConfig,
                  'maxVolumePercent': alarm.maxVolumePercent,
                  'volumeRampUpDurationSeconds': alarm.volumeRampUpDurationSeconds,
                  'tempVolumeReductionPercent': alarm.tempVolumeReductionPercent,
                  'tempVolumeReductionDurationSeconds': alarm.tempVolumeReductionDurationSeconds,
                  'enableTts': alarm.enableTts,
                  'ttsLanguage': alarm.ttsLanguage,
                  'ttsVolume': alarm.ttsVolume,
                  'ttsPitch': alarm.ttsPitch,
                  'ttsRepeatCount': alarm.ttsRepeatCount,
                  'ttsRepeatDelaySeconds': alarm.ttsRepeatDelaySeconds,
                  'ttsUsePrefix': alarm.ttsUsePrefix,
                  'ttsVoice': alarm.ttsVoice,
                  'piperVoice': alarm.piperVoice,
                },
              ),
            ),
          );
        }
        break;
      case 'showHabitScreen':
        final habitId = call.arguments['habitId'] as String;
        final occurrenceKey = call.arguments['occurrenceKey'] as String;
        final scheduledAtLocalMillis =
            (call.arguments['scheduledAtLocalMillis'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch;
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => HabitAlertScreen(
                habitId: habitId,
                occurrenceKey: occurrenceKey,
                scheduledAtLocalMillis: scheduledAtLocalMillis,
              ),
            ),
          );
        }
        break;
      case 'showMedicationScreen':
        final medId = call.arguments['medicationId'] as String;
        final medOccurrenceKey = call.arguments['occurrenceKey'] as String;
        final medScheduledMillis =
            (call.arguments['scheduledAtLocalMillis'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch;
        print('[HomePage] showMedicationScreen medId=$medId occurrenceKey=$medOccurrenceKey');
        if (mounted && !_showingMedicationScreens.contains(medOccurrenceKey)) {
          _showingMedicationScreens.add(medOccurrenceKey);
          // Limpiar pending solo si podemos mostrar la pantalla
          platform.invokeMethod('getPendingMedicationScreen').catchError((_) {});
          Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder: (context) => MedicationAlertScreen(
                    arguments: {
                      'medicationId': medId,
                      'occurrenceKey': medOccurrenceKey,
                      'scheduledAtLocalMillis': medScheduledMillis,
                      ...Map<String, dynamic>.from(call.arguments as Map),
                    },
                  ),
                ),
              )
              .then((_) => _showingMedicationScreens.remove(medOccurrenceKey));
        }
        break;
      case 'showMedicationConfirmScreen':
        final medConfirmId = call.arguments['medicationId'] as String;
        final medConfirmKey = call.arguments['occurrenceKey'] as String;
        final medConfirmMillis =
            (call.arguments['scheduledAtLocalMillis'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch;
        print('[HomePage] showMedicationConfirmScreen medId=$medConfirmId occurrenceKey=$medConfirmKey');
        if (mounted && !_showingMedicationScreens.contains(medConfirmKey)) {
          _showingMedicationScreens.add(medConfirmKey);
          // Limpiar pending solo si podemos mostrar la pantalla
          platform.invokeMethod('getPendingMedicationScreen').catchError((_) {});
          Navigator.of(context)
              .push(
                MaterialPageRoute(
                  builder: (context) => MedicationConfirmScreen(
                    arguments: {
                      'medicationId': medConfirmId,
                      'occurrenceKey': medConfirmKey,
                      'scheduledAtLocalMillis': medConfirmMillis,
                      ...Map<String, dynamic>.from(call.arguments as Map),
                    },
                  ),
                ),
              )
              .then((_) => _showingMedicationScreens.remove(medConfirmKey));
        }
        break;
      // NUEVO: Manejar notificación de alarma sonando
      case 'notifyAlarmRinging':
        final alarmId = call.arguments['alarmId'] as int;
        final title = call.arguments['title'] as String;
        final message = call.arguments['message'] as String;
        final snoozeCount = call.arguments['snoozeCount'] as int;
        final maxSnoozes = call.arguments['maxSnoozes'] as int;
        final snoozeDuration = call.arguments['snoozeDurationMinutes'] as int;

        setState(() {
          _isAlarmRinging = true;
          _ringingAlarmId = alarmId;
          _ringingAlarmTitle = title;
          _ringingAlarmMessage = message;
          _ringingAlarmSnoozeCount = snoozeCount;
          _ringingAlarmMaxSnoozes = maxSnoozes;
          _ringingAlarmSnoozeDuration = snoozeDuration;
        });
        break;
      case 'alarmManuallyStopped':
        print('Alarm manually stopped: $alarmId');
        // NUEVO: Ocultar el contenedor de alarma sonando
        setState(() {
          _isAlarmRinging = false;
          _ringingAlarmId = null;
          _ringingAlarmTitle = '';
          _ringingAlarmMessage = '';
          _ringingAlarmSnoozeCount = 0;
        });

        if (alarmId != null) {
          await _handleAlarmStopped(alarmId);
        }
        // Cerrar la pantalla de alarma si está abierta
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        break;

      case 'alarmManuallySnoozed':
        final alarmId = call.arguments['alarmId'] as int;
        final newTimeInMillis = call.arguments['newTimeInMillis'] as int;

        // NUEVO: Ocultar el contenedor de alarma sonando cuando se pospone
        setState(() {
          _isAlarmRinging = false;
          _ringingAlarmId = null;
          _ringingAlarmTitle = '';
          _ringingAlarmMessage = '';
          _ringingAlarmSnoozeCount = 0;
        });

        await _handleAlarmSnoozed(alarmId, newTimeInMillis);

        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        break;
      case 'closeAlarmScreenIfOpen':
        print('Closing alarm screen if open for alarm: $alarmId');
        // NUEVO: También ocultar el contenedor cuando se cierra la pantalla
        setState(() {
          _isAlarmRinging = false;
          _ringingAlarmId = null;
          _ringingAlarmTitle = '';
          _ringingAlarmMessage = '';
          _ringingAlarmSnoozeCount = 0;
        });

        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        break;
    }
    print('=== HANDLE NATIVE CALLS END ===');
  }

  // NUEVO: Manejar cuando una alarma es detenida
  Future<void> _handleAlarmStopped(int alarmId) async {
    print('=== HANDLE ALARM STOPPED START ===');
    print('Processing stopped alarm ID: $alarmId');

    // Limpiar la marca de pantalla de alarma para permitir futuras activaciones
    try {
      await platform.invokeMethod('clearAlarmScreenFlag', {'alarmId': alarmId});
      print('Cleared alarm screen flag for alarm $alarmId');
    } catch (e) {
      print('Error clearing alarm screen flag: $e');
    }

    final index = _alarms.indexWhere((a) => a.id == alarmId);
    if (index != -1) {
      final alarm = _alarms[index];
      final repeating = _isRepeatingAlarm(alarm);
      print('Found alarm: ${alarm.title}, isRepeating: $repeating');

      // Si la alarma NO es repetitiva, desactivarla
      if (!repeating) {
        print('Non-repeating alarm, deactivating...');
        final updated = alarm.copyWith(isActive: false, snoozeCount: 0);
        setState(() {
          _alarms[index] = updated;
        });
        await _alarmRepository.upsertAlarm(
          alarm: updated,
          cloudSyncEnabled: _cloudSyncEnabled,
          userId: _currentUser?.uid,
        );

        print('Non-repeating alarm deactivated and saved');
      } else {
        // Si la alarma es repetitiva, solo desactivar si no hay snoozes activos
        if (alarm.snoozeCount == 0) {
          print(
            'Repeating alarm with no active snoozes, keeping active for next occurrence',
          );
          // Para alarmas repetitivas sin snoozes, mantener activa para la siguiente ocurrencia
          // No hacer nada, la alarma se reprogramará automáticamente
        } else {
          print('Repeating alarm with active snoozes, resetting snooze count');
          final updated = alarm.copyWith(snoozeCount: 0);
          setState(() {
            _alarms[index] = updated;
          });
          await _alarmRepository.upsertAlarm(
            alarm: updated,
            cloudSyncEnabled: _cloudSyncEnabled,
            userId: _currentUser?.uid,
          );
        }
      }

      _startOrUpdateCountdown();
    } else {
      print('Alarm with ID $alarmId not found in list');
    }
    print('=== HANDLE ALARM STOPPED END ===');
  }

  // NUEVO: Reprogramar alarma repetitiva
  // Future<void> _rescheduleRepeatingAlarm(Alarm alarm) async {
  //   print('=== RESCHEDULE REPEATING ALARM START ===');
  //   print('Rescheduling alarm: ${alarm.title}');

  //   try {
  //     await _setNativeAlarm(alarm);
  //     print('Repeating alarm rescheduled successfully');
  //   } catch (e) {
  //     print('Error rescheduling repeating alarm: $e');
  //   }
  //   print('=== RESCHEDULE REPEATING ALARM END ===');
  // }

  // NUEVO: Manejar cuando una alarma es pospuesta
  Future<void> _handleAlarmSnoozed(int alarmId, int newTimeInMillis) async {
    print('=== HANDLE ALARM SNOOZED START ===');
    print(
      'Processing snoozed alarm ID: $alarmId, new time: ${DateTime.fromMillisecondsSinceEpoch(newTimeInMillis)}',
    );

    final index = _alarms.indexWhere((a) => a.id == alarmId);
    if (index != -1) {
      final alarm = _alarms[index];
      print(
        'Found alarm: ${alarm.title}, current snooze count: ${alarm.snoozeCount}',
      );

      // SOLUCIÓN: Validar máximo de posposiciones antes de actualizar
      if (alarm.snoozeCount >= alarm.maxSnoozes) {
        print('Maximum snoozes reached for alarm $alarmId, deactivating alarm');

        final updatedAlarm = alarm.copyWith(isActive: false, snoozeCount: 0);

        setState(() {
          _alarms[index] = updatedAlarm;
        });

        await _alarmRepository.upsertAlarm(
          alarm: updatedAlarm,
          cloudSyncEnabled: _cloudSyncEnabled,
          userId: _currentUser?.uid,
        );

        _startOrUpdateCountdown();
        return;
      }

      // Continuar con la posposición normal
      final updatedAlarm = alarm.copyWith(
        snoozeCount: alarm.snoozeCount + 1,
      );
      setState(() {
        _alarms[index] = updatedAlarm;
      });
      await _alarmRepository.upsertAlarm(
        alarm: updatedAlarm,
        cloudSyncEnabled: _cloudSyncEnabled,
        userId: _currentUser?.uid,
      );

      _startOrUpdateCountdown();
      print(
        'Alarm snoozed and saved, new snooze count: ${_alarms[index].snoozeCount}',
      );
    } else {
      print('Alarm with ID $alarmId not found in list');
    }
    print('=== HANDLE ALARM SNOOZED END ===');
  }

  Future<void> _reloadAlarmsFromLocal() async {
    final alarms = await _alarmRepository.loadLocalAlarms();
    if (!mounted) return;
    setState(() {
      _alarms
        ..clear()
        ..addAll(alarms);
    });
    if (_currentGroupingOption != AlarmGroupingOption.none) {
      _initializeGroupStates();
    }
  }

  Future<void> _loadAlarms() async {
    await _alarmRepository.ensureMigrated();
    await _reloadAlarmsFromLocal();
  }

  Future<void> _setNativeAlarm(Alarm alarm) async {
    try {
      final repeatDays = _normalizeRepeatDaysForAlarm(alarm);
      final flags = _deriveRepeatFlags(repeatDays);
      await platform.invokeMethod('setAlarm', {
        'id': alarm.id,
        'hour': alarm.time.hour,
        'minute': alarm.time.minute,
        'title': alarm.title,
        'message': alarm.message,
        'screenRoute': '/alarm',
        'repeatDays': repeatDays,
        'isDaily': flags['isDaily'],
        'isWeekly': flags['isWeekly'],
        'isWeekend': flags['isWeekend'],
        'maxSnoozes': alarm.maxSnoozes,
        'snoozeDurationMinutes': alarm.snoozeDurationMinutes,
        'maxVolumePercent': alarm.maxVolumePercent,
        'volumeRampUpDurationSeconds': alarm.volumeRampUpDurationSeconds,
        'tempVolumeReductionPercent': alarm.tempVolumeReductionPercent,
        'tempVolumeReductionDurationSeconds': alarm.tempVolumeReductionDurationSeconds,
      });
    } catch (e) {
      print('Error setting native alarm: $e');
      rethrow;
    }
  }

  List<int> _normalizeRepeatDaysFromEditorResult({
    required String repetitionType,
    required List<int> repeatDays,
    required DateTime baseTime,
  }) {
    if (repetitionType == 'daily') return const [1, 2, 3, 4, 5, 6, 7];
    if (repetitionType == 'weekend') return const [6, 7];
    if (repetitionType == 'weekly') {
      if (repeatDays.isNotEmpty) return [repeatDays.first];
      return [baseTime.weekday];
    }
    if (repetitionType == 'custom') return List<int>.from(repeatDays);
    return const [];
  }

  Future<void> _setAlarm() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (context) => const AlarmEditScreen()),
    );

    if (result != null && mounted) {
      final selectedTime = result['time'] as TimeOfDay;
      final now = DateTime.now();
      final baseTime = DateTime(
        now.year,
        now.month,
        now.day,
        selectedTime.hour,
        selectedTime.minute,
        0,
        0,
      );

      final nowNormalized = DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
        0,
        0,
      );

      final title = result['title']!.isNotEmpty ? result['title']! : 'Alarma';
      final message = result['message']!.isNotEmpty
          ? result['message']!
          : '¡Es hora de despertar!';
      final repetitionType = result['repetitionType'] as String;
      final repeatDays = result['repeatDays'] as List<int>;
      final maxSnoozes = result['maxSnoozes'] ?? 3;
      final snoozeDuration = result['snoozeDuration'] ?? 5;
      final requireGame = result['requireGame'] ?? false;
      final gameConfig = result['gameConfig'] as GameConfig?;
      final syncToCloud = result['syncToCloud'] ?? true;
      final maxVolumePercent = result['maxVolumePercent'] ?? 100;
      final volumeRampUpDurationSeconds = result['volumeRampUpDurationSeconds'] ?? 0;
      final tempVolumeReductionPercent = result['tempVolumeReductionPercent'] ?? 50;
      final tempVolumeReductionDurationSeconds = result['tempVolumeReductionDurationSeconds'] ?? 30;
      final enableTts = result['enableTts'] as bool? ?? true;
      final ttsLanguage = result['ttsLanguage'] as String? ?? 'es-MX';
      final ttsVolume = result['ttsVolume'] as int? ?? 80;
      final ttsPitch = (result['ttsPitch'] as num?)?.toDouble() ?? 1.0;
      final ttsRepeatCount = result['ttsRepeatCount'] as int? ?? 3;
      final ttsRepeatDelaySeconds = result['ttsRepeatDelaySeconds'] as int? ?? 5;
      final ttsUsePrefix = result['ttsUsePrefix'] as bool? ?? false;
      final ttsVoice = result['ttsVoice'] as String?;
      final piperVoice = result['piperVoice'] as String?;

      final finalRepeatDays = _normalizeRepeatDaysFromEditorResult(
        repetitionType: repetitionType,
        repeatDays: repeatDays,
        baseTime: baseTime,
      );
      final flags = _deriveRepeatFlags(finalRepeatDays);
      final alarmTime = finalRepeatDays.isEmpty
          ? (baseTime.isBefore(nowNormalized) ||
                  baseTime.isAtSameMomentAs(nowNormalized)
              ? baseTime.add(const Duration(days: 1))
              : baseTime)
          : _calculateNextOccurrence(
              Alarm(
                id: 0,
                time: baseTime,
                title: title,
                message: message,
                repeatDays: finalRepeatDays,
                isDaily: flags['isDaily'] as bool,
                isWeekly: flags['isWeekly'] as bool,
                isWeekend: flags['isWeekend'] as bool,
              ),
              now,
            );

      // Crear un nuevo ID para la alarma
      final alarmId = DateTime.now().millisecondsSinceEpoch % 100000;

      // Crear la nueva alarma
      final alarm = Alarm(
        id: alarmId,
        time: alarmTime,
        title: title,
        message: message,
        isActive: true,
        repeatDays: finalRepeatDays,
        isDaily: flags['isDaily'] as bool,
        isWeekly: flags['isWeekly'] as bool,
        isWeekend: flags['isWeekend'] as bool,
        maxSnoozes: maxSnoozes,
        snoozeCount: 0,
        snoozeDurationMinutes: snoozeDuration,
        requireGame: requireGame,
        gameConfig: gameConfig,
        syncToCloud: syncToCloud,
        maxVolumePercent: maxVolumePercent,
        volumeRampUpDurationSeconds: volumeRampUpDurationSeconds,
        tempVolumeReductionPercent: tempVolumeReductionPercent,
        tempVolumeReductionDurationSeconds: tempVolumeReductionDurationSeconds,
        enableTts: enableTts,
        ttsLanguage: ttsLanguage,
        ttsVolume: ttsVolume,
        ttsPitch: ttsPitch,
        ttsRepeatCount: ttsRepeatCount,
        ttsRepeatDelaySeconds: ttsRepeatDelaySeconds,
        ttsUsePrefix: ttsUsePrefix,
        ttsVoice: ttsVoice,
        piperVoice: piperVoice,
      );

      try {
        await _setNativeAlarm(alarm);
        setState(() {
          _alarms.add(alarm);
        });
        await _alarmRepository.upsertAlarm(
          alarm: alarm,
          cloudSyncEnabled: _cloudSyncEnabled,
          userId: _currentUser?.uid,
        );
        await _reloadAlarmsFromLocal();

        if (!mounted) return;
        _startOrUpdateCountdown();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Alarma configurada y activa')),
        );
      } on PlatformException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al configurar alarma: ${e.message}')),
        );
      }
    }
  }

  Future<void> _editAlarm(Alarm alarm) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (context) => AlarmEditScreen(alarm: alarm)),
    );

    if (result != null && mounted) {
      final selectedTime = result['time'] as TimeOfDay;
      final now = DateTime.now();

      final baseTime = DateTime(
        now.year,
        now.month,
        now.day,
        selectedTime.hour,
        selectedTime.minute,
      );
      final nowNormalized = DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
        0,
        0,
      );

      final title = (result['title'] as String).isNotEmpty
          ? result['title'] as String
          : 'Alarma';
      final message = result['message'] as String;
      final repetitionType = result['repetitionType'] as String;
      final repeatDays = result['repeatDays'] as List<int>;
      final maxSnoozes = result['maxSnoozes'] ?? 3;
      final snoozeDuration = result['snoozeDuration'] ?? 5;
      final requireGame = result['requireGame'] ?? false;
      final gameConfig = result['gameConfig'] as GameConfig?;
      final syncToCloud = result['syncToCloud'] ?? true;
      final maxVolumePercent = result['maxVolumePercent'] ?? 100;
      final volumeRampUpDurationSeconds = result['volumeRampUpDurationSeconds'] ?? 0;
      final tempVolumeReductionPercent = result['tempVolumeReductionPercent'] ?? 50;
      final tempVolumeReductionDurationSeconds = result['tempVolumeReductionDurationSeconds'] ?? 30;
      final enableTts = result['enableTts'] as bool? ?? true;
      final ttsLanguage = result['ttsLanguage'] as String? ?? 'es-MX';
      final ttsVolume = result['ttsVolume'] as int? ?? 80;
      final ttsPitch = (result['ttsPitch'] as num?)?.toDouble() ?? 1.0;
      final ttsRepeatCount = result['ttsRepeatCount'] as int? ?? 3;
      final ttsRepeatDelaySeconds = result['ttsRepeatDelaySeconds'] as int? ?? 5;
      final ttsUsePrefix = result['ttsUsePrefix'] as bool? ?? false;
      final ttsVoice = result['ttsVoice'] as String?;
      final piperVoice = result['piperVoice'] as String?;

      // Verificar si syncToCloud cambió de true a false para eliminar de Firebase
      final previousSyncToCloud = alarm.syncToCloud;
      final shouldDeleteFromFirebase = previousSyncToCloud && !syncToCloud;

      final finalRepeatDays = _normalizeRepeatDaysFromEditorResult(
        repetitionType: repetitionType,
        repeatDays: repeatDays,
        baseTime: baseTime,
      );
      final flags = _deriveRepeatFlags(finalRepeatDays);
      final alarmTime = finalRepeatDays.isEmpty
          ? (baseTime.isBefore(nowNormalized) ||
                  baseTime.isAtSameMomentAs(nowNormalized)
              ? baseTime.add(const Duration(days: 1))
              : baseTime)
          : _calculateNextOccurrence(
              alarm.copyWith(
                time: baseTime,
                repeatDays: finalRepeatDays,
                isDaily: flags['isDaily'] as bool,
                isWeekly: flags['isWeekly'] as bool,
                isWeekend: flags['isWeekend'] as bool,
              ),
              now,
            );

      // Cancelar la alarma anterior
      try {
        await platform.invokeMethod('cancelAlarm', {'alarmId': alarm.id});
      } catch (e) {
        print('Error al cancelar la alarma anterior: $e');
      }

      final updatedAlarm = alarm.copyWith(
        time: alarmTime,
        title: title,
        message: message,
        repeatDays: finalRepeatDays,
        isDaily: flags['isDaily'] as bool,
        isWeekly: flags['isWeekly'] as bool,
        isWeekend: flags['isWeekend'] as bool,
        maxSnoozes: maxSnoozes,
        snoozeDurationMinutes: snoozeDuration,
        requireGame: requireGame,
        gameConfig: gameConfig,
        syncToCloud: syncToCloud,
        maxVolumePercent: maxVolumePercent,
        volumeRampUpDurationSeconds: volumeRampUpDurationSeconds,
        tempVolumeReductionPercent: tempVolumeReductionPercent,
        tempVolumeReductionDurationSeconds: tempVolumeReductionDurationSeconds,
        enableTts: enableTts,
        ttsLanguage: ttsLanguage,
        ttsVolume: ttsVolume,
        ttsPitch: ttsPitch,
        ttsRepeatCount: ttsRepeatCount,
        ttsRepeatDelaySeconds: ttsRepeatDelaySeconds,
        ttsUsePrefix: ttsUsePrefix,
      );
      updatedAlarm.ttsVoice = ttsVoice;
      updatedAlarm.piperVoice = piperVoice;

      final index = _alarms.indexWhere((a) => a.id == alarm.id);
      if (index != -1) {
        setState(() {
          _alarms[index] = updatedAlarm;
        });
      }

      await _alarmRepository.upsertAlarm(
        alarm: updatedAlarm,
        cloudSyncEnabled: _cloudSyncEnabled,
        userId: _currentUser?.uid,
      );

      if (_cloudSyncEnabled && _currentUser != null && shouldDeleteFromFirebase) {
        try {
          await _alarmFirebaseService.deleteAlarmToCloud(
            alarm.id,
            _currentUser!.uid,
          );
          await _alarmLocalService.clearDirty(alarm.id);
        } catch (e) {
          print('Error al eliminar alarma de Firebase: $e');
        }
      }

      await _reloadAlarmsFromLocal();

      // Reprogramar la alarma si está activa
      if (alarm.isActive) {
        try {
          final updatedAlarm =
              _alarms[_alarms.indexWhere((a) => a.id == alarm.id)];
          await _setNativeAlarm(updatedAlarm);
          if (!mounted) return;
          _startOrUpdateCountdown();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Alarma actualizada para ${DateFormat('HH:mm').format(alarm.time)}',
              ),
            ),
          );
        } catch (e) {
          print('Error al reprogramar la alarma: $e');
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error al reprogramar la alarma')),
          );
        }
      }
    }
  }

  Future<void> _toggleAlarmState(int alarmId, bool isActive) async {
    final index = _alarms.indexWhere((a) => a.id == alarmId);
    if (index != -1) {
      final alarm = _alarms[index];
      if (alarm.isActive == isActive) return; // No change needed

      try {
        Alarm updatedAlarm;
        if (isActive) {
          // Reactivar alarma: calcular el próximo tiempo de alarma antes de activarla
          final now = DateTime.now();
          DateTime nextOccurrence = _calculateNextOccurrence(alarm, now);

          // Crear una copia de la alarma con el tiempo actualizado para la próxima ocurrencia
          updatedAlarm = alarm.copyWith(time: nextOccurrence, isActive: true);

          // Setear la alarma con el tiempo actualizado
          await _setNativeAlarm(updatedAlarm);

          // Actualizar el objeto de alarma en la lista con el tiempo calculado
          setState(() {
            _alarms[index] = updatedAlarm;
          });
        } else {
          // Desactivar alarma: cancelarla
          if (_isAlarmRinging && _ringingAlarmId == alarm.id) {
            try {
              await platform.invokeMethod('stopAlarm', {'alarmId': alarm.id});
            } catch (_) {}
          }
          await platform.invokeMethod('cancelAlarm', {'alarmId': alarm.id});
          updatedAlarm = alarm.copyWith(isActive: false);
          setState(() {
            _alarms[index] = updatedAlarm;
          });
        }

        await _alarmRepository.upsertAlarm(
          alarm: updatedAlarm,
          cloudSyncEnabled: _cloudSyncEnabled,
          userId: _currentUser?.uid,
        );
        await _reloadAlarmsFromLocal();

        if (!mounted) return;
        _startOrUpdateCountdown();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Alarma ${isActive ? "activada" : "desactivada"}'),
            backgroundColor: isActive
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.error,
          ),
        );
      } on PlatformException catch (e) {
        setState(() {
          alarm.isActive = !isActive; // Revertir
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al ${isActive ? "activar" : "desactivar"} alarma: ${e.message}',
            ),
          ),
        );
        // Revertir el cambio en la UI si la operación nativa falla
        // _alarms[index].isActive = !isActive; // Opcional, dependiendo de la UX deseada
        // if(mounted) setState(() {});
      }
    }
  }

  Future<void> _deleteAlarm(int alarmId) async {
    final index = _alarms.indexWhere((a) => a.id == alarmId);
    if (index != -1) {
      final alarm = _alarms[index];
      try {
        if (alarm.isActive) {
          await platform.invokeMethod('cancelAlarm', {'alarmId': alarm.id});
        }
        await _alarmRepository.deleteAlarm(
          alarmId: alarm.id,
          cloudSyncEnabled: _cloudSyncEnabled,
          userId: _currentUser?.uid,
        );
        await _reloadAlarmsFromLocal();
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Alarma eliminada')));
      } on PlatformException catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al eliminar alarma: ${e.message}')),
        );
      }
    }
  }

  Map<String, List<Alarm>> _getGroupedAlarms() {
    Map<String, List<Alarm>> grouped = {};
    if (_currentGroupingOption == AlarmGroupingOption.none) return {};

    int groupSizeHours;
    switch (_currentGroupingOption) {
      case AlarmGroupingOption.twelveHour:
        groupSizeHours = 12;
        break;
      case AlarmGroupingOption.sixHour:
        groupSizeHours = 6;
        break;
      case AlarmGroupingOption.fourHour:
        groupSizeHours = 4;
        break;
      case AlarmGroupingOption.twoHour:
        groupSizeHours = 2;
        break;
      default:
        return {};
    }

    for (int i = 0; i < 24; i += groupSizeHours) {
      final startHour = i;
      final endHour = (i + groupSizeHours - 1) % 24;
      final groupKey =
          '${startHour.toString().padLeft(2, '0')}:00 - ${endHour.toString().padLeft(2, '0')}:59';
      grouped[groupKey] = [];
    }

    for (var alarm in _alarms) {
      int alarmHour = alarm.time.hour;
      for (var groupKey in grouped.keys) {
        final parts = groupKey.split(' - ');
        final startHour = int.parse(parts[0].split(':')[0]);
        final endHour = int.parse(parts[1].split(':')[0]);

        // Manejar rangos que cruzan la medianoche para la última cubeta del día
        if (startHour <= endHour) {
          // Rango normal (e.g., 06:00 - 11:59)
          if (alarmHour >= startHour && alarmHour <= endHour) {
            grouped[groupKey]!.add(alarm);
            break;
          }
        } else {
          // Rango que cruza la medianoche (e.g., 22:00 - 01:59) - esto es para el último grupo si groupSizeHours no divide 24
          // Esta lógica se simplifica si asumimos que los grupos no cruzan la medianoche de forma extraña
          // Para los grupos definidos (12,6,4,2), siempre se alinearán bien dentro de las 24h.
          // La clave es que endHour es el final del bucket, no el inicio del siguiente.
          // Ejemplo: 2 horas -> 00-01, 02-03, ..., 22-23.
          // El endHour calculado como (i + groupSizeHours -1) % 24 asegura esto.
          if (alarmHour >= startHour && alarmHour <= endHour) {
            // Esta condición es suficiente
            grouped[groupKey]!.add(alarm);
            break;
          }
        }
      }
    }
    // Ordenar alarmas dentro de cada grupo
    grouped.forEach((key, value) {
      value.sort((a, b) => a.time.compareTo(b.time));
    });
    return grouped;
  }

  // At the top of _HomePageState class
  Timer? _countdownTimer;
  Duration _timeUntilNextAlarm = Duration.zero;
  Alarm? _currentNextAlarmForCountdown;
  DateTime? _nextCalendarAlarmTimeLocal;
  String _nextCalendarAlarmTitle = '';
  String _nextCalendarAlarmMessage = '';

  // In initState or a method called when alarms/settings change:
  void _startOrUpdateCountdown() {
    _countdownTimer?.cancel();

    final nextAlarm = _getNextActiveAlarm();
    _currentNextAlarmForCountdown = nextAlarm;

    if (nextAlarm != null) {
      _updateCountdown();
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _updateCountdown();
      });
    } else {
      setState(() {
        _timeUntilNextAlarm = Duration.zero;
      });
    }
  }

  void _updateCountdown() {
    if (_currentNextAlarmForCountdown != null) {
      final now = DateTime.now();
      final difference = _currentNextAlarmForCountdown!.time.difference(now);

      if (difference.isNegative) {
        // Si la alarma ya pasó, recalcular la próxima alarma
        _startOrUpdateCountdown();
      } else {
        setState(() {
          _timeUntilNextAlarm = difference;
        });
      }
    }
  }

  Alarm? _getNextActiveAlarm() {
    final now = DateTime.now();
    final activeAlarms = _alarms.where((alarm) => alarm.isActive).toList();

    Alarm? nextAlarm;
    Duration? shortestDuration;

    for (final alarm in activeAlarms) {
      DateTime nextAlarmTime;

      // SIEMPRE calcular basándose en la hora actual, no en la fecha original
      if (_isRepeatingAlarm(alarm)) {
        nextAlarmTime = _calculateNextOccurrence(alarm, now);
      } else {
        // Para alarmas no repetitivas, usar la hora actual como base
        nextAlarmTime = DateTime(
          now.year,
          now.month,
          now.day,
          alarm.time.hour,
          alarm.time.minute,
        );

        // Si la hora ya pasó hoy, programar para mañana
        if (nextAlarmTime.isBefore(now) ||
            nextAlarmTime.isAtSameMomentAs(now)) {
          nextAlarmTime = nextAlarmTime.add(const Duration(days: 1));
        }
      }

      final duration = nextAlarmTime.difference(now);
      if (duration.isNegative) continue;

      if (shortestDuration == null || duration < shortestDuration) {
        shortestDuration = duration;
        nextAlarm = Alarm(
          id: alarm.id,
          time: nextAlarmTime, // Usar el tiempo calculado, no el original
          title: alarm.title,
          message: alarm.message,
          isActive: alarm.isActive,
          repeatDays: alarm.repeatDays,
          isDaily: alarm.isDaily,
          isWeekly: alarm.isWeekly,
          isWeekend: alarm.isWeekend,
          snoozeCount: alarm.snoozeCount,
          maxSnoozes: alarm.maxSnoozes,
          snoozeDurationMinutes: alarm.snoozeDurationMinutes,
          requireGame: alarm.requireGame,
          gameConfig: alarm.gameConfig,
          syncToCloud: alarm.syncToCloud,
        );
      }
    }

    final nextCalendar = _nextCalendarAlarmTimeLocal;
    if (nextCalendar != null) {
      final calendarDuration = nextCalendar.difference(now);
      if (!calendarDuration.isNegative &&
          (shortestDuration == null || calendarDuration < shortestDuration)) {
        nextAlarm = Alarm(
          id: -1,
          time: nextCalendar,
          title: _nextCalendarAlarmTitle.isNotEmpty ? _nextCalendarAlarmTitle : 'Calendario',
          message: _nextCalendarAlarmMessage,
          isActive: true,
        );
      }
    }

    return nextAlarm;
  }

  DateTime _calculateNextOccurrence(Alarm alarm, DateTime now) {
    final repeatDays = _normalizeRepeatDaysForAlarm(alarm);
    final baseTime = DateTime(
      now.year,
      now.month,
      now.day,
      alarm.time.hour,
      alarm.time.minute,
    );
    print(
      'Calculating next occurrence - Current: $now, Target time: ${alarm.time.hour}:${alarm.time.minute}, RepeatDays: $repeatDays',
    );

    if (repeatDays.isNotEmpty) {
      if (repeatDays.contains(now.weekday) && baseTime.isAfter(now)) {
        print('Repeat alarm: scheduling for today');
        return baseTime;
      }

      for (int daysToAdd = 1; daysToAdd <= 7; daysToAdd++) {
        final testDate = now.add(Duration(days: daysToAdd));
        if (repeatDays.contains(testDate.weekday)) {
          final next = DateTime(
            testDate.year,
            testDate.month,
            testDate.day,
            alarm.time.hour,
            alarm.time.minute,
          );
          print('Repeat alarm: scheduling for next occurrence in $daysToAdd days');
          return next;
        }
      }
    }

    if (baseTime.isAfter(now)) {
      print('One-time alarm: scheduling for today');
      return baseTime;
    }
    print('One-time alarm: time passed today, scheduling for tomorrow');
    return baseTime.add(const Duration(days: 1));
  }

  String _formatDuration(Duration duration) {
    if (duration.isNegative || duration == Duration.zero) {
      return '--:--:--';
    }

    final days = duration.inDays;
    final hours = duration.inHours.remainder(24);
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (days > 0) {
      // Formato: dd:hh:mm:ss
      return '${days.toString().padLeft(2, '0')}:${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else if (hours > 0) {
      // Formato: hh:mm:ss
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      // Formato: mm:ss
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  Widget _buildNextAlarmSection() {
    final scheme = Theme.of(context).colorScheme;
    final nextAlarm = _getNextActiveAlarm();
    if (nextAlarm == null || !_showNextAlarmSection) {
      return const SizedBox.shrink();
    }

    final otherActiveAlarmsCount = _alarms
        .where((alarm) => alarm.id != nextAlarm.id && alarm.isActive)
        .length;

    return Container(
      margin: const EdgeInsets.all(8.0),
      padding: const EdgeInsets.only(
        left: 16.0,
        top: 16.0,
        bottom: 0,
        right: 16.0,
      ),
      decoration: BoxDecoration(
        color: scheme.primary.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.primary, width: 2),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Próxima Alarma: ${TimeOfDay.fromDateTime(nextAlarm.time).format(context)}'
                .toUpperCase(),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.all(0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: scheme.primary),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(
                      nextAlarm.title,
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: scheme.onSurface),
                    ),
                    if (nextAlarm.message.isNotEmpty)
                      Text(
                        nextAlarm.message,
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: scheme.onSurface),
                      ),
                  ],
                ),
                Switch(
                  value: nextAlarm.isActive,
                  onChanged: (bool value) {
                    _toggleAlarmState(nextAlarm.id, value);
                  },
                  activeColor: scheme.primary,
                  inactiveThumbColor: scheme.onSurface,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            margin: const EdgeInsets.all(0),
            padding: const EdgeInsets.all(0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        otherActiveAlarmsCount > 0
                            ? '$otherActiveAlarmsCount otra${otherActiveAlarmsCount > 1 ? 's' : ''} alarma${otherActiveAlarmsCount > 1 ? 's' : ''} activa${otherActiveAlarmsCount > 1 ? 's' : ''}'
                            : 'No hay otras alarmas activas',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: scheme.primary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    if (otherActiveAlarmsCount > 0) ...[
                      IconButton(
                        icon: Icon(
                          moreAlarms ? Icons.visibility_off : Icons.visibility,
                          size: 20,
                          color: scheme.primary,
                        ),
                        onPressed: () {
                          setState(() {
                            moreAlarms = !moreAlarms;
                          });
                        },
                        tooltip: moreAlarms
                            ? 'Ocultar alarmas'
                            : 'Mostrar alarmas',
                      ),
                    ],
                    const SizedBox(width: 16),
                  ],
                ),
                // Lista de alarmas adicionales (ahora fuera del Row)
                if (moreAlarms && otherActiveAlarmsCount > 0) ...[
                  const SizedBox(height: 8),
                  Container(
                    margin: const EdgeInsets.only(bottom: 5),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: scheme.primary,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      children: _alarms
                          .where(
                            (alarm) =>
                                alarm.id != nextAlarm.id && alarm.isActive,
                          )
                          .map(
                            (alarm) => Container(
                              // decoration: BoxDecoration(
                              //   border: Border(
                              //     bottom: BorderSide(
                              //       color: Colors.grey[700]!,
                              //       width: 0.5,
                              //     ),
                              //   ),
                              // ),
                              child: ListTile(
                                dense: true,
                                leading: Icon(
                                  Icons.alarm,
                                  color: scheme.primary,
                                  size: 20,
                                ),
                                title: Text(
                                  alarm.title,
                                  style: TextStyle(
                                    color: scheme.onSurface,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (alarm.message.isNotEmpty)
                                      Text(
                                        alarm.message,
                                        style: TextStyle(
                                          color: scheme.onSurface,
                                          fontSize: 11,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    Text(
                                      'Sonará a las ${DateFormat('HH:mm').format(alarm.time)}',
                                      style: TextStyle(
                                        color: scheme.onSurface,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Switch(
                                  value: alarm.isActive,
                                  onChanged: (bool value) {
                                    _toggleAlarmState(alarm.id, value);
                                  },
                                  activeColor: scheme.primary,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onTap: () {
                                  _editAlarm(alarm);
                                },
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlarmItem(Alarm alarm) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary, width: 1),
      ),
      child: ListTile(
        leading: PopupMenuButton<String>(
          onSelected: (String result) {
            if (result == 'delete') {
              _deleteAlarm(alarm.id);
            } else if (result == 'edit') {
              _editAlarm(alarm);
            }
          },
          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
            const PopupMenuItem<String>(value: 'edit', child: Text('Editar')),
            const PopupMenuItem<String>(value: 'delete', child: Text('Eliminar')),
          ],
        ),
        title: RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '${alarm.title} ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: scheme.onSurface,
                  fontSize: 16,
                ),
              ),
              if (alarm.isRepeating())
                TextSpan(
                  text: _getRepeatDaysPrefix(alarm),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              alarm.message.isNotEmpty ? alarm.message : 'Sin mensaje',
              style: TextStyle(color: scheme.onSurface),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Text('Próxima vez: ', style: TextStyle(color: scheme.onSurface)),
                Text(
                  TimeOfDay.fromDateTime(alarm.time).format(context),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
            if (alarm.isActive)
              Builder(
                builder: (context) {
                  final durationUntilAlarm = _calculateTimeUntilAlarm(alarm);
                  return Text(
                    'Faltan: ${_formatDuration(durationUntilAlarm)}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: scheme.primary),
                  );
                },
              ),
          ],
        ),
        trailing: Switch(
          value: alarm.isActive,
          onChanged: (bool value) {
            _toggleAlarmState(alarm.id, value);
          },
          activeColor: scheme.primary,
          inactiveThumbColor: scheme.onSurface,
        ),
      ),
    );
  }

  // NUEVO: Método para construir el contenedor de alarma sonando
  Widget _buildRingingAlarmContainer() {
    if (!_isAlarmRinging || _ringingAlarmId == null) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final canSnooze = _ringingAlarmSnoozeCount < _ringingAlarmMaxSnoozes;
    
    // Encontrar la alarma actual para obtener configuraciones de volumen
    final currentAlarm = _alarms.firstWhere(
      (alarm) => alarm.id == _ringingAlarmId,
      orElse: () => Alarm(
        id: _ringingAlarmId!,
        time: DateTime.now(),
        title: _ringingAlarmTitle,
        message: _ringingAlarmMessage,
        isActive: true,
      ),
    );

    return GestureDetector(
      onTap: () {
        // Navegar a AlarmScreen cuando se toca el contenedor
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => AlarmScreen(
              arguments: {
                'alarmId': _ringingAlarmId!,
                'title': _ringingAlarmTitle,
                'message': _ringingAlarmMessage,
                'snoozeCount': _ringingAlarmSnoozeCount,
                'maxSnoozes': _ringingAlarmMaxSnoozes,
                'snoozeDurationMinutes': _ringingAlarmSnoozeDuration,
                'maxVolumePercent': currentAlarm.maxVolumePercent,
                'volumeRampUpDurationSeconds': currentAlarm.volumeRampUpDurationSeconds,
                'tempVolumeReductionPercent': currentAlarm.tempVolumeReductionPercent,
                'tempVolumeReductionDurationSeconds': currentAlarm.tempVolumeReductionDurationSeconds,
              },
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.all(8.0),
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(color: scheme.error, width: 2),
          boxShadow: [
            BoxShadow(
              color: scheme.error.withOpacity(0.25),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(Icons.alarm, color: scheme.error, size: 35),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ALARMA SONANDO',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: scheme.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Center(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _ringingAlarmTitle.toUpperCase(),
                    style: TextStyle(
                      fontSize: 35,
                      fontWeight: FontWeight.bold,
                      color: scheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_ringingAlarmMessage.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _ringingAlarmMessage,
                      style: TextStyle(
                        fontSize: 20,
                        color: scheme.error,
                        fontWeight: FontWeight.w900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),
            
            // Configuración de volumen
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: scheme.outline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Configuración de Volumen',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Volumen máximo: ${currentAlarm.maxVolumePercent}%',
                    style: TextStyle(color: scheme.onSurface),
                  ),
                  Text(
                    'Aumento gradual: ${currentAlarm.volumeRampUpDurationSeconds}s',
                    style: TextStyle(color: scheme.onSurface),
                  ),
                  const SizedBox(height: 8),
                  SynchronizedVolumeControlButton(
                    tempVolumePercent: currentAlarm.tempVolumeReductionPercent,
                    durationSeconds: currentAlarm.tempVolumeReductionDurationSeconds,
                    onToggle: (isActive) {
                      // Manejar activación/desactivación de reducción temporal
                      print('Volume reduction toggled in home: $isActive');
                    },
                    onExpired: () {
                      // Manejar expiración de reducción temporal
                      print('Volume reduction expired in home');
                    },
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await platform.invokeMethod('stopAlarm', {
                        'alarmId': _ringingAlarmId,
                      });
                    } catch (e) {
                      print('Error stopping alarm: $e');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'APAGAR ALARMA',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                ),

                const SizedBox(height: 12),
                if (canSnooze)
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        await platform.invokeMethod('snoozeAlarm', {
                          'alarmId': _ringingAlarmId,
                          'maxSnoozes': _ringingAlarmMaxSnoozes,
                          'snoozeDurationMinutes': _ringingAlarmSnoozeDuration,
                        });
                      } catch (e) {
                        print('Error snoozing alarm: $e');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: scheme.error,
                      foregroundColor: scheme.onError,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      'POSPONER $_ringingAlarmSnoozeDuration MIN',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (!canSnooze) ...[
                  Container(
                    padding: const EdgeInsets.all(8.0),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: scheme.error),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(Icons.warning, color: scheme.onErrorContainer, size: 25),
                        Text(
                          'Máximo Posposiciones Alcanzado ($_ringingAlarmSnoozeCount/$_ringingAlarmMaxSnoozes)',
                          style: TextStyle(
                            color: scheme.onErrorContainer,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  // NUEVA: Función para obtener el prefijo de días de repetición
  String _getRepeatDaysPrefix(Alarm alarm) {
    if (!alarm.isRepeating()) {
      return '';
    }

    if (alarm.isDaily) {
      return '[Diario] ';
    }

    if (alarm.isWeekend) {
      return '[Fin de semana] ';
    }

    if (alarm.isWeekly) {
      return '[Semanal] ';
    }

    if (alarm.repeatDays.isNotEmpty) {
      List<String> dayNames = ['L', 'M', 'X', 'J', 'V', 'S', 'D'];
      List<String> activeDays = [];

      for (int day in alarm.repeatDays) {
        if (day >= 1 && day <= 7) {
          activeDays.add(dayNames[day - 1]);
        }
      }

      if (activeDays.isNotEmpty) {
        return '[${activeDays.join(',')}] ';
      }
    }

    return '';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    Map<String, List<Alarm>> groupedAlarms =
        _currentGroupingOption != AlarmGroupingOption.none
        ? _getGroupedAlarms()
        : {};

    final scheme = Theme.of(context).colorScheme;
    // Verificar si hay alarmas activas
    final hasActiveAlarms = _alarms.any((alarm) => alarm.isActive);
    final hasNextCalendarAlarm = _nextCalendarAlarmTimeLocal != null;
    final nextAlarm = _getNextActiveAlarm();

    final body = SingleChildScrollView(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasActiveAlarms || hasNextCalendarAlarm) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                color: (hasActiveAlarms || hasNextCalendarAlarm) ? scheme.primary : scheme.surface,
                child: Text(
                  (hasActiveAlarms || hasNextCalendarAlarm)
                      ? 'Próxima alarma en: ${_formatDuration(_timeUntilNextAlarm)}'
                      : 'No hay alarmas activas',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: (hasActiveAlarms || hasNextCalendarAlarm)
                        ? scheme.onPrimary
                        : scheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],

            // Contenedor para alarma sonando
            _buildRingingAlarmContainer(),

            // Contenedor para alarmas pospuestas
            if (_getSnoozedAlarms().isNotEmpty)
              Container(
                margin: const EdgeInsets.all(8.0),
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: scheme.secondary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8.0),
                  border: Border.all(color: scheme.secondary, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: scheme.secondary.withOpacity(0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.snooze,
                          color: scheme.secondary,
                          size: 35,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Alarmas Pospuestas (${_getSnoozedAlarms().length})'
                              .toUpperCase(),
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: scheme.secondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._getSnoozedAlarms().map(
                      (alarm) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: scheme.secondary),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        alarm.title,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Faltan: ${_formatDuration(_calculateTimeUntilSnoozedAlarm(alarm))}',
                                        style: TextStyle(
                                          color: scheme.secondary,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    'Sonará a las: ${DateFormat('HH:mm').format(_calculateSnoozedAlarmTime(alarm))}',
                                    style: TextStyle(
                                      color: scheme.onSurface,
                                    ),
                                  ),
                                  Text(
                                    'Pospuesta: ${alarm.snoozeCount}/${alarm.maxSnoozes} veces',
                                    style: TextStyle(
                                      color: scheme.secondary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () async {
                                try {
                                  await platform.invokeMethod('cancelAlarm', {
                                    'alarmId': alarm.id,
                                  });
                                } catch (_) {}

                                final updatedAlarm = alarm.copyWith(
                                  isActive: false,
                                  snoozeCount: 0,
                                );
                                final index = _alarms.indexWhere(
                                  (a) => a.id == alarm.id,
                                );
                                if (index != -1) {
                                  setState(() {
                                    _alarms[index] = updatedAlarm;
                                  });
                                }

                                await _alarmRepository.upsertAlarm(
                                  alarm: updatedAlarm,
                                  cloudSyncEnabled: _cloudSyncEnabled,
                                  userId: _currentUser?.uid,
                                );
                                await _reloadAlarmsFromLocal();
                              },
                              icon: Icon(
                                Icons.cancel,
                                color: scheme.error,
                              ),
                              tooltip: 'Desactivar alarma pospuesta',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Sección de próxima alarma
            _buildNextAlarmSection(),

            // Lista de alarmas (sin Expanded, ahora dentro del scroll)
            _alarms.isEmpty
                ? SizedBox(
                    height: 200,
                    child: const Center(
                      child: Text('No hay alarmas configuradas'),
                    ),
                  )
                : _currentGroupingOption == AlarmGroupingOption.none
                ? Column(
                    children: _alarms
                        .map((alarm) => _buildAlarmItem(alarm))
                        .toList(),
                  )
                : Column(
                    children: groupedAlarms.keys.map((groupKey) {
                      List<Alarm> alarmsInGroup = groupedAlarms[groupKey]!;
                      bool showActiveOnly =
                          _groupShowActiveOnlyState[groupKey] ?? false;

                      List<Alarm> displayAlarms = showActiveOnly
                          ? alarmsInGroup.where((a) => a.isActive).toList()
                          : alarmsInGroup;

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        elevation: 1.0,
                        color: scheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                          side: BorderSide(color: scheme.primary, width: 2),
                        ),
                        child: ExpansionTile(
                          collapsedIconColor: Colors.transparent,
                          key: PageStorageKey(groupKey),
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              IconButton(
                                icon: Icon(
                                  showActiveOnly
                                      ? Icons.alarm_on
                                      : Icons.alarm_off,
                                ),
                                color: scheme.onSurface,
                                iconSize: 35,
                                tooltip: showActiveOnly
                                    ? 'Mostrar todas'
                                    : 'Mostrar solo activas',
                                onPressed: () {
                                  setState(() {
                                    _groupShowActiveOnlyState[groupKey] =
                                        !showActiveOnly;
                                  });
                                },
                              ),
                              const SizedBox(width: 80),
                              Padding(
                                padding: EdgeInsets.only(top: 5),
                                child: Text(
                                  groupKey,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context).colorScheme.onSurface,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ],
                          ),
                          initiallyExpanded:
                              _groupExpansionState[groupKey] ?? false,
                          onExpansionChanged: (isExpanded) {
                            setState(() {
                              _groupExpansionState[groupKey] = isExpanded;
                            });
                          },
                          shape: Border.all(color: Colors.transparent),
                          children: displayAlarms.isEmpty
                              ? [
                                  ListTile(
                                    title: Center(
                                      child: Text(
                                        'No hay alarmas en este grupo',
                                        style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                                      ),
                                    ),
                                  ),
                                ]
                              : displayAlarms
                                    .map((alarm) => _buildAlarmItem(alarm))
                                    .toList(),
                        ),
                      );
                    }).toList(),
                  ),
          ],
        ),
    );

    final fab = FloatingActionButton(
      onPressed: _setAlarm,
      tooltip: 'Añadir alarma',
      focusColor: scheme.onPrimary,
      foregroundColor: scheme.onPrimary,
      backgroundColor: scheme.primary,
      child: const Icon(Icons.add),
    );

    if (widget.embedInShell) {
      return Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: body,
      );
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Padding(
          padding: const EdgeInsets.only(left: 85),
          child: Text(
            'The Good Alarm',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 25,
            ),
          ),
        ),
        actions: [
          Theme(
            data: Theme.of(context).copyWith(
              popupMenuTheme: PopupMenuThemeData(
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: scheme.primary, width: 2.0),
                  borderRadius: BorderRadius.circular(4.0),
                ),
              ),
            ),
            child: PopupMenuButton<String>(
              color: scheme.surface,
              icon: const Icon(Icons.more_vert, size: 30),
              onSelected: (String value) async {
                switch (value) {
                  case 'settings':
                    await Navigator.pushNamed(context, '/settings');
                    _loadSettingsAndAlarms();
                    break;
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'settings',
                  child: Row(
                    children: [
                      Icon(Icons.settings, color: scheme.onSurface),
                      const SizedBox(width: 8),
                      Text(
                        'Configuración',
                        style: TextStyle(color: scheme.onSurface),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          final initial = Offset(
            size.width - _fabSize - _fabMargin,
            size.height - _fabSize - _fabMargin,
          );
          final current = _fabOffset ?? initial;
          final clamped = Offset(
            current.dx.clamp(_fabMargin, size.width - _fabSize - _fabMargin),
            current.dy.clamp(_fabMargin, size.height - _fabSize - _fabMargin),
          );
          _fabOffset = clamped;

          return Stack(
            children: [
              body,
              Positioned(
                left: clamped.dx,
                top: clamped.dy,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    final next = Offset(
                      (_fabOffset!.dx + details.delta.dx).clamp(
                        _fabMargin,
                        size.width - _fabSize - _fabMargin,
                      ),
                      (_fabOffset!.dy + details.delta.dy).clamp(
                        _fabMargin,
                        size.height - _fabSize - _fabMargin,
                      ),
                    );
                    setState(() {
                      _fabOffset = next;
                    });
                  },
                  child: fab,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
