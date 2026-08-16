import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class BiometricAuthService {
  BiometricAuthService({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();
  final LocalAuthentication _auth;

  Future<bool> isAvailable() async {
    try {
      if (!await _auth.isDeviceSupported()) return false;
      return (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticate() async {
    try {
      if (!await isAvailable()) return false;
      return await _auth.authenticate(
        localizedReason: 'برای ورود به Cine Track هویت خود را تأیید کنید.',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }
}

class BiometricPreferenceStore {
  BiometricPreferenceStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );
  static const _key = 'biometric_login_enabled';
  final FlutterSecureStorage _storage;

  Future<bool> isEnabled() async => (await _storage.read(key: _key)) == 'true';
  Future<void> setEnabled(bool enabled) => _storage.write(key: _key, value: enabled ? 'true' : 'false');
  Future<void> clear() => _storage.delete(key: _key);
}
