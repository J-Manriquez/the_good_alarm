// Clases para ecuaciones
class SimpleEquation {
  final String equation;
  final int result;
  
  // Constructor principal para ecuaciones predefinidas
  SimpleEquation({
    required this.equation,
    required this.result,
  });
  
  // Constructor alternativo para compatibilidad con código existente
  SimpleEquation.fromOperands({
    required int operand1,
    required int operand2,
    required String operation,
    required this.result,
  }) : equation = '$operand1 $operation $operand2';
  
  @override
  String toString() {
    return equation;
  }
}

class ComplexEquation {
  final List<int> operands;
  final List<String> operations;
  final int result;
  
  ComplexEquation({
    required this.operands,
    required this.operations,
    required this.result,
  });
  
  @override
  String toString() {
    if (operands.isEmpty || operations.isEmpty) {
      return '0';
    }
    
    if (operands.length == 1) {
      return operands[0].toString();
    }
    
    String equation = operands[0].toString();
    for (int i = 0; i < operations.length && i + 1 < operands.length; i++) {
      equation += ' ${operations[i]} ${operands[i + 1]}';
    }
    return equation;
  }
}

// Clase para cartas de memoria
class MemoryCard {
  final int id;
  final int value;
  final String symbol;
  bool isFlipped;
  bool isMatched;

  MemoryCard({
    required this.id,
    required this.value,
    required this.symbol,
    this.isFlipped = false,
    this.isMatched = false,
  });
}