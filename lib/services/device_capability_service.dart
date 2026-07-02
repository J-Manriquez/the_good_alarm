import 'dart:io';

class DeviceCapabilityService {
  DeviceCapabilityService._();
  static final DeviceCapabilityService instance = DeviceCapabilityService._();

  Future<bool> supportsLocalAi() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await Process.run('getprop', ['ro.product.cpu.abi']);
      final abi = result.stdout.toString().trim().toLowerCase();
      return abi.contains('arm64') || abi.contains('x86_64');
    } catch (_) {
      return false;
    }
  }
}
