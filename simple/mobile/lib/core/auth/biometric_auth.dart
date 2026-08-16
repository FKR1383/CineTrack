import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
        localizedReason: 'برای ورود به Cine Track Simple هویت خود را تأیید کنید.',
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
  static const _enabledKey = 'biometric_login_enabled';
  static const _userKey = 'biometric_login_user';

  Future<bool> isEnabledFor(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) == true && prefs.getString(_userKey) == userId;
  }

  Future<void> setEnabledFor(String userId, bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    if (enabled) {
      await prefs.setString(_userKey, userId);
    } else {
      await prefs.remove(_userKey);
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_enabledKey);
    await prefs.remove(_userKey);
  }
}
