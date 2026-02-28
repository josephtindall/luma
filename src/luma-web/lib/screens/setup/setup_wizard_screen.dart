import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../services/auth_service.dart';

const _baseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:8002',
);

/// Three-step setup wizard: token → instance config → owner account.
class SetupWizardScreen extends StatefulWidget {
  final AuthService auth;

  const SetupWizardScreen({super.key, required this.auth});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  int _step = 0; // 0, 1, 2

  // Step 0
  final _tokenCtrl = TextEditingController();

  // Step 1
  final _formKey1 = GlobalKey<FormState>();
  final _instanceNameCtrl = TextEditingController();
  String _timezone = 'UTC';
  String _locale = 'en-US';

  // Step 2
  final _formKey2 = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _acknowledged = false;

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _instanceNameCtrl.dispose();
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _verifyToken() async {
    final token = _tokenCtrl.text.trim();
    if (token.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/api/luma/setup/verify-token'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'token': token}),
      );

      if (resp.statusCode == 200) {
        setState(() => _step = 1);
      } else {
        setState(() => _error = 'Invalid token — check Haven\'s startup logs.');
      }
    } catch (_) {
      setState(() => _error = 'Could not reach the server. Try again.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _configure() async {
    if (!_formKey1.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/api/luma/setup/configure'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'instance_name': _instanceNameCtrl.text.trim(),
          'timezone': _timezone,
          'locale': _locale,
        }),
      );

