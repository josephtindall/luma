import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../services/auth_service.dart';

const _baseUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://localhost:8002',
);

/// Returns the browser's IANA timezone (e.g. "America/New_York") or null.
String? _detectBrowserTimezone() {
  try {
    // Equivalent to: Intl.DateTimeFormat().resolvedOptions().timeZone
    final intl = globalContext['Intl'] as JSObject?;
    if (intl == null) return null;
    final fmt = intl.callMethod('DateTimeFormat'.toJS) as JSObject;
    final opts = fmt.callMethod('resolvedOptions'.toJS) as JSObject;
    final tz = opts['timeZone'] as JSString?;
    return tz?.toDart;
  } catch (_) {
    return null;
  }
}

/// Three-step setup wizard: token → instance config → owner account.
class SetupWizardScreen extends StatefulWidget {
  final AuthService auth;

  const SetupWizardScreen({super.key, required this.auth});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen>
    with TickerProviderStateMixin {
  int _step = 0; // 0, 1, 2, 3 (3 = success)
  int _previousStep = 0;

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

  // Success screen animation
  late final AnimationController _successCtrl;
  late final Animation<double> _successScale;

  @override
  void initState() {
    super.initState();

    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _successScale = CurvedAnimation(
      parent: _successCtrl,
      curve: Curves.elasticOut,
    );

    // Auto-detect IANA timezone from the browser (falls back to 'UTC').
    _timezone = _detectBrowserTimezone() ?? 'UTC';
  }

  @override
  void dispose() {
    _successCtrl.dispose();
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

  void _setStep(int next) {
    setState(() {
      _previousStep = _step;
      _step = next;
      _error = null;
    });
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
        _setStep(1);

      } else if (resp.statusCode == 429) {
        setState(() =>
            _error = 'Too many attempts \u2014 wait a moment and try again.');
      } else {
        setState(() => _error = _parseError(
            resp, 'Invalid token \u2014 check startup logs.'));
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
        _setStep(2);

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

        final data = json.decode(resp.body) as Map<String, dynamic>;
        final token = data['access_token'] as String?;
        if (token != null && token.isNotEmpty) {
          // Show success screen, then navigate.
          _setStep(3);
          _successCtrl.forward();
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              widget.auth.activateSession(token);
              context.go('/home');
            }
          });
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
      if (_step != 3) {
        setState(() => _loading = false);
      }
    }
  }

  void _goBack() {
    _setStep(_step - 1);

  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case 0:
        return _Step0(
          key: const ValueKey(0),
          ctrl: _tokenCtrl,
          loading: _loading,
          onContinue: _verifyToken,
        );
      case 1:
        return _Step1(
          key: const ValueKey(1),
          formKey: _formKey1,
          nameCtrl: _instanceNameCtrl,
          loading: _loading,
          onContinue: _configure,
        );
      case 2:
        return _Step2(
          key: const ValueKey(2),
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
        );
      case 3:
        return _SuccessStep(
          key: const ValueKey(3),
          scaleAnimation: _successScale,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final goingForward = _step >= _previousStep;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Branded header
                Icon(
                  Icons.light_mode_rounded,
                  size: 40,
                  color: colors.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  'Luma',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 32),
                // Main card
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 40,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _StepIndicator(
                          currentStep: _step.clamp(0, 3),
                          labels: const ['Verify', 'Configure', 'Create'],
                        ),
                        const SizedBox(height: 32),
                        if (_error != null) ...[
                          _ErrorBanner(
                            message: _error!,
                            onDismiss: () => setState(() => _error = null),
                          ),
                          const SizedBox(height: 20),
                        ],
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          switchInCurve: Curves.easeOut,
                          switchOutCurve: Curves.easeIn,
                          transitionBuilder: (child, animation) {
                            final offset = goingForward
                                ? const Offset(1, 0)
                                : const Offset(-1, 0);
                            // The incoming child matches the current key.
                            final isIncoming =
                                child.key == ValueKey(_step);
                            final slideOffset = isIncoming
                                ? offset
                                : Offset(-offset.dx, 0);
                            return SlideTransition(
                              position: Tween(
                                begin: slideOffset,
                                end: Offset.zero,
                              ).animate(animation),
                              child: FadeTransition(
                                opacity: animation,
                                child: child,
                              ),
                            );
                          },
                          child: _buildCurrentStep(),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step indicator
// ---------------------------------------------------------------------------

class _StepIndicator extends StatelessWidget {
  final int currentStep; // 0–3 (3 = all complete)
  final List<String> labels;

  const _StepIndicator({
    required this.currentStep,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Row(
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(
                height: 2,
                color: i <= currentStep
                    ? colors.primary
                    : colors.outlineVariant,
              ),
            ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < currentStep
                      ? colors.primary
                      : i == currentStep && currentStep < 3
                          ? colors.primary
                          : currentStep >= 3
                              ? colors.primary
                              : Colors.transparent,
                  border: Border.all(
                    color: i <= currentStep || currentStep >= 3
                        ? colors.primary
                        : colors.outlineVariant,
                    width: 2,
                  ),
                ),
                child: Center(
                  child: i < currentStep || currentStep >= 3
                      ? Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: colors.onPrimary,
                        )
                      : i == currentStep
                          ? Text(
                              '${i + 1}',
                              style: textTheme.labelSmall?.copyWith(
                                color: colors.onPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : Text(
                              '${i + 1}',
                              style: textTheme.labelSmall?.copyWith(
                                color: colors.outlineVariant,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                labels[i],
                style: textTheme.labelSmall?.copyWith(
                  color: i <= currentStep || currentStep >= 3
                      ? colors.onSurface
                      : colors.outlineVariant,
                  fontWeight: i == currentStep
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 0 — Verify token
// ---------------------------------------------------------------------------

class _Step0 extends StatefulWidget {
  final TextEditingController ctrl;
  final bool loading;
  final VoidCallback onContinue;

  const _Step0({
    super.key,
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
    final theme = Theme.of(context);
    const half = _kCodeLength ~/ 2;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.vpn_key_rounded, size: 48, color: colors.primary),
        const SizedBox(height: 16),
        Text(
          'Verify ownership',
          style: theme.textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Paste the 8-character code from startup logs',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
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
                            EdgeInsets.only(right: i < half - 1 ? 6 : 0),
                        child: _buildCharBox(i, colors),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        '\u2014',
                        style: TextStyle(
                          fontSize: 20,
                          color: colors.outline,
                          fontWeight: FontWeight.w300,
                        ),
                      ),
                    ),
                    for (var i = half; i < _kCodeLength; i++)
                      Padding(
                        padding: EdgeInsets.only(
                            right: i < _kCodeLength - 1 ? 6 : 0),
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
        _WizardButton(
          loading: widget.loading,
          onPressed: widget.onContinue,
          label: 'Verify',
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
      width: 40,
      height: 48,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            char,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
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

// ---------------------------------------------------------------------------
// Step 1 — Configure instance
// ---------------------------------------------------------------------------

class _Step1 extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  final bool loading;
  final VoidCallback onContinue;

  const _Step1({
    super.key,
    required this.formKey,
    required this.nameCtrl,
    required this.loading,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.tune_rounded, size: 48, color: colors.primary),
          const SizedBox(height: 16),
          Text(
            'Name your instance',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Give your workspace a friendly name',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
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
          const SizedBox(height: 24),
          _WizardButton(
            loading: loading,
            onPressed: onContinue,
            label: 'Continue',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2 — Create owner
// ---------------------------------------------------------------------------

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
    super.key,
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
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.person_add_rounded, size: 48, color: colors.primary),
          const SizedBox(height: 16),
          Text(
            'Create owner account',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'This account will have full control over the instance',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: fullNameCtrl,
            decoration: const InputDecoration(
              labelText: 'Full name',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Required.' : null,
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 16),
          _PasswordField(ctrl: passwordCtrl),
          const SizedBox(height: 16),
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
          const SizedBox(height: 20),
          CheckboxListTile(
            value: acknowledged,
            onChanged: onAcknowledgedChanged,
            title: const Text(
              'I acknowledge that this account is the instance owner.',
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              TextButton.icon(
                onPressed: loading ? null : onBack,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Back'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _WizardButton(
                  loading: loading,
                  onPressed: onContinue,
                  label: 'Finish setup',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3 — Success
// ---------------------------------------------------------------------------

class _SuccessStep extends StatelessWidget {
  final Animation<double> scaleAnimation;

  const _SuccessStep({
    super.key,
    required this.scaleAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 24),
        ScaleTransition(
          scale: scaleAnimation,
          child: Icon(
            Icons.check_circle_rounded,
            size: 72,
            color: colors.primary,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'You\'re all set!',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Welcome to Luma',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: colors.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _WizardButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;
  final String label;

  const _WizardButton({
    required this.loading,
    required this.onPressed,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: loading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white),
            )
          : Text(label),
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
