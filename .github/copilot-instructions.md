# Copilot Instructions — The Good Alarm

## Descripción del Proyecto
The Good Alarm es una app Flutter enfocada en alarmas inteligentes, habitos y recordatorios de medicamentos para Android.
Integra persistencia local (Hive y SharedPreferences), autenticacion y sincronizacion en la nube con Firebase Auth y Cloud Firestore.
Incluye flujos de alarma avanzados (snooze, control de volumen, juegos para apagar alarma) y canales nativos Android via MethodChannel.
Esta orientada a usuarios finales que necesitan alarmas robustas y sincronizacion entre dispositivos.

## Stack Tecnologico
- **Lenguaje principal**: Dart (SDK constraint `^3.8.0`)
- **Runtime / Plataforma**: Flutter (Android como plataforma principal activa)
- **Framework principal**: Flutter + Material
- **Frameworks secundarios / librerias clave**: firebase_core, firebase_auth, cloud_firestore, hive, hive_flutter, shared_preferences, flutter_tts, google_sign_in, googleapis, http, intl
- **Gestor de paquetes**: pub (`flutter pub`)
- **Base de datos**: Cloud Firestore + almacenamiento local en Hive/SharedPreferences
- **Infraestructura / Despliegue**: Firebase (Auth + Firestore) y configuracion Android Gradle

## Estructura del Proyecto
- `lib/`: codigo principal Dart (UI, modelos, servicios, pantallas y widgets)
  - `lib/services/`: repositorios y servicios de sincronizacion/local/cloud
  - `lib/models/`: modelos de dominio (alarmas, habitos, calendario, medicacion)
  - `lib/screens/`: pantallas especializadas (auth, medicamentos, etc.)
  - `lib/games/`: minijuegos usados para desactivar alarmas
  - `lib/widgets/`: componentes reutilizables de UI
- `android/`: implementacion nativa Android (AlarmManager, BroadcastReceivers, MethodChannels)
- `assets/`: recursos estaticos (iconos)
- `.github/`: instrucciones y documentos operativos del asistente
- `ios/`, `web/`, `linux/`, `macos/`, `windows/`: scaffolding multiplataforma de Flutter

## Comandos Clave
| Proposito        | Comando                     |
|-----------------|-----------------------------|
| Instalar deps   | `flutter pub get`           |
| Build           | `flutter build apk`         |
| Desarrollo      | `flutter run`               |
| Tests           | `flutter test`              |
| Lint            | `dart analyze`              |
| Format          | `dart format lib android`   |
| Deploy          | `N/A`                       |

## Convenciones de Codigo
- **Estilo**: indentacion de 2 espacios, estilo Dart/Flutter, trailing commas donde aplica
- **Naming**: clases en PascalCase, metodos/variables en camelCase, archivos mayormente en snake_case
- **Organizacion de imports**: imports de `dart:` primero, luego `package:`, luego relativos
- **Maximo de lineas por archivo**: [No detectado — completar manualmente]
- **Comentarios**: predominan comentarios tecnicos breves en espanol
- El linter base proviene de `package:flutter_lints/flutter.yaml`

## Patrones y Arquitectura
- **Patron principal**: arquitectura por features con separacion UI + services/repository + models
- **Manejo de errores**: control explicito con `try/catch` en integraciones async (cloud/local/native)
- **Estado global**: [No detectado — completar manualmente]
- **Autenticacion**: Firebase Auth (flujo login/registro y streams de sesion)
- Integracion Flutter-Android por MethodChannel para programacion y control de alarmas

## Testing
- **Framework**: `flutter_test`
- **Ubicacion de tests**: [No detectado — completar manualmente]
- **Convencion de nombres**: [No detectado — completar manualmente]
- **Cobertura minima requerida**: [No detectado — completar manualmente]
- **Mocks y fixtures**: [No detectado — completar manualmente]

## Variables de Entorno
- No se detecto `.env.example` en el repositorio.
- Configuracion Firebase principal en `lib/firebase_options.dart` y `android/app/google-services.json`.
- Variables/secretos runtime adicionales: [No detectado — completar manualmente]

## Lo que Copilot DEBE hacer en este proyecto
- Priorizar cambios en `lib/services/`, `lib/models/` y `lib/screens/` respetando el flujo actual local-cloud.
- Mantener compatibilidad con Android nativo cuando se toquen parametros de alarmas o MethodChannels.
- Preservar campos de sincronizacion (`syncToCloud`, `revision`, `fieldUpdatedAt`, `deletedAt`) al editar modelos/repositorios.
- Siempre usar los comandos definidos en la seccion "Comandos Clave".
- Respetar las convenciones de naming y estilo definidas.
- Al crear nuevos archivos, seguir la estructura de directorios establecida.

## Lo que Copilot NO debe hacer en este proyecto
- No reemplazar Firebase/Hive por otras librerias sin requerimiento explicito.
- No generar codigo que omita el manejo de errores.
- No crear archivos fuera de las carpetas establecidas sin confirmacion.
- No sugerir dependencias nuevas sin advertirlo explicitamente.
- No romper la compatibilidad de llaves y payloads usadas entre Flutter y Android nativo.

## Contexto Adicional
El proyecto contiene documentacion tecnica complementaria en archivos `.txt` (flujos, estructura Firebase, historial y planes).
Existen logs de depuracion en `console.txt` que muestran trazas operativas de alarmas, volumen y bridge nativo.
La app opera con enfoque Android para ejecucion de alarmas exactas, permisos especiales y receivers nativos.
Se observa coexistencia de rutas Kotlin en `com.example` y package real `com.andodevs.the_good_alarm`; tratar cambios nativos con cautela.