      if (resp.statusCode == 200) {
        setState(() => _step = 2);
      } else {
        final body = json.decode(resp.body) as Map<String, dynamic>?;
        setState(() => _error =
            (body?['error'] as String?) ?? 'Configuration failed. Try again.');
      }
    } catch (_) {
      setState(() => _error = 'Could not reach the server. Try again.');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _createOwner() async {
    if (!_formKey2.currentState!.validate()) return;
    if (!_acknowledged) {
      setState(() => _error = 'You must acknowledge that this is the owner account.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final resp = await http.post(
        Uri.parse('$_baseUrl/api/luma/setup/owner'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'full_name': _fullNameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'password': _passwordCtrl.text,
        }),
      );

      if (resp.statusCode == 200 || resp.statusCode == 201) {
        // Log in immediately with the new owner credentials.
        await widget.auth.login(
          _emailCtrl.text.trim(),
          _passwordCtrl.text,
        );
        if (mounted) context.go('/home');
      } else {
        final body = json.decode(resp.body) as Map<String, dynamic>?;
        setState(
            () => _error = (body?['error'] as String?) ?? 'Setup failed. Try again.');
      }
    } on AuthException catch (e) {
      setState(() => _error = 'Owner created but login failed: ${e.message}');
    } catch (_) {
      setState(() => _error = 'Could not reach the server. Try again.');
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Set up Luma',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: (_step + 1) / 3),
                const SizedBox(height: 24),
                if (_error != null) ...[
                  _ErrorBanner(message: _error!),
                  const SizedBox(height: 16),
                ],
                IndexedStack(
                  index: _step,
                  children: [
                    _Step0(
                      ctrl: _tokenCtrl,
                      loading: _loading,
                      onContinue: _verifyToken,
                    ),
                    _Step1(
                      formKey: _formKey1,
                      nameCtrl: _instanceNameCtrl,
                      timezone: _timezone,
                      locale: _locale,
                      onTimezoneChanged: (v) => setState(() => _timezone = v),
                      onLocaleChanged: (v) => setState(() => _locale = v),
                      loading: _loading,
                      onContinue: _configure,
                    ),
                    _Step2(
                      formKey: _formKey2,
                      fullNameCtrl: _fullNameCtrl,
                      emailCtrl: _emailCtrl,
                      passwordCtrl: _passwordCtrl,
                      acknowledged: _acknowledged,
                      onAcknowledgedChanged: (v) =>
                          setState(() => _acknowledged = v ?? false),
                      loading: _loading,
                      onContinue: _createOwner,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Step0 extends StatelessWidget {
  final TextEditingController ctrl;
  final bool loading;
  final VoidCallback onContinue;

  const _Step0({
    required this.ctrl,
    required this.loading,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Step 1 of 3 — Verify ownership',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Setup token',
            hintText: 'Paste the token from Haven\'s startup logs',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (_) => onContinue(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: loading ? null : onContinue,
          child: loading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Text('Continue'),
        ),
      ],
    );
  }
}

// Common timezones — a practical subset of the IANA list.
const _kTimezones = [
  'UTC',
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'America/Anchorage',
  'America/Honolulu',
  'America/Sao_Paulo',
  'America/Argentina/Buenos_Aires',
  'America/Toronto',
  'America/Vancouver',
  'America/Mexico_City',
  'Europe/London',
  'Europe/Paris',
  'Europe/Berlin',
  'Europe/Madrid',
  'Europe/Rome',
  'Europe/Amsterdam',
  'Europe/Stockholm',
  'Europe/Moscow',
  'Europe/Istanbul',
  'Asia/Kolkata',
  'Asia/Dhaka',
  'Asia/Bangkok',
  'Asia/Singapore',
  'Asia/Shanghai',
  'Asia/Tokyo',
  'Asia/Seoul',
  'Asia/Dubai',
  'Australia/Sydney',
  'Australia/Melbourne',
  'Pacific/Auckland',
  'Africa/Cairo',
  'Africa/Nairobi',
  'Africa/Johannesburg',
];

const _kLocales = [
  'en-US',
  'en-GB',
  'en-AU',
  'en-CA',
  'es-ES',
  'es-MX',
  'fr-FR',
  'de-DE',
  'it-IT',
  'pt-BR',
  'pt-PT',
  'nl-NL',
  'sv-SE',
  'no-NO',
  'da-DK',
  'fi-FI',
  'pl-PL',
  'ru-RU',
  'tr-TR',
  'ar-SA',
  'he-IL',
  'hi-IN',
  'ja-JP',
  'ko-KR',
  'zh-CN',
  'zh-TW',
];

class _Step1 extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  final String timezone;
  final String locale;
  final ValueChanged<String> onTimezoneChanged;
  final ValueChanged<String> onLocaleChanged;
  final bool loading;
  final VoidCallback onContinue;

  const _Step1({
    required this.formKey,
    required this.nameCtrl,
    required this.timezone,
    required this.locale,
    required this.onTimezoneChanged,
    required this.onLocaleChanged,
    required this.loading,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Step 2 of 3 — Name your instance',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextFormField(
            controller: nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Instance name',
              hintText: 'e.g. Acme Engineering',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              if (v == null || v.trim().length < 2) {
                return 'Must be at least 2 characters.';
              }
              if (v.trim().length > 64) {
                return 'Must be 64 characters or fewer.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: timezone,
            decoration: const InputDecoration(
              labelText: 'Timezone',
              border: OutlineInputBorder(),
            ),
            items: _kTimezones
                .map((tz) => DropdownMenuItem(value: tz, child: Text(tz)))
                .toList(),
            onChanged: (v) => onTimezoneChanged(v!),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: locale,
            decoration: const InputDecoration(
              labelText: 'Locale',
              border: OutlineInputBorder(),
            ),
            items: _kLocales
                .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                .toList(),
            onChanged: (v) => onLocaleChanged(v!),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: loading ? null : onContinue,
            child: loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Continue'),
          ),
        ],
      ),
    );
  }
}

class _Step2 extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController fullNameCtrl;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool acknowledged;
  final ValueChanged<bool?> onAcknowledgedChanged;
  final bool loading;
  final VoidCallback onContinue;

  const _Step2({
    required this.formKey,
    required this.fullNameCtrl,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.acknowledged,
    required this.onAcknowledgedChanged,
    required this.loading,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Step 3 of 3 — Create owner account',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextFormField(
            controller: fullNameCtrl,
            decoration: const InputDecoration(
              labelText: 'Full name',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required.' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || !v.contains('@')) ? 'Enter a valid email.' : null,
          ),
          const SizedBox(height: 12),
          _PasswordField(ctrl: passwordCtrl),
          const SizedBox(height: 16),
          CheckboxListTile(
            value: acknowledged,
            onChanged: onAcknowledgedChanged,
            title: const Text(
              'I acknowledge that this account is the instance owner.',
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: loading ? null : onContinue,
            child: loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Finish setup'),
          ),
        ],
      ),
    );
  }
}

class _PasswordField extends StatefulWidget {
  final TextEditingController ctrl;

  const _PasswordField({required this.ctrl});

  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: widget.ctrl,
      builder: (_, value, __) {
        final length = value.text.length;
        return TextFormField(
          controller: widget.ctrl,
          obscureText: _obscure,
          decoration: InputDecoration(
            labelText: 'Password',
            border: const OutlineInputBorder(),
            helperText: '$length characters (min 12)',
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          validator: (v) {
            if (v == null || v.length < 12) {
              return 'Password must be at least 12 characters.';
            }
            return null;
          },
        );
      },
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}
