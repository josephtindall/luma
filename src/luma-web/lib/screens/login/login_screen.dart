import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/auth_service.dart';
import '../../services/user_service.dart';
import 'login_email_store.dart';

/// The login step the user is currently viewing.
enum _LoginStep {
  /// Enter email or pick a previously-used account.
  email,

  /// Passkey prompt (user has at least one passkey registered).
  passkey,

  /// Password only (no MFA configured).
  password,

  /// Password + TOTP code (user has TOTP but no passkey, or chose fallback).
  passwordMfa,

  /// Recovery code entry (available from passkey or TOTP steps).
  recoveryCode,

  /// Warning shown after a recovery code is consumed.
  recoveryWarning,
}

class LoginScreen extends StatefulWidget {
  final AuthService auth;
  final UserService userService;

  const LoginScreen({super.key, required this.auth, required this.userService});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailStore = LoginEmailStore();

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _totpCtrl = TextEditingController();
  final _recoveryCtrl = TextEditingController();

  _LoginStep _step = _LoginStep.email;
  bool _loading = false;
  bool _obscure = true;
  bool _showEmailField = false;
  String? _error;

  // Identified email + its MFA capabilities.
  String _email = '';
  IdentifyResult? _identified;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _totpCtrl.dispose();
    _recoveryCtrl.dispose();
    super.dispose();
  }

  // ── Step transitions ──────────────────────────────────────────────────────

  void _goToStep(_LoginStep step) {
    setState(() {
      _step = step;
      _error = null;
      _loading = false;
      if (step == _LoginStep.email) _showEmailField = false;
    });
  }

  void _goBack() {
    if (_step == _LoginStep.recoveryCode) {
      // Go back to whichever MFA step the user came from.
      if (_identified?.hasPasskey == true) {
        _goToStep(_LoginStep.passkey);
      } else {
        _goToStep(_LoginStep.passwordMfa);
      }
    } else {
      _goToStep(_LoginStep.email);
      _emailCtrl.clear();
      _passwordCtrl.clear();
      _totpCtrl.clear();
    }
  }

  // ── Step 1: Email identification ──────────────────────────────────────────

  Future<void> _submitEmail([String? prefilledEmail]) async {
    final email = prefilledEmail ?? _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await widget.auth.identify(email);
      _email = email;
      _identified = result;

      if (result.hasPasskey) {
        _goToStep(_LoginStep.passkey);
      } else if (result.hasMFA) {
        _goToStep(_LoginStep.passwordMfa);
      } else {
        _goToStep(_LoginStep.password);
      }
    } catch (_) {
      setState(() => _error = 'Could not reach the server. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Step 2b / 3: Password (with optional MFA) ────────────────────────────

  Future<void> _signInWithPassword() async {
    if (_passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Password is required.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await widget.auth.login(_email, _passwordCtrl.text);

      // If MFA is required, the auth service sets mfaPending.
      if (widget.auth.mfaPending) {
        // For passkey step: auto-trigger passkey ceremony.
        if (_step == _LoginStep.passkey) {
          await _doPasskeyVerification();
          return;
        }
        // For password-only step but MFA came back (shouldn't happen, but safe).
        if (_step == _LoginStep.password) {
          _goToStep(_LoginStep.passwordMfa);
          return;
        }
        // Stay on passwordMfa — user needs to enter TOTP code on same screen.
        setState(() => _loading = false);
        return;
      }

      // Password change required — router handles the redirect.
      if (widget.auth.hasPasswordChangePending) return;

      // No MFA — login complete.
      _emailStore.addEmail(_email);
      await _loadUserDataAndFinish();
    } on AuthException {
      setState(() => _error = 'Invalid credentials');
    } catch (_) {
      setState(() => _error = 'Could not reach the server. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitPasswordAndTotp() async {
    if (_passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Password is required.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Step 1: login to get MFA challenge if not already done.
      if (!widget.auth.mfaPending) {
        await widget.auth.login(_email, _passwordCtrl.text);
        if (!widget.auth.mfaPending) {
          // Password change required — router handles the redirect.
          if (widget.auth.hasPasswordChangePending) return;
          // No MFA actually required — done.
          _emailStore.addEmail(_email);
          await _loadUserDataAndFinish();
          return;
        }
      }

      // Step 2: verify TOTP code.
      final code = _totpCtrl.text.trim();
      if (code.isEmpty) {
        setState(() {
          _error = 'Enter your authenticator code.';
          _loading = false;
        });
        return;
      }

      await widget.auth.verifyMFA(code);
      _emailStore.addEmail(_email);
      await _loadUserDataAndFinish();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
      _totpCtrl.clear();
    } catch (_) {
      setState(() => _error = 'Could not reach the server. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Passkey verification (after password) ─────────────────────────────────

  Future<void> _doPasskeyVerification() async {
    try {
      await widget.auth.verifyMFAWithPasskey();
      _emailStore.addEmail(_email);
      await _loadUserDataAndFinish();
    } on AuthException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      setState(() {
        _error = 'Passkey verification failed.';
        _loading = false;
      });
    }
  }

  // ── Recovery code ─────────────────────────────────────────────────────────

  Future<void> _submitRecoveryCode() async {
    final code = _recoveryCtrl.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter your recovery code.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // Ensure we have a pending MFA challenge.
      if (!widget.auth.mfaPending) {
        if (_passwordCtrl.text.isEmpty) {
          setState(() {
            _error = 'Enter your password first, then use a recovery code.';
            _loading = false;
          });
          return;
        }
        await widget.auth.login(_email, _passwordCtrl.text);
      }

      await widget.auth.verifyMFA(code);
      _emailStore.addEmail(_email);

      // Show the recovery warning before navigating away.
      // The router won't navigate yet because we haven't loaded user data.
      setState(() {
        _step = _LoginStep.recoveryWarning;
        _loading = false;
      });
    } on AuthException {
      setState(() => _error = 'Invalid recovery code. Please try again.');
      _recoveryCtrl.clear();
    } catch (_) {
      setState(() => _error = 'Could not reach the server. Try again.');
    } finally {
      if (mounted && _step != _LoginStep.recoveryWarning) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _proceedAfterRecoveryWarning() async {
    setState(() => _loading = true);
    await _loadUserDataAndFinish();
  }

  // ── Shared completion ─────────────────────────────────────────────────────

  Future<void> _loadUserDataAndFinish() async {
    await Future.wait([
      widget.userService.loadProfile(),
      widget.userService.loadPreferences(),
    ]);
    // The router will auto-navigate to /home.
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _buildCurrentStep(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case _LoginStep.email:
        return _buildEmailStep();
      case _LoginStep.passkey:
        return _buildPasskeyStep();
      case _LoginStep.password:
        return _buildPasswordStep();
      case _LoginStep.passwordMfa:
        return _buildPasswordMfaStep();
      case _LoginStep.recoveryCode:
        return _buildRecoveryCodeStep();
      case _LoginStep.recoveryWarning:
        return _buildRecoveryWarningStep();
    }
  }

  // ── Step builders ─────────────────────────────────────────────────────────

  Widget _buildEmailStep() {
    final savedEmails = _emailStore.getEmails();

    return Column(
      key: const ValueKey('email'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sign in to ${widget.auth.instanceName.isNotEmpty ? widget.auth.instanceName : "Luma"}',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 24),
        if (_error != null) _buildError(),
        // Show saved accounts as tiles if they exist.
        if (savedEmails.isNotEmpty && !_showEmailField) ...[
          ...savedEmails.map((email) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _EmailTile(
                  email: email,
                  onTap: () => _submitEmail(email),
                  onRemove: () {
                    _emailStore.removeEmail(email);
                    setState(() {});
                  },
                ),
              )),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => setState(() {
              _showEmailField = true;
              _emailCtrl.clear();
            }),
            child: const Text('Use another account'),
          ),
        ] else ...[
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
            onFieldSubmitted: (_) => _submitEmail(),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _loading ? null : () => _submitEmail(),
            child: _loading ? const _ButtonSpinner() : const Text('Next'),
          ),
        ],
      ],
    );
  }

  Widget _buildPasskeyStep() {
    return Column(
      key: const ValueKey('passkey'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBackButton(),
        const SizedBox(height: 8),
        Text('Welcome back', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(_email, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),
        if (_error != null) _buildError(),
        Text(
          'Use your passkey to sign in. No password needed.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _loading ? null : _signInAndPasskey,
          icon: const Icon(Icons.key),
          label: _loading
              ? const _ButtonSpinner()
              : const Text('Sign in with passkey'),
        ),
        const SizedBox(height: 12),
        if (_identified?.hasTOTP == true)
          TextButton(
            onPressed: () => _goToStep(_LoginStep.passwordMfa),
            child: const Text('Enter password & code instead'),
          ),
        TextButton(
          onPressed: () => _goToStep(_LoginStep.recoveryCode),
          child: const Text('Use a recovery code'),
        ),
      ],
    );
  }

  Future<void> _signInAndPasskey() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await widget.auth.signInWithPasskey(_email);
      _emailStore.addEmail(_email);
      await _loadUserDataAndFinish();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'Passkey verification failed. Try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildPasswordStep() {
    return Column(
      key: const ValueKey('password'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBackButton(),
        const SizedBox(height: 8),
        Text('Welcome back', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(_email, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),
        if (_error != null) _buildError(),
        TextFormField(
          controller: _passwordCtrl,
          obscureText: _obscure,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Password',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onFieldSubmitted: (_) => _signInWithPassword(),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _loading ? null : _signInWithPassword,
          child: _loading ? const _ButtonSpinner() : const Text('Sign in'),
        ),
      ],
    );
  }

  Widget _buildPasswordMfaStep() {
    return Column(
      key: const ValueKey('passwordMfa'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBackButton(),
        const SizedBox(height: 8),
        Text('Two-step verification',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(_email, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 24),
        if (_error != null) _buildError(),
        if (!widget.auth.mfaPending) ...[
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscure,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Password',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onFieldSubmitted: (_) => _submitPasswordAndTotp(),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _totpCtrl,
          autofocus: widget.auth.mfaPending,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                letterSpacing: 8,
              ),
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: const InputDecoration(
            hintText: '000000',
            labelText: 'Authenticator code',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            if (value.length == 6) {
              _submitPasswordAndTotp();
            }
          },
          onSubmitted: (_) => _submitPasswordAndTotp(),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _loading ? null : _submitPasswordAndTotp,
          child: _loading ? const _ButtonSpinner() : const Text('Verify'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => _goToStep(_LoginStep.recoveryCode),
          child: const Text('Use a recovery code'),
        ),
      ],
    );
  }

  Widget _buildRecoveryCodeStep() {
    return Column(
      key: const ValueKey('recovery'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBackButton(),
        const SizedBox(height: 8),
        Text('Recovery code',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          'Enter one of your recovery codes (e.g. XXXXX-XXXXX-XXXXX-XXXXX).',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        if (_error != null) _buildError(),
        if (!widget.auth.mfaPending) ...[
          TextFormField(
            controller: _passwordCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Password',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _recoveryCtrl,
          autofocus: widget.auth.mfaPending,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                letterSpacing: 4,
              ),
          inputFormatters: [
            LengthLimitingTextInputFormatter(23),
            FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-]')),
            TextInputFormatter.withFunction((oldValue, newValue) {
              return newValue.copyWith(text: newValue.text.toUpperCase());
            }),
          ],
          decoration: const InputDecoration(
            hintText: 'XXXXX-XXXXX-XXXXX-XXXXX',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) {
            if (value.length == 11 || value.length == 23) _submitRecoveryCode();
          },
          onSubmitted: (_) => _submitRecoveryCode(),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _loading ? null : _submitRecoveryCode,
          child: _loading ? const _ButtonSpinner() : const Text('Verify'),
        ),
      ],
    );
  }

  Widget _buildRecoveryWarningStep() {
    return Column(
      key: const ValueKey('recoveryWarning'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.orange),
        const SizedBox(height: 16),
        Text(
          'Recovery code used',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
          ),
          child: const Text(
            'You have used a recovery code to sign in. Each code can only be '
            'used once. Please go to Settings → Security to generate new '
            'recovery codes and make sure you do not run out.',
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _loading ? null : _proceedAfterRecoveryWarning,
          child: _loading
              ? const _ButtonSpinner()
              : const Text('Continue to Luma'),
        ),
      ],
    );
  }

  // ── Shared widgets ────────────────────────────────────────────────────────

  Widget _buildBackButton() {
    return Align(
      alignment: Alignment.centerLeft,
      child: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: _goBack,
        tooltip: 'Back',
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
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
    );
  }
}

// ── Email tile widget ───────────────────────────────────────────────────────

class _EmailTile extends StatelessWidget {
  final String email;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _EmailTile({
    required this.email,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                child: Text(
                  email[0].toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  email,
                  style: Theme.of(context).textTheme.bodyLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: onRemove,
                tooltip: 'Remove',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared spinner ──────────────────────────────────────────────────────────

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 20,
      width: 20,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
  }
}
