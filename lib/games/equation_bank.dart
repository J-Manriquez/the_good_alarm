import 'dart:math';
import 'modelo_por_juego.dart';
import 'modelo_juegos.dart';

class EquationBank {
  static final Map<String, List<Map<String, dynamic>>> _equations = {
    // Suma y resta - Simples (1 operación)
    'addSubtract_1': [
      {'equation': '5 + 3', 'result': 8},
      {'equation': '12 - 7', 'result': 5},
      {'equation': '8 + 6', 'result': 14},
      {'equation': '15 - 9', 'result': 6},
      {'equation': '7 + 4', 'result': 11},
      {'equation': '20 - 13', 'result': 7},
      {'equation': '9 + 8', 'result': 17},
      {'equation': '16 - 8', 'result': 8},
      {'equation': '6 + 7', 'result': 13},
      {'equation': '18 - 11', 'result': 7},
      {'equation': '11 + 5', 'result': 16},
      {'equation': '14 - 6', 'result': 8},
      {'equation': '13 + 9', 'result': 22},
      {'equation': '25 - 17', 'result': 8},
      {'equation': '8 + 12', 'result': 20},
      {'equation': '19 - 12', 'result': 7},
      {'equation': '15 + 7', 'result': 22},
      {'equation': '23 - 15', 'result': 8},
      {'equation': '17 + 6', 'result': 23},
      {'equation': '21 - 14', 'result': 7},
    ],
    
    // Suma y resta - Intermedias (2 operaciones)
    'addSubtract_2': [
      {'equation': '5 + 3 - 2', 'result': 6},
      {'equation': '12 - 7 + 4', 'result': 9},
      {'equation': '8 + 6 - 5', 'result': 9},
      {'equation': '15 - 9 + 3', 'result': 9},
      {'equation': '7 + 4 - 6', 'result': 5},
      {'equation': '20 - 13 + 8', 'result': 15},
      {'equation': '9 + 8 - 7', 'result': 10},
      {'equation': '16 - 8 + 5', 'result': 13},
      {'equation': '6 + 7 - 4', 'result': 9},
      {'equation': '18 - 11 + 6', 'result': 13},
      {'equation': '11 + 5 - 8', 'result': 8},
      {'equation': '14 - 6 + 9', 'result': 17},
      {'equation': '13 + 9 - 12', 'result': 10},
      {'equation': '25 - 17 + 11', 'result': 19},
      {'equation': '8 + 12 - 9', 'result': 11},
      {'equation': '19 - 12 + 7', 'result': 14},
      {'equation': '15 + 7 - 13', 'result': 9},
      {'equation': '23 - 15 + 10', 'result': 18},
      {'equation': '17 + 6 - 11', 'result': 12},
      {'equation': '21 - 14 + 8', 'result': 15},
    ],
    
    // Suma y resta - Complejas (3 operaciones)
    'addSubtract_3': [
      {'equation': '5 + 3 - 2 + 4', 'result': 10},
      {'equation': '12 - 7 + 4 - 3', 'result': 6},
      {'equation': '8 + 6 - 5 + 7', 'result': 16},
      {'equation': '15 - 9 + 3 - 2', 'result': 7},
      {'equation': '7 + 4 - 6 + 8', 'result': 13},
      {'equation': '20 - 13 + 8 - 5', 'result': 10},
      {'equation': '9 + 8 - 7 + 6', 'result': 16},
      {'equation': '16 - 8 + 5 - 4', 'result': 9},
      {'equation': '6 + 7 - 4 + 9', 'result': 18},
      {'equation': '18 - 11 + 6 - 3', 'result': 10},
      {'equation': '11 + 5 - 8 + 7', 'result': 15},
      {'equation': '14 - 6 + 9 - 5', 'result': 12},
      {'equation': '13 + 9 - 12 + 6', 'result': 16},
      {'equation': '25 - 17 + 11 - 8', 'result': 11},
      {'equation': '8 + 12 - 9 + 4', 'result': 15},
      {'equation': '19 - 12 + 7 - 6', 'result': 8},
      {'equation': '15 + 7 - 13 + 9', 'result': 18},
      {'equation': '23 - 15 + 10 - 7', 'result': 11},
      {'equation': '17 + 6 - 11 + 5', 'result': 17},
      {'equation': '21 - 14 + 8 - 3', 'result': 12},
    ],
    
    // Multiplicación y división - Simples (1 operación)
    'multiplyDivide_1': [
      {'equation': '6 × 4', 'result': 24},
      {'equation': '35 ÷ 7', 'result': 5},
      {'equation': '8 × 3', 'result': 24},
      {'equation': '48 ÷ 6', 'result': 8},
      {'equation': '7 × 5', 'result': 35},
      {'equation': '42 ÷ 7', 'result': 6},
      {'equation': '9 × 4', 'result': 36},
      {'equation': '56 ÷ 8', 'result': 7},
      {'equation': '6 × 7', 'result': 42},
      {'equation': '63 ÷ 9', 'result': 7},
      {'equation': '8 × 6', 'result': 48},
      {'equation': '54 ÷ 6', 'result': 9},
      {'equation': '9 × 7', 'result': 63},
      {'equation': '72 ÷ 8', 'result': 9},
      {'equation': '5 × 8', 'result': 40},
      {'equation': '45 ÷ 5', 'result': 9},
      {'equation': '7 × 8', 'result': 56},
      {'equation': '64 ÷ 8', 'result': 8},
      {'equation': '6 × 9', 'result': 54},
      {'equation': '81 ÷ 9', 'result': 9},
    ],
    
    // Multiplicación y división - Intermedias (2 operaciones)
    'multiplyDivide_2': [
      {'equation': '6 × 4 ÷ 3', 'result': 8},
      {'equation': '35 ÷ 7 × 4', 'result': 20},
      {'equation': '8 × 3 ÷ 6', 'result': 4},
      {'equation': '48 ÷ 6 × 3', 'result': 24},
      {'equation': '7 × 5 ÷ 7', 'result': 5},
      {'equation': '42 ÷ 7 × 5', 'result': 30},
      {'equation': '9 × 4 ÷ 6', 'result': 6},
      {'equation': '56 ÷ 8 × 4', 'result': 28},
      {'equation': '6 × 7 ÷ 7', 'result': 6},
      {'equation': '63 ÷ 9 × 3', 'result': 21},
      {'equation': '8 × 6 ÷ 8', 'result': 6},
      {'equation': '54 ÷ 6 × 2', 'result': 18},
      {'equation': '9 × 7 ÷ 9', 'result': 7},
      {'equation': '72 ÷ 8 × 2', 'result': 18},
      {'equation': '5 × 8 ÷ 5', 'result': 8},
      {'equation': '45 ÷ 5 × 3', 'result': 27},
      {'equation': '7 × 8 ÷ 7', 'result': 8},
      {'equation': '64 ÷ 8 × 3', 'result': 24},
      {'equation': '6 × 9 ÷ 6', 'result': 9},
      {'equation': '81 ÷ 9 × 2', 'result': 18},
    ],
    
    // Multiplicación y división - Complejas (3 operaciones)
    'multiplyDivide_3': [
      {'equation': '6 × 4 ÷ 3 × 2', 'result': 16},
      {'equation': '35 ÷ 7 × 4 ÷ 2', 'result': 10},
      {'equation': '8 × 3 ÷ 6 × 5', 'result': 20},
      {'equation': '48 ÷ 6 × 3 ÷ 4', 'result': 6},
      {'equation': '7 × 5 ÷ 7 × 3', 'result': 15},
      {'equation': '42 ÷ 7 × 5 ÷ 6', 'result': 5},
      {'equation': '9 × 4 ÷ 6 × 3', 'result': 18},
      {'equation': '56 ÷ 8 × 4 ÷ 7', 'result': 4},
      {'equation': '6 × 7 ÷ 7 × 4', 'result': 24},
      {'equation': '63 ÷ 9 × 3 ÷ 3', 'result': 7},
      {'equation': '8 × 6 ÷ 8 × 5', 'result': 30},
      {'equation': '54 ÷ 6 × 2 ÷ 3', 'result': 6},
      {'equation': '9 × 7 ÷ 9 × 2', 'result': 14},
      {'equation': '72 ÷ 8 × 2 ÷ 6', 'result': 3},
      {'equation': '5 × 8 ÷ 5 × 3', 'result': 24},
      {'equation': '45 ÷ 5 × 3 ÷ 9', 'result': 3},
      {'equation': '7 × 8 ÷ 7 × 2', 'result': 16},
      {'equation': '64 ÷ 8 × 3 ÷ 4', 'result': 6},
      {'equation': '6 × 9 ÷ 6 × 3', 'result': 27},
      {'equation': '81 ÷ 9 × 2 ÷ 3', 'result': 6},
    ],
    
    // Todas las operaciones - Simples (1 operación)
    'addSubtractMultiplyDivide_1': [
      {'equation': '5 + 3', 'result': 8},
      {'equation': '12 - 7', 'result': 5},
      {'equation': '6 × 4', 'result': 24},
      {'equation': '35 ÷ 7', 'result': 5},
      {'equation': '8 + 6', 'result': 14},
      {'equation': '15 - 9', 'result': 6},
      {'equation': '8 × 3', 'result': 24},
      {'equation': '48 ÷ 6', 'result': 8},
      {'equation': '7 + 4', 'result': 11},
      {'equation': '20 - 13', 'result': 7},
      {'equation': '7 × 5', 'result': 35},
      {'equation': '42 ÷ 7', 'result': 6},
      {'equation': '9 + 8', 'result': 17},
      {'equation': '16 - 8', 'result': 8},
      {'equation': '9 × 4', 'result': 36},
      {'equation': '56 ÷ 8', 'result': 7},
      {'equation': '6 + 7', 'result': 13},
      {'equation': '18 - 11', 'result': 7},
      {'equation': '6 × 7', 'result': 42},
      {'equation': '63 ÷ 9', 'result': 7},
    ],
    
    // Todas las operaciones - Intermedias (2 operaciones)
    'addSubtractMultiplyDivide_2': [
      {'equation': '5 + 3 × 2', 'result': 11},
      {'equation': '12 - 6 ÷ 2', 'result': 9},
      {'equation': '8 × 3 - 4', 'result': 20},
      {'equation': '15 + 9 ÷ 3', 'result': 18},
      {'equation': '7 × 4 - 8', 'result': 20},
      {'equation': '20 - 8 ÷ 2', 'result': 16},
      {'equation': '9 + 6 × 2', 'result': 21},
      {'equation': '16 ÷ 4 + 6', 'result': 10},
      {'equation': '6 × 5 - 10', 'result': 20},
      {'equation': '18 + 12 ÷ 3', 'result': 22},
      {'equation': '11 - 3 × 2', 'result': 5},
      {'equation': '14 ÷ 2 + 9', 'result': 16},
      {'equation': '13 × 2 - 6', 'result': 20},
      {'equation': '25 - 15 ÷ 3', 'result': 20},
      {'equation': '8 + 4 × 3', 'result': 20},
      {'equation': '19 - 6 ÷ 2', 'result': 16},
      {'equation': '15 ÷ 3 + 7', 'result': 12},
      {'equation': '23 - 5 × 2', 'result': 13},
      {'equation': '17 + 8 ÷ 4', 'result': 19},
      {'equation': '21 ÷ 3 - 2', 'result': 5},
    ],
    
    // Todas las operaciones - Complejas (3 operaciones)
    'addSubtractMultiplyDivide_3': [
      {'equation': '5 + 3 × 2 - 4', 'result': 7},
      {'equation': '12 - 6 ÷ 2 + 5', 'result': 14},
      {'equation': '8 × 3 - 4 ÷ 2', 'result': 22},
      {'equation': '15 + 9 ÷ 3 - 6', 'result': 12},
      {'equation': '7 × 4 - 8 + 3', 'result': 23},
      {'equation': '20 - 8 ÷ 2 × 3', 'result': 8},
      {'equation': '9 + 6 × 2 - 7', 'result': 14},
      {'equation': '16 ÷ 4 + 6 × 2', 'result': 16},
      {'equation': '6 × 5 - 10 ÷ 2', 'result': 25},
      {'equation': '18 + 12 ÷ 3 - 8', 'result': 14},
      {'equation': '11 - 3 × 2 + 7', 'result': 12},
      {'equation': '14 ÷ 2 + 9 - 5', 'result': 11},
      {'equation': '13 × 2 - 6 ÷ 3', 'result': 24},
      {'equation': '25 - 15 ÷ 3 + 4', 'result': 24},
      {'equation': '8 + 4 × 3 - 6', 'result': 14},
      {'equation': '19 - 6 ÷ 2 × 2', 'result': 13},
      {'equation': '15 ÷ 3 + 7 - 4', 'result': 8},
      {'equation': '23 - 5 × 2 + 8', 'result': 21},
      {'equation': '17 + 8 ÷ 4 × 3', 'result': 23},
      {'equation': '21 ÷ 3 - 2 + 5', 'result': 10},
    ],
  };

