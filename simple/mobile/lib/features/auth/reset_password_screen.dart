import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/api_exception.dart';
import '../../core/widgets/common_widgets.dart';
import 'auth_controller.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, this.initialToken});

  final String? initialToken;

  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _token = TextEditingController(text: widget.initialToken);
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _token.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      await ref.read(repositoryProvider).resetPassword(_token.text, _password.text);
      await ref.read(authControllerProvider.notifier).completePasswordReset();
      if (!mounted) return;
      showMessage(context, 'رمز عبور تغییر کرد. اکنون وارد شوید.');
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on ApiException catch (error) {
      if (mounted) showMessage(context, error.message, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? _passwordValidator(String? value) {
    final text = value ?? '';
    if (text.length < 8 ||
        !RegExp('[A-Z]').hasMatch(text) ||
        !RegExp('[a-z]').hasMatch(text) ||
        !RegExp('[0-9]').hasMatch(text)) {
      return 'حداقل ۸ کاراکتر شامل حرف بزرگ، حرف کوچک و عدد وارد کنید.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تعیین رمز جدید')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.password_rounded, size: 72),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _token,
                    textDirection: TextDirection.ltr,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'توکن بازیابی'),
                    validator: (value) => (value?.trim().length ?? 0) >= 20
                        ? null
                        : 'توکن بازیابی معتبر وارد کنید.',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    textDirection: TextDirection.ltr,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: InputDecoration(
                      labelText: 'رمز عبور جدید',
                      helperText: 'حداقل ۸ کاراکتر، شامل حرف بزرگ، حرف کوچک و عدد',
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      ),
                    ),
                    validator: _passwordValidator,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmPassword,
                    obscureText: _obscure,
                    textDirection: TextDirection.ltr,
                    autofillHints: const [AutofillHints.newPassword],
                    decoration: const InputDecoration(labelText: 'تکرار رمز عبور جدید'),
                    validator: (value) => value == _password.text
                        ? null
                        : 'تکرار رمز عبور با رمز جدید یکسان نیست.',
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _loading ? null : _submit,
                    icon: _loading
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_reset),
                    label: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('تغییر رمز عبور'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
