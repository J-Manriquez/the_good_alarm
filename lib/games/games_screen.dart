import 'package:flutter/material.dart';
import 'package:the_good_alarm/games/modelo_juegos.dart';
import 'game_config_screen.dart';

class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Minijuegos'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
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
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => GameConfigScreen(gameType: gameType),
            ),
          );
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
              Icon(
                icon,
                size: 48,
                color: Colors.white,
              ),
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
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