  static List<SimpleEquation> getEquations(EquationOperationType operationType, int subEquations, int count) {
    String key = _getKey(operationType, subEquations);
    List<Map<String, dynamic>> equationData = _equations[key] ?? [];
    
    if (equationData.isEmpty) {
      // Fallback a generación automática si no hay ecuaciones predefinidas
      return _generateFallbackEquations(operationType, subEquations, count);
    }
    
    // Mezclar y tomar las ecuaciones necesarias
    List<Map<String, dynamic>> shuffled = List.from(equationData);
    shuffled.shuffle();
    
    List<SimpleEquation> result = [];
    for (int i = 0; i < count && i < shuffled.length; i++) {
      result.add(SimpleEquation(
        equation: shuffled[i]['equation'],
        result: shuffled[i]['result'],
      ));
    }
    
    // Si necesitamos más ecuaciones de las disponibles, repetir con mezcla
    while (result.length < count) {
      shuffled.shuffle();
      for (int i = 0; i < shuffled.length && result.length < count; i++) {
        result.add(SimpleEquation(
          equation: shuffled[i]['equation'],
          result: shuffled[i]['result'],
        ));
      }
    }
    
    return result;
  }
  
  static String _getKey(EquationOperationType operationType, int subEquations) {
    String opType;
    switch (operationType) {
      case EquationOperationType.addSubtract:
        opType = 'addSubtract';
        break;
      case EquationOperationType.multiplyDivide:
        opType = 'multiplyDivide';
        break;
      case EquationOperationType.addSubtractMultiplyDivide:
        opType = 'addSubtractMultiplyDivide';
        break;
    }
    return '${opType}_$subEquations';
  }
  
