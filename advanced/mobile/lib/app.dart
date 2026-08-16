import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/biometric_unlock_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/reset_password_screen.dart';
import 'features/shared/main_shell.dart';

class CineTrackApp extends ConsumerStatefulWidget {
  const CineTrackApp({required this.appLinks, super.key});

  final AppLinks appLinks;

  @override
  ConsumerState<CineTrackApp> createState() => _CineTrackAppState();
}

class _CineTrackAppState extends ConsumerState<CineTrackApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  StreamSubscription<Uri>? _deepLinkSubscription;
  String? _lastHandledDeepLink;

  @override
  void initState() {
    super.initState();
    _startDeepLinkHandling();
  }

  void _startDeepLinkHandling() {
    try {
      _deepLinkSubscription = widget.appLinks.uriLinkStream.listen(
        _handleDeepLink,
        onError: (_) {
          // A malformed or unsupported platform link must not stop the app.
        },
      );
    } on MissingPluginException {
      // Widget tests and unsupported platforms do not install Android plugins.
    } on PlatformException {
      // Platform startup errors must not prevent normal authentication flows.
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _readInitialDeepLink());
  }

  @override
  void dispose() {
    _deepLinkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _readInitialDeepLink() async {
    try {
      _handleDeepLink(await widget.appLinks.getInitialLink());
    } on MissingPluginException {
      // Desktop/widget-test builds do not install the Android plugin.
    } on PlatformException {
      // A malformed platform intent must never prevent app startup.
    }
  }

  void _handleDeepLink(Uri? uri) {
    if (uri == null || uri.scheme != 'timetv' || uri.host != 'reset-password') {
      return;
    }
    final token = uri.queryParameters['token']?.trim();
    if (token == null || token.length < 20) return;

    final canonical = 'timetv://reset-password?token=$token';
    if (_lastHandledDeepLink == canonical) return;
    _lastHandledDeepLink = canonical;

    void openResetScreen() {
      final navigator = _navigatorKey.currentState;
      if (navigator == null) return;
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => ResetPasswordScreen(initialToken: token),
          settings: const RouteSettings(name: '/reset-password'),
        ),
      );
    }

    if (_navigatorKey.currentState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => openResetScreen());
    } else {
      openResetScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'Cine Track',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      locale: const Locale('fa'),
      supportedLocales: const [Locale('fa'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends ConsumerWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return switch (auth.status) {
      AuthStatus.checking => const _SplashScreen(),
      AuthStatus.biometricLocked => const BiometricUnlockScreen(),
      AuthStatus.authenticated => const MainShell(),
      AuthStatus.unauthenticated || AuthStatus.loading => const LoginScreen(),
    };
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/brand_logo.png', width: 120, height: 120),
            const SizedBox(height: 20),
            const Text('Cine Track', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text('مدل پیشرفته • سرور اختصاصی • TMDB', textAlign: TextAlign.center),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
