---
skill: flutter-screen-implementation
version: 1.0.0
domain: flutter-ui
trigger_phrases:
  - "crea una pantalla nueva en Flutter"
  - "ajusta la UI de esta screen"
  - "implementa una vista en lib/screens"
applies_to:
  - "*.dart"
  - "nuevos archivos y archivos existentes en lib/screens y lib/widgets"
---

# Skill: Flutter Screen Implementation

## Propósito
Implementar o modificar pantallas Flutter manteniendo consistencia con navegación, estilos y estructura actual del proyecto.
Se usa para features de UI en alarmas, habitos, calendario y medicamentos.

## Comportamiento Esperado

### Siempre hacer
- Usar widgets Material y rutas existentes definidas en `lib/main.dart`.
- Mantener nombrado en snake_case para archivos y PascalCase para clases.
- Respetar el flujo entre pantalla, modelos en `lib/models/` y servicios en `lib/services/`.

### Nunca hacer
- No introducir paquetes UI nuevos sin aviso explicito.
- No mover logica de negocio compleja al widget cuando ya existe en servicios/repositorios.

## Proceso Paso a Paso
1. Revisar ruta/pantalla relacionada y dependencias en `lib/main.dart` y `lib/home_page.dart`.
2. Implementar cambios en la screen con estado local claro y validaciones basicas.
3. Conectar acciones con repositorio/servicio existente, evitando duplicar logica.
4. Ejecutar `dart analyze <archivo_modificado.dart>` y corregir errores.

## Plantilla de Salida
```dart
class ExampleScreen extends StatelessWidget {
  const ExampleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Titulo')),
      body: const Center(child: Text('Contenido')),
    );
  }
}
```

## Criterios de Éxito
- [ ] La pantalla compila y respeta las rutas existentes.
- [ ] No se rompe el flujo hacia servicios/modelos.
- [ ] `dart analyze` del archivo modificado no reporta errores.

## Referencias del Proyecto
- Archivos relacionados: `lib/main.dart`, `lib/screens/`, `lib/widgets/`
- Comandos relacionados: `flutter run`, `dart analyze`, `dart format lib`
- Convenciones aplicadas: Flutter lints, arquitectura por features, naming Dart