  static List<SimpleEquation> _generateFallbackEquations(EquationOperationType operationType, int subEquations, int count) {
    // Método de respaldo para generar ecuaciones si no hay predefinidas
    final random = Random();
    List<SimpleEquation> equations = [];
    
    for (int i = 0; i < count; i++) {
      if (subEquations == 1) {
        equations.add(_generateSimpleEquation(random, operationType));
      } else {
        equations.add(_generateComplexEquation(random, operationType, subEquations));
      }
    }
    
    return equations;
  }
  
  static SimpleEquation _generateSimpleEquation(Random random, EquationOperationType operationType) {
    List<String> operations = _getOperationsForType(operationType);
    String operation = operations[random.nextInt(operations.length)];
    
    int a, b, result;
    
    switch (operation) {
      case '+':
        a = random.nextInt(50) + 1;
        b = random.nextInt(50) + 1;
        result = a + b;
        break;
      case '-':
        a = random.nextInt(50) + 20;
        b = random.nextInt(a - 1) + 1;
        result = a - b;
        break;
      case '×':
        a = random.nextInt(10) + 2;
        b = random.nextInt(10) + 2;
        result = a * b;
        break;
      case '÷':
        result = random.nextInt(15) + 2;
        b = random.nextInt(8) + 2;
        a = result * b;
        break;
      default:
        a = 1;
        b = 1;
        result = 2;
    }
    
    return SimpleEquation(
      equation: '$a $operation $b',
      result: result,
    );
  }
  
