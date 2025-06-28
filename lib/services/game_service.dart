import 'package:flutter/material.dart';
import 'package:the_good_alarm/games/alarm_game_config.dart';
import 'package:the_good_alarm/games/modelo_juegos.dart';

class GameService {
  static Future<GameConfig?> selectGameForAlarm(BuildContext context) async {
    // Navegar a la pantalla de selección de juegos
    final GameType? selectedGameType = await Navigator.push<GameType>(
      context,
      MaterialPageRoute(builder: (context) => const GameSelectionScreen()),
    );

    if (selectedGameType == null) return null;

    // Navegar a la configuración del juego seleccionado
    final GameConfig? gameConfig = await Navigator.push<GameConfig>(
      context,
      MaterialPageRoute(
        builder: (context) => AlarmGameConfigScreen(gameType: selectedGameType, isAlarmMode: true,),
      ),
    );

    return gameConfig;
  }
}

class GameSelectionScreen extends StatelessWidget {
  const GameSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Seleccionar Juego para Alarma',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'Selecciona el juego que deberás completar para apagar la alarma:',
              style: TextStyle(color: Colors.white, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                children: [
                  _GameCard(
                    title: 'Memorice',
                    description: 'Encuentra las parejas de cartas',
                    icon: Icons.memory,
                    color: Colors.purple,
                    gameType: GameType.memorice,
                  ),
                  _GameCard(
                    title: 'Ecuaciones',
                    description: 'Resuelve problemas matemáticos',
                    icon: Icons.calculate,
                    color: Colors.green,
                    gameType: GameType.equations,
                  ),
                  _GameCard(
                    title: 'Secuencia',
                    description: 'Sigue el patrón de luces',
                    icon: Icons.lightbulb,
                    color: Colors.orange,
                    gameType: GameType.sequence,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameCard extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final GameType gameType;

  const _GameCard({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.gameType,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: () {
          Navigator.pop(context, gameType);
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withOpacity(0.8), color],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48, color: Colors.white),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  description,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

