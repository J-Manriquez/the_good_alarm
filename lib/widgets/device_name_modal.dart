import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/sistema_firebase_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DeviceNameModal extends StatefulWidget {
  final VoidCallback? onDeviceNameSet;
  final bool canDismiss;

  const DeviceNameModal({
    Key? key,
    this.onDeviceNameSet,
    this.canDismiss = false,
  }) : super(key: key);

  @override
  _DeviceNameModalState createState() => _DeviceNameModalState();
}

class _DeviceNameModalState extends State<DeviceNameModal> {
  final TextEditingController _deviceNameController = TextEditingController();
  final SistemaFirebaseService _sistemaService = SistemaFirebaseService();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _deviceNameController.dispose();
    super.dispose();
  }

  Future<void> _saveDeviceName() async {
    final deviceName = _deviceNameController.text.trim();
    
    if (deviceName.isEmpty) {
      setState(() {
        _errorMessage = 'El nombre del dispositivo es obligatorio';
      });
      return;
    }

    if (deviceName.length < 3) {
      setState(() {
        _errorMessage = 'El nombre debe tener al menos 3 caracteres';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Guardar en SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('device_name', deviceName);

      // Guardar en Firebase si el usuario está autenticado
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await _sistemaService.addDevice(user.uid, deviceName, true);
      }

      // Llamar callback si existe
      if (widget.onDeviceNameSet != null) {
        widget.onDeviceNameSet!();
      }

      // Cerrar modal
      if (mounted) {
        Navigator.of(context).pop(deviceName);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al guardar el nombre del dispositivo: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => widget.canDismiss,
      child: AlertDialog(
        title: const Text(
          'Nombre del Dispositivo',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Para sincronizar tus alarmas, necesitamos identificar este dispositivo. Ingresa un nombre único para este dispositivo.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _deviceNameController,
              decoration: InputDecoration(
                labelText: 'Nombre del dispositivo',
                hintText: 'Ej: Mi Teléfono, Tablet Casa, etc.',
                border: const OutlineInputBorder(),
                errorText: _errorMessage,
              ),
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
              enabled: !_isLoading,
              onSubmitted: (_) => _saveDeviceName(),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
        actions: [
          if (widget.canDismiss)
            TextButton(
              onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ElevatedButton(
            onPressed: _isLoading ? null : _saveDeviceName,
            child: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Guardar'),
          ),
        ],
      ),
    );
  }
}

// Función de utilidad para mostrar el modal
Future<String?> showDeviceNameModal(
  BuildContext context, {
  VoidCallback? onDeviceNameSet,
  bool canDismiss = false,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: canDismiss,
    builder: (context) => DeviceNameModal(
      onDeviceNameSet: onDeviceNameSet,
      canDismiss: canDismiss,
    ),
  );
}

// Función para verificar si se necesita mostrar el modal
Future<bool> shouldShowDeviceNameModal() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final deviceName = prefs.getString('device_name');
    return deviceName == null || deviceName.isEmpty;
  } catch (e) {
    return true; // Si hay error, mostrar el modal por seguridad
  }
}

// Función para obtener el nombre del dispositivo guardado
Future<String?> getStoredDeviceName() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('device_name');
  } catch (e) {
    return null;
  }
}