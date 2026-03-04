import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/auth_service.dart';
import '../../services/user_service.dart';

class MFAScreen extends StatefulWidget {
  final AuthService auth;
  final UserService userService;

  const MFAScreen({super.key, required this.auth, required this.userService});

  @override
  State<MFAScreen> createState() => _MFAScreenState();
}

class _MFAScreenState extends State<MFAScreen> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;
  bool _passkeyLoading = false;
  String? _error;

  bool get _hasTotp => widget.auth.mfaMethods.contains('totp');
  bool get _hasPasskey => widget.auth.mfaMethods.contains('passkey');

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_loading) return;
    final code = _codeCtrl.text.trim();
    if (code.length != 6 && code.length != 11) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await widget.auth.verifyMFA(code);
      // Load user data before the router navigates to /home.
      await Future.wait([
        widget.userService.loadProfile(),
        widget.userService.loadPreferences(),
      ]);
    } on AuthException {
      setState(() => _error = 'Invalid code. Please try again.');
      _codeCtrl.clear();
    } catch (_) {
      setState(() => _error = 'Could not reach the server. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyWithPasskey() async {
    if (_passkeyLoading) return;

    setState(() {
      _passkeyLoading = true;
      _error = null;
    });

    try {
      await widget.auth.verifyMFAWithPasskey();
      await Future.wait([
        widget.userService.loadProfile(),
        widget.userService.loadPreferences(),
      ]);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Passkey verification failed. Try again.');
    } finally {
      if (mounted) setState(() => _passkeyLoading = false);
    }
  }

  void _cancel() {
    widget.auth.cancelMFA();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Two-factor authentication',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _hasTotp && _hasPasskey
                      ? 'Enter your authenticator code, recovery code, or use a passkey.'
                      : _hasPasskey
                          ? 'Use your passkey to sign in.'
                          : 'Enter the 6-digit code from your authenticator app, or an 11-character recovery code.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Passkey button — shown when passkeys are available.
                if (_hasPasskey) ...[
                  FilledButton.icon(
                    onPressed: _passkeyLoading ? null : _verifyWithPasskey,
                    icon: const Icon(Icons.key),
                    label: _passkeyLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Sign in with passkey'),
                  ),
                  if (_hasTotp) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text('or',
                              style: Theme.of(context).textTheme.bodySmall),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ],
                // TOTP section — shown when TOTP is available.
                if (_hasTotp) ...[
                  TextField(
                    controller: _codeCtrl,
                    autofocus: !_hasPasskey,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          letterSpacing: 8,
                        ),
                    keyboardType: TextInputType.visiblePassword,
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(11),
                    ],
                    decoration: const InputDecoration(
                      hintText: '000000 or ABCDE-12345',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      if (value.length == 6 && !value.contains('-')) {
                        _verify();
                      } else if (value.length == 11) {
                        _verify();
                      }
                    },
                    onSubmitted: (_) => _verify(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _loading ? null : _verify,
                    child: _loading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Verify'),
                  ),
                ],
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _cancel,
                  child: const Text('Back to sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
