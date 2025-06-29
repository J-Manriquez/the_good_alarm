# The Good Alarm

Una aplicación de alarmas inteligente desarrollada en Flutter con sincronización en la nube mediante Firebase.

## Características Principales

### 🔔 Gestión de Alarmas
- Crear, editar y eliminar alarmas
- Alarmas repetitivas (diarias, semanales, fines de semana, días específicos)
- Sistema de posposición (snooze) configurable
- Juegos interactivos para desactivar alarmas
- Agrupación de alarmas por horarios

### ☁️ Sincronización en la Nube
- **Sincronización automática**: Las alarmas se sincronizan automáticamente con Firebase cuando `syncToCloud` está habilitado
- **Sincronización en tiempo real**: Los cambios se reflejan instantáneamente en todos los dispositivos conectados
- **Autenticación de usuarios**: Sistema de login/registro para identificar usuarios únicos
- **Almacenamiento seguro**: Las alarmas se almacenan en Firestore bajo `users/{userId}/alarms`

### 🎮 Juegos Interactivos
- Juego de ecuaciones matemáticas
- Juego de memoria (Memorice)
- Juego de secuencias
- Configuración personalizable de dificultad

## Arquitectura de Sincronización

### Estructura de Datos en Firebase
```
users/
  {userId}/
    alarms/
      {alarmId}/
        - id: string
        - time: timestamp
        - title: string
        - message: string
        - isActive: boolean
        - repeatDays: array
        - snoozeCount: number
        - maxSnoozes: number
        - snoozeDurationMinutes: number
        - requireGame: boolean
        - gameConfig: object
        - syncToCloud: boolean
```

### Operaciones Sincronizadas

1. **Creación de Alarmas** (`_setAlarm`)
   - Se guarda localmente
   - Si `syncToCloud: true`, se envía a Firebase

2. **Edición de Alarmas** (`_editAlarm`)
   - Se actualiza localmente
   - Si `syncToCloud: true`, se actualiza en Firebase

3. **Activación/Desactivación** (`_toggleAlarmState`)
   - Se cambia el estado localmente
   - Si `syncToCloud: true`, se sincroniza el estado con Firebase

4. **Eliminación de Alarmas** (`_deleteAlarm`)
   - Se elimina localmente
   - Si estaba sincronizada, se elimina de Firebase

5. **Posposición (Snooze)** (`_handleAlarmSnoozed`)
   - Se actualiza el contador de snooze localmente
   - Si `syncToCloud: true`, se sincroniza con Firebase

6. **Detención de Alarmas** (`_handleAlarmStopped`)
   - Se resetea el contador de snooze
   - Si `syncToCloud: true`, se sincroniza con Firebase

### Sincronización en Tiempo Real

La aplicación utiliza `StreamSubscription` para escuchar cambios en Firebase:

```dart
_firebaseAlarmsSubscription = _alarmFirebaseService
    .getAlarmsStream(_currentUser!.uid)
    .listen(_handleFirebaseAlarmsUpdate);
```

Cuando se detectan cambios:
- Se comparan las alarmas locales con las de Firebase
- Se agregan nuevas alarmas
- Se actualizan alarmas existentes
- Se eliminan alarmas que ya no existen en Firebase

### Configuración de Sincronización

Los usuarios pueden:
- Habilitar/deshabilitar la sincronización en la nube desde Configuración
- Elegir qué alarmas sincronizar (campo `syncToCloud` por alarma)
- Iniciar sesión/registrarse para acceder a la sincronización

## Instalación y Configuración

### Prerrequisitos
- Flutter SDK
- Cuenta de Firebase
- Android Studio / VS Code

### Configuración de Firebase

1. Crear un proyecto en [Firebase Console](https://console.firebase.google.com/)
2. Habilitar Authentication (Email/Password)
3. Habilitar Firestore Database
4. Descargar `google-services.json` y colocarlo en `android/app/`
5. Configurar las reglas de Firestore:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId}/alarms/{alarmId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

### Instalación

```bash
# Clonar el repositorio
git clone <repository-url>
cd the_good_alarm

# Instalar dependencias
flutter pub get

# Ejecutar la aplicación
flutter run
```

## Uso

1. **Primera vez**: Registrarse o iniciar sesión
2. **Crear alarmas**: Usar el botón "+" en la pantalla principal
3. **Habilitar sincronización**: Ir a Configuración > Guardado en la Nube
4. **Sincronización automática**: Las alarmas con `syncToCloud: true` se sincronizan automáticamente

## Tecnologías Utilizadas

- **Flutter**: Framework de desarrollo
- **Firebase Auth**: Autenticación de usuarios
- **Firestore**: Base de datos en tiempo real
- **SharedPreferences**: Almacenamiento local
- **Platform Channels**: Comunicación con código nativo para alarmas

## Contribuir

1. Fork el proyecto
2. Crear una rama para tu feature (`git checkout -b feature/AmazingFeature`)
3. Commit tus cambios (`git commit -m 'Add some AmazingFeature'`)
4. Push a la rama (`git push origin feature/AmazingFeature`)
5. Abrir un Pull Request
