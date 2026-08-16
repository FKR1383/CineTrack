import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/api_exception.dart';
import '../../core/widgets/common_widgets.dart';
import 'auth_controller.dart';
import 'reset_password_screen.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_email.text.contains('@')) {
      showMessage(context, 'ایمیل معتبر وارد کنید.', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final debugToken = await ref.read(repositoryProvider).forgotPassword(_email.text);
      if (!mounted) return;
      if (debugToken == null) {
        showMessage(context, 'حسابی با این ایمیل روی این دستگاه ثبت نشده است.', error: true);
        return;
      }
      showMessage(context, 'توکن بازیابی محلی ۱۵ دقیقه‌ای ساخته شد.');
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ResetPasswordScreen(initialToken: debugToken)),
      );
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('بازیابی رمز عبور')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.mark_email_read_outlined, size: 72),
                const SizedBox(height: 20),
                const Text(
                  'در مدل ساده حساب‌ها روی همین دستگاه ذخیره می‌شوند. ایمیل حساب را وارد کنید تا توکن بازیابی محلی ساخته شود.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'ایمیل'),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading ? const CircularProgressIndicator() : const Text('ساخت توکن بازیابی'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
