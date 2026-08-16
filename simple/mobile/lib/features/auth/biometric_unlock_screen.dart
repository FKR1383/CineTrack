import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';

class BiometricUnlockScreen extends ConsumerWidget {
  const BiometricUnlockScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final loading = auth.status == AuthStatus.loading;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(26),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset('assets/images/brand_logo.png', width: 112, height: 112),
                      const SizedBox(height: 18),
                      const Text('Cine Track Simple', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),
                      const Text(
                        'نشست ۳۰ روزه شما هنوز معتبر است. برای ورود، هویت بیومتریک خود را تأیید کنید.',
                        textAlign: TextAlign.center,
                      ),
                      if (auth.error != null) ...[
                        const SizedBox(height: 12),
                        Text(auth.error!, style: TextStyle(color: Theme.of(context).colorScheme.error), textAlign: TextAlign.center),
                      ],
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: loading ? null : () => ref.read(authControllerProvider.notifier).unlockWithBiometrics(),
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('ورود با بیومتریک'),
                      ),
                      const SizedBox(height: 10),
                      TextButton(
                        onPressed: loading ? null : () => ref.read(authControllerProvider.notifier).usePasswordInstead(),
                        child: const Text('ورود با ایمیل و رمز عبور'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
