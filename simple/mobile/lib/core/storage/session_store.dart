import 'package:shared_preferences/shared_preferences.dart';

class LocalSession {
  const LocalSession({required this.userId, required this.expiresAt});
  final String userId;
  final DateTime expiresAt;
}

class SessionStore {
  static const _userKey = 'session_user_id';
  static const _expiryKey = 'session_expiry';

  Future<void> write({required String userId, required DateTime expiresAt}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userKey, userId);
    await prefs.setString(_expiryKey, expiresAt.toUtc().toIso8601String());
  }

  Future<LocalSession?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_userKey);
    final expiryRaw = prefs.getString(_expiryKey);
    if (userId == null || expiryRaw == null) return null;
    final expiry = DateTime.tryParse(expiryRaw)?.toLocal();
    if (expiry == null || expiry.isBefore(DateTime.now())) {
      await clear();
      return null;
    }
    return LocalSession(userId: userId, expiresAt: expiry);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userKey);
    await prefs.remove(_expiryKey);
  }
}
