# The Good Alarm — Notas para Claude

## Compilación Android

Para generar las 3 versiones de APK (una por arquitectura), usar siempre:

```
flutter build apk --split-per-abi
```

Esto genera en `build/app/outputs/flutter-apk/`:
- `app-arm64-v8a-release.apk` — dispositivos ARM64 (mayoría de Android modernos)
- `app-armeabi-v7a-release.apk` — dispositivos ARM32 (Android antiguos)
- `app-x86_64-release.apk` — emuladores y dispositivos x86

Los APKs se copian a la carpeta `releases/` en la raíz del proyecto.
