import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

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

  // Step 2
  final _formKey2 = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _acknowledged = false;

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();

    // Auto-detect timezone from the browser.
    final detected = DateTime.now().timeZoneName;
    if (_kTimezones.contains(detected)) {
      _timezone = detected;
    }

    // Restore step from sessionStorage on refresh.
    _restoreFromSession();
  }

  void _restoreFromSession() {
    try {
      final storage = web.window.sessionStorage;
      final savedStep = storage.getItem('luma_setup_step');
      final savedToken = storage.getItem('luma_setup_token');
      if (savedStep != null) {
        final step = int.tryParse(savedStep);
        if (step != null && step >= 0 && step <= 2) {
          _step = step;
          if (savedToken != null && savedToken.isNotEmpty) {
            _tokenCtrl.text = savedToken;
          }
        }
      }
    } catch (_) {
      // sessionStorage unavailable (e.g. SSR or restricted context) — ignore.
    }
  }

  void _saveStepToSession(int step) {
    try {
      final storage = web.window.sessionStorage;
      storage.setItem('luma_setup_step', step.toString());
      if (_tokenCtrl.text.isNotEmpty) {
        storage.setItem('luma_setup_token', _tokenCtrl.text);
      }
    } catch (_) {
      // Ignore if sessionStorage is unavailable.
    }
  }

  void _clearSession() {
    try {
      final storage = web.window.sessionStorage;
      storage.removeItem('luma_setup_step');
      storage.removeItem('luma_setup_token');
    } catch (_) {
      // Ignore.
    }
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    _instanceNameCtrl.dispose();
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  /// Parses an error message from a Haven JSON response body, falling back
  /// to [fallback] if the body cannot be decoded.
  String _parseError(http.Response resp, String fallback) {
    try {
      final body = json.decode(resp.body) as Map<String, dynamic>?;
      return (body?['error'] as String?) ??
          (body?['message'] as String?) ??
          fallback;
    } catch (_) {
      return fallback;
    }
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

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        setState(() => _step = 1);
        _saveStepToSession(1);
      } else if (resp.statusCode == 429) {
        setState(() =>
            _error = 'Too many attempts \u2014 wait a moment and try again.');
      } else {
        setState(() => _error = _parseError(
            resp, 'Invalid token \u2014 check Haven\'s startup logs.'));
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
          'name': _instanceNameCtrl.text.trim(),
          'timezone': _timezone,
          'locale': 'en-US',
        }),
      );

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        setState(() => _step = 2);
        _saveStepToSession(2);
      } else if (resp.statusCode == 429) {
        setState(() =>
            _error = 'Too many attempts \u2014 wait a moment and try again.');
      } else {
        setState(() =>
            _error = _parseError(resp, 'Configuration failed. Try again.'));
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
          'display_name': _fullNameCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'password': _passwordCtrl.text,
          'confirmed': true,
        }),
      );

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        _clearSession();
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final token = data['access_token'] as String?;
        if (token != null && token.isNotEmpty) {
          widget.auth.activateSession(token);
          if (mounted) context.go('/home');
        } else {
          setState(() => _error = 'Owner created but no token returned. Please log in.');
        }
      } else if (resp.statusCode == 429) {
        setState(() =>
            _error = 'Too many attempts \u2014 wait a moment and try again.');
      } else {
        setState(() =>
            _error = _parseError(resp, 'Setup failed. Try again.'));
      }
    } catch (_) {
      setState(() => _error = 'Could not reach the server. Try again.');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _goBack() {
    setState(() {
      _step -= 1;
      _error = null;
    });
    _saveStepToSession(_step);
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
                  _ErrorBanner(
                    message: _error!,
                    onDismiss: () => setState(() => _error = null),
                  ),
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
                      onTimezoneChanged: (v) => setState(() => _timezone = v),
                      loading: _loading,
                      onContinue: _configure,
                    ),
                    _Step2(
                      formKey: _formKey2,
                      fullNameCtrl: _fullNameCtrl,
                      emailCtrl: _emailCtrl,
                      passwordCtrl: _passwordCtrl,
                      confirmPasswordCtrl: _confirmPasswordCtrl,
                      acknowledged: _acknowledged,
                      onAcknowledgedChanged: (v) =>
                          setState(() => _acknowledged = v ?? false),
                      loading: _loading,
                      onContinue: _createOwner,
                      onBack: _goBack,
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

class _Step0 extends StatefulWidget {
  final TextEditingController ctrl;
  final bool loading;
  final VoidCallback onContinue;

  const _Step0({
    required this.ctrl,
    required this.loading,
    required this.onContinue,
  });

  @override
  State<_Step0> createState() => _Step0State();
}

const _kCodeLength = 8;

class _Step0State extends State<_Step0> {
  final _inputCtrl = TextEditingController();
  final _inputNode = FocusNode();
  String _display = '';

  @override
  void initState() {
    super.initState();
    _inputCtrl.addListener(_onInputChanged);

    // If the parent controller already has a value (restored from session),
    // seed the local display.
    if (widget.ctrl.text.isNotEmpty) {
      _inputCtrl.text = widget.ctrl.text;
    }
  }

  @override
  void dispose() {
    _inputCtrl.removeListener(_onInputChanged);
    _inputCtrl.dispose();
    _inputNode.dispose();
    super.dispose();
  }

  void _onInputChanged() {
    // Filter to alphanumeric, uppercase, clamp to 8 chars.
    final raw = _inputCtrl.text
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final clamped = raw.length > _kCodeLength
        ? raw.substring(0, _kCodeLength)
        : raw;

    // If filtering changed the text, rewrite without re-triggering.
    if (clamped != _inputCtrl.text) {
      _inputCtrl.value = TextEditingValue(
        text: clamped,
        selection: TextSelection.collapsed(offset: clamped.length),
      );
      return; // listener will re-fire with the clean value
    }

    setState(() => _display = clamped);
    widget.ctrl.text = clamped;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const half = _kCodeLength ~/ 2;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Step 1 of 3 \u2014 Verify ownership',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Paste the 8-character code from Haven\'s startup logs',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),
        // Stack: visual boxes on the bottom, real transparent TextField on top
        // so clicks land on the real input naturally.
        Stack(
          children: [
            // Visual display layer.
            ListenableBuilder(
              listenable: _inputNode,
              builder: (context, _) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < half; i++)
                      Padding(
                        padding:
                            EdgeInsets.only(right: i < half - 1 ? 10 : 0),
                        child: _buildCharBox(i, colors),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '\u2014',
                        style: TextStyle(
                          fontSize: 22,
                          color: colors.outline,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ),
                    for (var i = half; i < _kCodeLength; i++)
                      Padding(
                        padding: EdgeInsets.only(
                            right: i < _kCodeLength - 1 ? 10 : 0),
                        child: _buildCharBox(i, colors),
                      ),
                  ],
                );
              },
            ),
            // Invisible input layer — sits on top, same size, captures all
            // clicks, keyboard input, and paste.
            Positioned.fill(
              child: Center(
                child: SizedBox(
                  width: 1,
                  child: Opacity(
                    opacity: 0,
                    child: TextField(
                      controller: _inputCtrl,
                      focusNode: _inputNode,
                      autofocus: true,
                      maxLength: _kCodeLength,
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9]')),
                      ],
                      onSubmitted: (_) => widget.onContinue(),
                    ),
                  ),
                ),
              ),
            ),
            // Hit-target layer — transparent overlay with text cursor that
            // forwards clicks to the real input.
            Positioned.fill(
              child: MouseRegion(
                cursor: SystemMouseCursors.text,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _inputNode.requestFocus,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: widget.loading ? null : widget.onContinue,
          child: widget.loading
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

  Widget _buildCharBox(int index, ColorScheme colors) {
    final char = index < _display.length ? _display[index] : '';
    final isCursor = _inputNode.hasFocus && index == _display.length;
    final isFilled = char.isNotEmpty;

    final Color underlineColor;
    if (isCursor) {
      underlineColor = colors.primary;
    } else if (isFilled) {
      underlineColor = colors.onSurface;
    } else {
      underlineColor = colors.outlineVariant;
    }

    return SizedBox(
      width: 48,
      height: 52,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            char,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              letterSpacing: 2,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: isCursor ? 2.5 : 2,
            decoration: BoxDecoration(
              color: underlineColor,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ],
      ),
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

class _Step1 extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  final String timezone;
  final ValueChanged<String> onTimezoneChanged;
  final bool loading;
  final VoidCallback onContinue;

  const _Step1({
    required this.formKey,
    required this.nameCtrl,
    required this.timezone,
    required this.onTimezoneChanged,
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
          Text('Step 2 of 3 \u2014 Name your instance',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextFormField(
            controller: nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Instance name',
              hintText: 'e.g. My Home',
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
  final TextEditingController confirmPasswordCtrl;
  final bool acknowledged;
  final ValueChanged<bool?> onAcknowledgedChanged;
  final bool loading;
  final VoidCallback onContinue;
  final VoidCallback onBack;

  const _Step2({
    required this.formKey,
    required this.fullNameCtrl,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.confirmPasswordCtrl,
    required this.acknowledged,
    required this.onAcknowledgedChanged,
    required this.loading,
    required this.onContinue,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Step 3 of 3 \u2014 Create owner account',
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
          const SizedBox(height: 12),
          TextFormField(
            controller: confirmPasswordCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Confirm password',
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Please confirm your password.';
              if (v != passwordCtrl.text) return 'Passwords do not match.';
              return null;
            },
          ),
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
          Row(
            children: [
              TextButton(
                onPressed: loading ? null : onBack,
                child: const Text('Back'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
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
              ),
            ],
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
  final VoidCallback onDismiss;

  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.only(left: 12, top: 4, bottom: 4, right: 4),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: colors.onErrorContainer),
            onPressed: onDismiss,
            tooltip: 'Dismiss',
          ),
        ],
      ),
    );
  }
}
