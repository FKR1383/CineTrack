import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/auth/biometric_auth.dart';
import '../../core/auth/token_store.dart';
import '../../core/errors/api_exception.dart';
import '../shared/models.dart';
import '../shared/repository.dart';

enum AuthStatus { checking, biometricLocked, authenticated, unauthenticated, loading }

class AuthState {
  const AuthState({
    required this.status,
    this.user,
    this.error,
    this.biometricEnabled = false,
  });

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
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      error: clearError ? null : (error ?? this.error),
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
    );
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());
final biometricAuthProvider = Provider<BiometricAuthService>((ref) => BiometricAuthService());
final biometricPreferenceProvider = Provider<BiometricPreferenceStore>((ref) => BiometricPreferenceStore());
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.read(tokenStoreProvider)));
final repositoryProvider = Provider<CineTrackRepository>((ref) => CineTrackRepository(ref.read(apiClientProvider)));

final authControllerProvider = StateNotifierProvider<AuthController, AuthState>((ref) {
  return AuthController(
    ref.read(repositoryProvider),
    ref.read(tokenStoreProvider),
    ref.read(biometricAuthProvider),
    ref.read(biometricPreferenceProvider),
  )..bootstrap();
});

class AuthController extends StateNotifier<AuthState> {
  AuthController(this.repository, this.tokenStore, this.biometricAuth, this.biometricPreferences)
      : super(const AuthState(status: AuthStatus.checking));

  final CineTrackRepository repository;
  final TokenStore tokenStore;
  final BiometricAuthService biometricAuth;
  final BiometricPreferenceStore biometricPreferences;

  Future<void> bootstrap() async {
    final tokens = await tokenStore.read();
    if (tokens == null) {
      state = const AuthState(status: AuthStatus.unauthenticated);
      return;
    }
    final biometricEnabled = await biometricPreferences.isEnabled();
    if (biometricEnabled) {
      final unlocked = await biometricAuth.authenticate();
      if (!unlocked) {
        state = const AuthState(status: AuthStatus.biometricLocked, biometricEnabled: true);
        return;
      }
    }
    await _restoreProfile(biometricEnabled: biometricEnabled);
  }

  Future<void> _restoreProfile({required bool biometricEnabled}) async {
    try {
      final user = await repository.profile();
      state = AuthState(status: AuthStatus.authenticated, user: user, biometricEnabled: biometricEnabled);
    } catch (_) {
      await tokenStore.clear();
      await biometricPreferences.clear();
      state = const AuthState(status: AuthStatus.unauthenticated);
    }
  }

  Future<bool> login({
    required String email,
    required String password,
    required bool enableBiometric,
  }) async {
    state = state.copyWith(status: AuthStatus.loading, clearError: true);
    try {
      if (enableBiometric && !await biometricAuth.isAvailable()) {
        throw const ApiException(message: 'بیومتریک روی این دستگاه فعال یا ثبت نشده است.');
      }
      final result = await repository.login(
        email: email,
        password: password,
        rememberMe: true,
      );
      await tokenStore.write(accessToken: result.accessToken, refreshToken: result.refreshToken);
      await biometricPreferences.setEnabled(enableBiometric);
      state = AuthState(
        status: AuthStatus.authenticated,
        user: result.user,
        biometricEnabled: enableBiometric,
      );
      return true;
    } on ApiException catch (error) {
      state = AuthState(status: AuthStatus.unauthenticated, error: error.message);
      return false;
    }
  }

  Future<bool> unlockWithBiometrics() async {
    state = state.copyWith(status: AuthStatus.loading, clearError: true);
    if (!await biometricAuth.authenticate()) {
      state = const AuthState(
        status: AuthStatus.biometricLocked,
        biometricEnabled: true,
        error: 'احراز هویت بیومتریک انجام نشد.',
      );
      return false;
    }
    await _restoreProfile(biometricEnabled: true);
    return state.status == AuthStatus.authenticated;
  }

  Future<void> usePasswordInstead() async {
    await tokenStore.clear();
    await biometricPreferences.clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<bool> setBiometricEnabled(bool enabled) async {
    if (enabled) {
      if (!await biometricAuth.isAvailable()) return false;
      if (!await biometricAuth.authenticate()) return false;
    }
    await biometricPreferences.setEnabled(enabled);
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
      final result = await repository.register(
        firstName: firstName,
        lastName: lastName,
        username: username,
        email: email,
        password: password,
        bio: bio,
        profileImagePath: profileImagePath,
      );
      await tokenStore.write(accessToken: result.accessToken, refreshToken: result.refreshToken);
      await biometricPreferences.clear();
      state = AuthState(status: AuthStatus.authenticated, user: result.user);
      return true;
    } on ApiException catch (error) {
      state = AuthState(status: AuthStatus.unauthenticated, error: error.message);
      return false;
    }
  }

  Future<void> logout() async {
    state = state.copyWith(status: AuthStatus.loading, clearError: true);
    final refresh = await tokenStore.readRefreshToken();
    try {
      if (refresh != null) await repository.logout(refresh);
    } catch (_) {
      // Local logout must still succeed when the network is unavailable.
    }
    await tokenStore.clear();
    await biometricPreferences.clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  void setUser(UserModel user) {
    state = AuthState(
      status: AuthStatus.authenticated,
      user: user,
      biometricEnabled: state.biometricEnabled,
    );
  }

  Future<void> completePasswordReset() async {
    await tokenStore.clear();
    await biometricPreferences.clear();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  void clearError() => state = state.copyWith(clearError: true);
}