  static SimpleEquation _generateComplexEquation(Random random, EquationOperationType operationType, int subEquations) {
    List<String> operations = _getOperationsForType(operationType);
    
    List<int> numbers = [];
    List<String> ops = [];
    
    // Generar números y operaciones
    numbers.add(random.nextInt(20) + 1);
    for (int i = 0; i < subEquations; i++) {
      ops.add(operations[random.nextInt(operations.length)]);
      numbers.add(random.nextInt(15) + 1);
    }
    
    // Construir ecuación y calcular resultado
    String equation = numbers[0].toString();
    int result = numbers[0];
    
    for (int i = 0; i < ops.length; i++) {
      equation += ' ${ops[i]} ${numbers[i + 1]}';
      
      switch (ops[i]) {
        case '+':
          result += numbers[i + 1];
          break;
        case '-':
          result -= numbers[i + 1];
          break;
        case '×':
          result *= numbers[i + 1];
          break;
        case '÷':
          if (numbers[i + 1] != 0) {
            result = (result / numbers[i + 1]).round();
          }
          break;
      }
    }
    
    return SimpleEquation(
      equation: equation,
      result: result,
    );
  }
  
  static List<String> _getOperationsForType(EquationOperationType operationType) {
    switch (operationType) {
      case EquationOperationType.addSubtract:
        return ['+', '-'];
      case EquationOperationType.multiplyDivide:
        return ['×', '÷'];
      case EquationOperationType.addSubtractMultiplyDivide:
        return ['+', '-', '×', '÷'];
    }
  }
}