import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/tmdb_client.dart';
import '../../core/auth/biometric_auth.dart';
import '../../core/errors/api_exception.dart';
import '../../core/storage/local_database.dart';
import '../../core/storage/session_store.dart';
import '../shared/models.dart';
import '../shared/repository.dart';

enum AuthStatus { checking, biometricLocked, authenticated, unauthenticated, loading }

class AuthState {
  const AuthState({required this.status, this.user, this.error, this.biometricEnabled = false});
  final AuthStatus status;
  final UserModel? user;
  final String? error;
  final bool biometricEnabled;

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    String? error,
    bool clearError = false,
    bool? biometricEnabled,
  }) => AuthState(
        status: status ?? this.status,
        user: user ?? this.user,
        error: clearError ? null : (error ?? this.error),
        biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      );
}

final localDatabaseProvider = Provider<LocalDatabase>((ref) => LocalDatabase.instance);
final tmdbClientProvider = Provider<TmdbClient>((ref) => TmdbClient(ref.read(localDatabaseProvider)));
final repositoryProvider = Provider<CineTrackRepository>((ref) => CineTrackRepository(ref.read(localDatabaseProvider), ref.read(tmdbClientProvider)));
final sessionStoreProvider = Provider<SessionStore>((ref) => SessionStore());
final biometricAuthProvider = Provider<BiometricAuthService>((ref) => BiometricAuthService());
final biometricPreferenceProvider = Provider<BiometricPreferenceStore>((ref) => BiometricPreferenceStore());

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    ref.read(repositoryProvider),
    ref.read(sessionStoreProvider),
    ref.read(biometricAuthProvider),
    ref.read(biometricPreferenceProvider),
  )..bootstrap();
});

class AuthController extends StateNotifier<AuthState> {
  AuthController(this.repository, this.sessionStore, this.biometricAuth, this.biometricPreferences)
      : super(const AuthState(status: AuthStatus.checking));

  final CineTrackRepository repository;
  final SessionStore sessionStore;
  final BiometricAuthService biometricAuth;
  final BiometricPreferenceStore biometricPreferences;

  Future<void> bootstrap() async {
    final session = await sessionStore.read();
    if (session == null) {
      repository.setCurrentUser(null);
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }
    repository.setCurrentUser(session.userId);
    final biometricEnabled = await biometricPreferences.isEnabledFor(session.userId);
    if (biometricEnabled) {
      final unlocked = await biometricAuth.authenticate();
      if (!unlocked) {
        state = const AuthState(status: AuthStatus.biometricLocked, biometricEnabled: true);
        return;
      }
    }
    await _restoreProfile(session.userId, biometricEnabled: biometricEnabled);
  }

  Future<void> _restoreProfile(String userId, {required bool biometricEnabled}) async {
    try {
      repository.setCurrentUser(userId);
      final user = await repository.profile(userId);
      state = AuthState(status: AuthStatus.authenticated, user: user, biometricEnabled: biometricEnabled);
    } catch (_) {
      repository.setCurrentUser(null);
      await sessionStore.clear();
      await biometricPreferences.clear();
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<bool> login({required String email, required String password, required bool enableBiometric}) async {
    state = state.copyWith(status: AuthStatus.loading, clearError: true);
    try {
      if (enableBiometric && !await biometricAuth.isAvailable()) {
        throw const ApiException(message: 'بیومتریک روی این دستگاه فعال یا ثبت نشده است.');
      }
      final user = await repository.login(email: email, password: password, rememberMe: true);
      await sessionStore.write(userId: user.id, expiresAt: DateTime.now().add(const Duration(days: 30)));
      await biometricPreferences.setEnabledFor(user.id, enableBiometric);
      state = AuthState(status: AuthStatus.authenticated, user: user, biometricEnabled: enableBiometric);
      return true;
    } on ApiException catch (error) {
      repository.setCurrentUser(null);
      state = AuthState(status: AuthStatus.unauthenticated, error: error.message);
      return false;
    }
  }

  Future<bool> unlockWithBiometrics() async {
    final session = await sessionStore.read();
    if (session == null) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return false;
    }
    state = state.copyWith(status: AuthStatus.loading, clearError: true);
    if (!await biometricAuth.authenticate()) {
      state = const AuthState(status: AuthStatus.biometricLocked, biometricEnabled: true, error: 'احراز هویت بیومتریک انجام نشد.');
      return false;
    }
    await _restoreProfile(session.userId, biometricEnabled: true);
    return state.status == AuthStatus.authenticated;
  }

  Future<void> usePasswordInstead() async {
    await sessionStore.clear();
    await biometricPreferences.clear();
    repository.setCurrentUser(null);
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<bool> setBiometricEnabled(bool enabled) async {
    final user = state.user;
    if (user == null) return false;
    if (enabled) {
      if (!await biometricAuth.isAvailable()) return false;
      if (!await biometricAuth.authenticate()) return false;
    }
    await biometricPreferences.setEnabledFor(user.id, enabled);
    state = state.copyWith(biometricEnabled: enabled, clearError: true);
    return true;
  }

  Future<bool> register({
    required String firstName,
    required String lastName,
    required String username,
    required String email,
    required String password,
    String? bio,
    String? profileImagePath,
  }) async {
    state = state.copyWith(status: AuthStatus.loading, clearError: true);
    try {
      final user = await repository.register(
        firstName: firstName,
        lastName: lastName,
        username: username,
        email: email,
        password: password,
        bio: bio,
        profileImagePath: profileImagePath,
      );
      await sessionStore.write(userId: user.id, expiresAt: DateTime.now().add(const Duration(days: 30)));
      await biometricPreferences.clear();
      state = AuthState(status: AuthStatus.authenticated, user: user);
      return true;
    } on ApiException catch (error) {
      repository.setCurrentUser(null);
      state = AuthState(status: AuthStatus.unauthenticated, error: error.message);
      return false;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(status: AuthStatus.loading, clearError: true);
    await sessionStore.clear();
    await biometricPreferences.clear();
    await repository.logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  void setUser(UserModel user) => state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        biometricEnabled: state.biometricEnabled,
      );

  Future<void> completePasswordReset() async {
    await sessionStore.clear();
    await biometricPreferences.clear();
    repository.setCurrentUser(null);
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  void clearError() => state = state.copyWith(clearError: true);
}
