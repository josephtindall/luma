import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:web/web.dart' as web;

import '../../models/user.dart';
import '../../services/user_service.dart';
import '../../services/webauthn_interop.dart' as webauthn;
import '../../widgets/user_avatar.dart';
import '../login/login_email_store.dart';

// ── Profile tab: avatar, display name, email, preferences ──────────────────
class SettingsProfileTab extends StatelessWidget {
  final UserService userService;

  const SettingsProfileTab({super.key, required this.userService});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: userService,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                _ProfileSection(userService: userService),
                const SizedBox(height: 24),
                _PreferencesSection(userService: userService),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Security tab: password, MFA, passkeys, recovery codes, devices ──────────
class SettingsSecurityTab extends StatefulWidget {
  final UserService userService;

  const SettingsSecurityTab({super.key, required this.userService});

  @override
  State<SettingsSecurityTab> createState() => _SettingsSecurityTabState();
}

class _SettingsSecurityTabState extends State<SettingsSecurityTab> {
  bool _hasTOTP = false;

  @override
  void initState() {
    super.initState();
    widget.userService.loadTOTPApps().then((apps) {
      if (mounted) setState(() => _hasTOTP = apps.isNotEmpty);
    });
  }

  void _onTOTPChanged(bool hasTOTP) => setState(() => _hasTOTP = hasTOTP);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.userService,
      builder: (context, _) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              children: [
                _PasswordSection(userService: widget.userService),
                const SizedBox(height: 24),
                _TOTPSection(
                  userService: widget.userService,
                  onTOTPChanged: _onTOTPChanged,
                ),
                const SizedBox(height: 24),
                _PasskeysSection(
                  userService: widget.userService,
                  hasTOTP: _hasTOTP,
                ),
                const SizedBox(height: 24),
                _RecoveryCodesSection(
                  userService: widget.userService,
                  hasTOTP: _hasTOTP,
                ),
                const SizedBox(height: 24),
                _AccountRecoverySection(userService: widget.userService),
                const SizedBox(height: 24),
                _DevicesSection(userService: widget.userService),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Activity tab: paginated, filterable audit log ───────────────────────────
class SettingsActivityTab extends StatelessWidget {
  final UserService userService;

  const SettingsActivityTab({super.key, required this.userService});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: _AuditSection(userService: userService),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------

class _ProfileSection extends StatefulWidget {
  final UserService userService;

  const _ProfileSection({required this.userService});

  @override
  State<_ProfileSection> createState() => _ProfileSectionState();
}

class _ProfileSectionState extends State<_ProfileSection> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  bool _saving = false;
  bool _controllersSynced = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _emailCtrl = TextEditingController();
    _syncControllers();
    widget.userService.addListener(_syncControllers);
  }

  void _syncControllers() {
    final p = widget.userService.profile;
    if (p != null && !_controllersSynced) {
      _nameCtrl.text = p.displayName;
      _emailCtrl.text = p.email;
      _controllersSynced = true;
    }
  }

  @override
  void dispose() {
    widget.userService.removeListener(_syncControllers);
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final oldEmail = widget.userService.profile?.email;
    final newEmail = _emailCtrl.text.trim();

    setState(() => _saving = true);
    try {
      await widget.userService.updateProfile(
        displayName: _nameCtrl.text.trim(),
        email: newEmail,
      );

      if (oldEmail != null && oldEmail != newEmail) {
        LoginEmailStore().replaceEmail(oldEmail, newEmail);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.userService.profile;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Profile', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            Center(
              child: UserAvatar(
                avatarSeed: p?.avatarSeed ?? '',
                displayName: p?.displayName ?? '',
                size: 80,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Display name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailCtrl,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save changes'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Password
// ---------------------------------------------------------------------------

class _PasswordSection extends StatefulWidget {
  final UserService userService;

  const _PasswordSection({required this.userService});

  @override
  State<_PasswordSection> createState() => _PasswordSectionState();
}

class _PasswordSectionState extends State<_PasswordSection> {
  final _currentCtrl = TextEditingController();
  final _newCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    if (_newCtrl.text != _confirmCtrl.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New passwords do not match')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.userService.changePassword(
        currentPassword: _currentCtrl.text,
        newPassword: _newCtrl.text,
      );
      _currentCtrl.clear();
      _newCtrl.clear();
      _confirmCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Password', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            TextField(
              controller: _currentCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Current password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _newCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirmCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirm new password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: _saving ? null : _change,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Change password'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// TOTP (Two-Factor Authentication)
// ---------------------------------------------------------------------------

class _TOTPSection extends StatefulWidget {
  final UserService userService;
  final ValueChanged<bool>? onTOTPChanged;

  const _TOTPSection({required this.userService, this.onTOTPChanged});

  @override
  State<_TOTPSection> createState() => _TOTPSectionState();
}

class _TOTPSectionState extends State<_TOTPSection> {
  late Future<List<TOTPApp>> _future;

  // Enrollment state.
  bool _enrolling = false;
  String? _pendingId;
  String? _secret;
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    _future = widget.userService.loadTOTPApps();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _future = widget.userService.loadTOTPApps().then((apps) {
        widget.onTOTPChanged?.call(apps.isNotEmpty);
        return apps;
      });
    });
  }

  Future<void> _startSetup() async {
    final name = _nameCtrl.text.trim();
    setState(() => _enrolling = true);
    try {
      final result = await widget.userService.setupTOTP(name);
      setState(() {
        _pendingId = result['id'];
        _secret = result['secret'];
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
      setState(() => _enrolling = false);
    }
  }

  Future<void> _confirmCode() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6 || _pendingId == null) return;

    // Capture current TOTP app count before confirming.
    List<TOTPApp>? currentApps;
    try {
      currentApps = await widget.userService.loadTOTPApps();
    } catch (_) {}

    setState(() => _confirming = true);
    try {
      await widget.userService.confirmTOTP(_pendingId!, code);
      setState(() {
        _enrolling = false;
        _pendingId = null;
        _secret = null;
      });
      _nameCtrl.clear();
      _codeCtrl.clear();
      _refresh();

      // If this was the first TOTP app, auto-generate recovery codes.
      final isFirstApp = (currentApps == null || currentApps.isEmpty);
      if (isFirstApp && mounted) {
        try {
          final codes = await widget.userService.generateRecoveryCodes();
          if (mounted) {
            await showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                title: const Text('Recovery codes generated'),
                content: SizedBox(
                  width: 400,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(ctx).colorScheme.errorContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Theme.of(ctx).colorScheme.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Save these codes in a safe place. If you lose access '
                                'to your authenticator app and use all 8 codes, you '
                                'will need to regenerate them or risk losing your '
                                'account forever.',
                                style: TextStyle(
                                    color: Theme.of(ctx)
                                        .colorScheme
                                        .onErrorContainer),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color:
                              Theme.of(ctx).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Theme.of(ctx).colorScheme.outline),
                        ),
                        child: SelectableText(
                          codes
                              .asMap()
                              .entries
                              .map((e) {
                                final i = e.key;
                                final code = e.value;
                                // 2-column layout: odd-indexed codes get leading tab
                                if (i % 2 == 0 && i < codes.length - 1) {
                                  return '${code.padRight(28)}${codes[i + 1]}';
                                } else if (i % 2 == 0) {
                                  return code;
                                }
                                return null;
                              })
                              .where((l) => l != null)
                              .join('\n'),
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 16,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('I\'ve saved these codes'),
                  ),
                ],
              ),
            );
          }
        } catch (_) {
          // Recovery code generation failed — user can do it manually later.
        }
      }

      widget.onTOTPChanged?.call(true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Authenticator app added')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  void _cancelEnrollment() {
    setState(() {
      _enrolling = false;
      _pendingId = null;
      _secret = null;
    });
    _nameCtrl.clear();
    _codeCtrl.clear();
  }

  Future<void> _remove(TOTPApp app) async {
    _passwordCtrl.clear();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove authenticator app'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Remove "${app.name}"? Enter your password to confirm.'),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || _passwordCtrl.text.isEmpty) {
      _passwordCtrl.clear();
      return;
    }

    try {
      await widget.userService.removeTOTPApp(app.id, _passwordCtrl.text);
      _passwordCtrl.clear();
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('"${app.name}" removed')),
        );
      }
    } catch (e) {
      _passwordCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Authenticator apps',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Use an authenticator app for two-factor authentication.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),

            // Enrolled apps list.
            FutureBuilder<List<TOTPApp>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Text(
                      'Could not load authenticator apps: ${snap.error}',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error));
                }
                final apps = snap.data ?? [];
                if (apps.isEmpty && !_enrolling) {
                  return const Text('No authenticator apps registered.');
                }
                return Column(
                  children: apps.map((a) => _appTile(context, a)).toList(),
                );
              },
            ),

            // Enrollment flow.
            if (_secret != null) ...[
              const Divider(height: 32),
              const Text(
                  'Enter this secret in your authenticator app, then type the 6-digit code to confirm.'),
              const SizedBox(height: 12),
              SelectableText(
                _secret!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  SizedBox(
                    width: 160,
                    child: TextField(
                      controller: _codeCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: const InputDecoration(
                        labelText: 'Code',
                        border: OutlineInputBorder(),
                        counterText: '',
                      ),
                      onSubmitted: (_) => _confirmCode(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _confirming ? null : _confirmCode,
                    child: _confirming
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Confirm'),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _cancelEnrollment,
                    child: const Text('Cancel'),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'App nickname (optional)',
                        hintText: 'e.g. My Ente Auth app',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _enrolling ? null : _startSetup,
                    icon: const Icon(Icons.add),
                    label: _enrolling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Add app'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _appTile(BuildContext context, TOTPApp app) {
    return ListTile(
      leading: const Icon(Icons.security),
      title: Text(app.name),
      subtitle: Text('Added ${_formatDate(app.createdAt)}'),
      trailing: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Remove',
        onPressed: () => _remove(app),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Passkeys
// ---------------------------------------------------------------------------

class _PasskeysSection extends StatefulWidget {
  final UserService userService;
  final bool hasTOTP;

  const _PasskeysSection({required this.userService, required this.hasTOTP});

  @override
  State<_PasskeysSection> createState() => _PasskeysSectionState();
}

class _PasskeysSectionState extends State<_PasskeysSection> {
  late Future<List<Passkey>> _future;
  final _nameCtrl = TextEditingController();
  bool _registering = false;

  @override
  void initState() {
    super.initState();
    _future = widget.userService.loadPasskeys();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _future = widget.userService.loadPasskeys();
    });
  }

  Future<void> _addPasskey() async {
    final name = _nameCtrl.text.trim();
    setState(() => _registering = true);
    try {
      // Step 1: Get creation options from the server.
      final options = await widget.userService.beginPasskeyRegistration(name);

      // Step 2: Prompt the browser to create a credential.
      final credential = await webauthn.createCredential(options);

      // Step 3: Send the credential back to the server.
      await widget.userService.finishPasskeyRegistration(credential);

      _nameCtrl.clear();
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Passkey added')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  Future<void> _revoke(Passkey passkey) async {
    final passwordCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove passkey'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                'Remove "${passkey.name}"? You won\'t be able to sign in with it. Enter your password to confirm.'),
            const SizedBox(height: 12),
            TextField(
              controller: passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true || passwordCtrl.text.isEmpty) {
      passwordCtrl.dispose();
      return;
    }

    try {
      await widget.userService.revokePasskey(passkey.id, passwordCtrl.text);
      passwordCtrl.dispose();
      _refresh();
    } catch (e) {
      passwordCtrl.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Passkeys', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Sign in with Touch ID, Windows Hello, or your phone.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<Passkey>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Text('Could not load passkeys: ${snap.error}',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error));
                }
                final passkeys = snap.data ?? [];
                if (passkeys.isEmpty && !_registering) {
                  return const Text('No passkeys registered.');
                }
                return Column(
                  children:
                      passkeys.map((p) => _passkeyTile(context, p)).toList(),
                );
              },
            ),
            const SizedBox(height: 12),
            if (!widget.hasTOTP) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Add an authenticator app first to enable passkey registration.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Passkey nickname (optional)',
                        hintText: 'e.g. MacBook Touch ID',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _registering ? null : _addPasskey,
                    icon: const Icon(Icons.add),
                    label: _registering
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Add passkey'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _passkeyTile(BuildContext context, Passkey passkey) {
    return ListTile(
      leading: const Icon(Icons.key),
      title: Text(passkey.name),
      subtitle: Text('Added ${_formatDate(passkey.createdAt)}'),
      trailing: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Remove',
        onPressed: () => _revoke(passkey),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Recovery Codes
// ---------------------------------------------------------------------------

class _RecoveryCodesSection extends StatefulWidget {
  final UserService userService;
  final bool hasTOTP;

  const _RecoveryCodesSection(
      {required this.userService, required this.hasTOTP});

  @override
  State<_RecoveryCodesSection> createState() => _RecoveryCodesSectionState();
}

class _RecoveryCodesSectionState extends State<_RecoveryCodesSection> {
  int? _count;
  bool _loading = true;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant _RecoveryCodesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.hasTOTP != oldWidget.hasTOTP) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final count = await widget.userService.getRecoveryCodesCount();
      if (mounted) {
        setState(() {
          _count = count;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Generate new recovery codes?'),
        content: const Text(
            'This will immediately invalidate any existing recovery codes you have saved. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    setState(() => _generating = true);

    try {
      final codes = await widget.userService.generateRecoveryCodes();
      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Save your recovery codes'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'These codes can be used to sign in if you lose your authenticator app or passkeys.'),
              const SizedBox(height: 8),
              const Text(
                'Copy or download them now. They will not be shown again.',
                style:
                    TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  codes
                      .asMap()
                      .entries
                      .map((e) {
                        final i = e.key;
                        final code = e.value;
                        if (i % 2 == 0 && i < codes.length - 1) {
                          return '${code.padRight(28)}${codes[i + 1]}';
                        } else if (i % 2 == 0) {
                          return code;
                        }
                        return null;
                      })
                      .where((l) => l != null)
                      .join('\n'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.5,
                      ),
                ),
              ),
            ],
          ),
          actions: [
            FilledButton.icon(
              onPressed: () {
                // In a real app we'd trigger a file download using universal_html
                // or similar, but for now we instruct the user to copy.
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Please select and copy the codes above')),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('I saved them'),
            ),
          ],
        ),
      );

      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error generating codes: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Recovery codes',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Use a recovery code to sign in if you lose access to your other MFA methods.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (!widget.hasTOTP)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline,
                        size: 20,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Add an authenticator app first to enable recovery codes.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                    ),
                  ],
                ),
              )
            else if (_loading)
              const CircularProgressIndicator()
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _count == 0
                        ? 'No active recovery codes.'
                        : '$_count unused codes remaining.',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  OutlinedButton.icon(
                    onPressed: _generating ? null : _generate,
                    icon: _generating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label:
                        Text(_count == 0 ? 'Generate codes' : 'Replace codes'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account Recovery Token
// ---------------------------------------------------------------------------

class _AccountRecoverySection extends StatefulWidget {
  final UserService userService;

  const _AccountRecoverySection({required this.userService});

  @override
  State<_AccountRecoverySection> createState() =>
      _AccountRecoverySectionState();
}

class _AccountRecoverySectionState extends State<_AccountRecoverySection> {
  bool? _hasToken;
  bool _loading = true;

  // Regenerate state
  final _passwordCtrl = TextEditingController();
  bool _regenerating = false;
  String? _newToken;
  bool _generatingPdf = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _newToken = null;
    });
    try {
      final has = await widget.userService.getRecoveryTokenStatus();
      if (mounted) setState(() => _hasToken = has);
    } catch (_) {
      if (mounted) setState(() => _hasToken = false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _regenerate() async {
    _passwordCtrl.clear();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Regenerate recovery code?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                'Your existing recovery code will be invalidated. Enter your password to confirm.'),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Current password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Regenerate')),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _regenerating = true);
    try {
      final token = await widget.userService.generateRecoveryToken(
        currentPassword: _passwordCtrl.text,
      );
      _passwordCtrl.clear();
      if (mounted) setState(() => _newToken = token);
    } catch (e) {
      _passwordCtrl.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _regenerating = false);
    }
  }

  List<String> _groups(String token) {
    final groups = <String>[];
    for (int i = 0; i < token.length; i += 4) {
      groups.add(token.substring(i, (i + 4).clamp(0, token.length)));
    }
    return groups;
  }

  void _copyToken(String token) {
    Clipboard.setData(ClipboardData(text: token));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recovery code copied to clipboard')),
    );
  }

  Future<void> _downloadPDF(String token) async {
    if (_generatingPdf) return;
    setState(() => _generatingPdf = true);
    try {
      final bytes = await _buildPdf(token);
      _triggerDownload(bytes, 'luma-recovery-code.pdf', 'application/pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not generate PDF: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  Future<Uint8List> _buildPdf(String token) async {
    final groups = _groups(token);
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(60),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Luma Account Recovery Code',
              style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 24),
            pw.Text(
              'Keep this code in a safe place. It is the only way to recover '
              'your account if you forget your password.',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.SizedBox(height: 32),
            ...List.generate(
                4,
                (row) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 14),
                      child: pw.Row(
                        children: List.generate(4, (col) {
                          final idx = row * 4 + col;
                          return pw.Padding(
                            padding: const pw.EdgeInsets.only(right: 14),
                            child: pw.Container(
                              width: 72,
                              padding: const pw.EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              decoration: pw.BoxDecoration(
                                border: pw.Border.all(
                                    color: PdfColors.grey400, width: 1),
                                borderRadius: const pw.BorderRadius.all(
                                    pw.Radius.circular(4)),
                              ),
                              child: pw.Text(
                                idx < groups.length ? groups[idx] : '',
                                style: pw.TextStyle(
                                  fontSize: 18,
                                  fontWeight: pw.FontWeight.bold,
                                  font: pw.Font.courier(),
                                ),
                                textAlign: pw.TextAlign.center,
                              ),
                            ),
                          );
                        }),
                      ),
                    )),
            pw.SizedBox(height: 32),
            pw.Text(
              'Do not share this code with anyone.',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.red900),
            ),
          ],
        ),
      ),
    );
    return Uint8List.fromList(await doc.save());
  }

  void _triggerDownload(Uint8List bytes, String filename, String mimeType) {
    final encoded = base64Encode(bytes);
    final dataUrl = 'data:$mimeType;base64,$encoded';
    final a = web.document.createElement('a') as web.HTMLAnchorElement;
    a.href = dataUrl;
    a.download = filename;
    a.click();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Account recovery code',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'A recovery code lets you reset your password without admin help '
              'if you forget it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (_loading)
              const CircularProgressIndicator()
            else if (_newToken != null)
              _NewTokenPanel(
                token: _newToken!,
                generatingPdf: _generatingPdf,
                onCopy: () => _copyToken(_newToken!),
                onDownload: () => _downloadPDF(_newToken!),
                onDone: _refresh,
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _hasToken == true
                        ? 'You have an active recovery code.'
                        : 'No recovery code set.',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  OutlinedButton.icon(
                    onPressed: _regenerating ? null : _regenerate,
                    icon: _regenerating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(_hasToken == true
                        ? 'Regenerate code'
                        : 'Generate code'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _NewTokenPanel extends StatelessWidget {
  final String token;
  final bool generatingPdf;
  final VoidCallback onCopy;
  final VoidCallback onDownload;
  final VoidCallback onDone;

  const _NewTokenPanel({
    required this.token,
    required this.generatingPdf,
    required this.onCopy,
    required this.onDownload,
    required this.onDone,
  });

  List<String> get _groups {
    final groups = <String>[];
    for (int i = 0; i < token.length; i += 4) {
      groups.add(token.substring(i, (i + 4).clamp(0, token.length)));
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final groups = _groups;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: colorScheme.onErrorContainer, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Save this code somewhere safe. It will not be shown again.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: colorScheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 4×4 grid — LayoutBuilder avoids Expanded-in-Column width ambiguity
        LayoutBuilder(
          builder: (context, constraints) {
            const cellGap = 8.0;
            final cellWidth = ((constraints.maxWidth - cellGap * 3) / 4)
                .clamp(0.0, double.infinity);
            return Column(
              children: List.generate(
                  4,
                  (row) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: List.generate(4, (col) {
                            final idx = row * 4 + col;
                            final group =
                                idx < groups.length ? groups[idx] : '';
                            return Padding(
                              padding:
                                  EdgeInsets.only(right: col < 3 ? cellGap : 0),
                              child: SizedBox(
                                width: cellWidth,
                                child: Container(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  decoration: BoxDecoration(
                                    border:
                                        Border.all(color: colorScheme.outline),
                                    borderRadius: BorderRadius.circular(6),
                                    color: colorScheme.surfaceContainerHighest,
                                  ),
                                  child: Text(
                                    group,
                                    textAlign: TextAlign.center,
                                    style:
                                        theme.textTheme.titleMedium?.copyWith(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      )),
            );
          },
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: generatingPdf ? null : onDownload,
              icon: generatingPdf
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download, size: 16),
              label: const Text('Download PDF'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: onDone,
              child: const Text("I've saved it"),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Preferences
// ---------------------------------------------------------------------------

class _PreferencesSection extends StatefulWidget {
  final UserService userService;

  const _PreferencesSection({required this.userService});

  @override
  State<_PreferencesSection> createState() => _PreferencesSectionState();
}

class _PreferencesSectionState extends State<_PreferencesSection> {
  Future<void> _update({
    String? theme,
    String? dateFormat,
    String? timeFormat,
    bool? compactMode,
  }) async {
    try {
      await widget.userService.updatePreferences(
        theme: theme,
        dateFormat: dateFormat,
        timeFormat: timeFormat,
        compactMode: compactMode,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save preference: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = widget.userService.preferences ?? const UserPreferences();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Preferences', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),

            // Theme
            _label(context, 'Theme'),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'system', label: Text('System')),
                ButtonSegment(value: 'light', label: Text('Light')),
                ButtonSegment(value: 'dark', label: Text('Dark')),
              ],
              selected: {prefs.theme},
              onSelectionChanged: (v) => _update(theme: v.first),
            ),
            const SizedBox(height: 16),

            // Date format
            _label(context, 'Date format'),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'YYYY-MM-DD', label: Text('YYYY-MM-DD')),
                ButtonSegment(value: 'MM/DD/YYYY', label: Text('MM/DD/YYYY')),
                ButtonSegment(value: 'DD/MM/YYYY', label: Text('DD/MM/YYYY')),
              ],
              selected: {prefs.dateFormat},
              onSelectionChanged: (v) => _update(dateFormat: v.first),
            ),
            const SizedBox(height: 16),

            // Time format
            _label(context, 'Time format'),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '12h', label: Text('12h')),
                ButtonSegment(value: '24h', label: Text('24h')),
              ],
              selected: {prefs.timeFormat},
              onSelectionChanged: (v) => _update(timeFormat: v.first),
            ),
            const SizedBox(height: 16),

            // Timezone
            _label(context, 'Timezone'),
            const SizedBox(height: 4),
            Text(prefs.timezone, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),

            // Compact mode
            SwitchListTile(
              title: const Text('Compact mode'),
              subtitle: const Text('Reduce spacing and font sizes'),
              value: prefs.compactMode,
              onChanged: (v) => _update(compactMode: v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) {
    return Text(text, style: Theme.of(context).textTheme.labelLarge);
  }
}

// ---------------------------------------------------------------------------
// Devices
// ---------------------------------------------------------------------------

class _DevicesSection extends StatefulWidget {
  final UserService userService;

  const _DevicesSection({required this.userService});

  @override
  State<_DevicesSection> createState() => _DevicesSectionState();
}

class _DevicesSectionState extends State<_DevicesSection> {
  late Future<List<Device>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.userService.loadDevices();
  }

  void _refresh() {
    setState(() {
      _future = widget.userService.loadDevices();
    });
  }

  Future<void> _revoke(Device device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Revoke device'),
        content: Text('Revoke "${device.name}"? It will be signed out.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Revoke')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await widget.userService.revokeDevice(device.id);
      _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Devices', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            FutureBuilder<List<Device>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Text('Could not load devices: ${snap.error}',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error));
                }
                final devices = snap.data ?? [];
                if (devices.isEmpty) {
                  return const Text('No active devices.');
                }
                return Column(
                  children:
                      devices.map((d) => _deviceTile(context, d)).toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _deviceTile(BuildContext context, Device device) {
    final icon = switch (device.platform.toLowerCase()) {
      'web' => Icons.language,
      'android' => Icons.phone_android,
      'ios' => Icons.phone_iphone,
      'macos' || 'windows' || 'linux' => Icons.computer,
      _ => Icons.devices,
    };

    return ListTile(
      leading: Icon(icon),
      title: Row(
        children: [
          Text(device.name),
          if (device.isCurrent) ...[
            const SizedBox(width: 8),
            Chip(
              label: const Text('This device'),
              labelStyle: Theme.of(context).textTheme.labelSmall,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
            ),
          ],
        ],
      ),
      subtitle: Text('Last seen ${_relativeTime(device.lastSeenAt)}'),
      trailing: device.isCurrent
          ? null
          : IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Revoke',
              onPressed: () => _revoke(device),
            ),
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

// ---------------------------------------------------------------------------
// Audit log
// ---------------------------------------------------------------------------

// ── Event metadata helpers (shared with admin_events_screen) ───────────────

(IconData, String) auditEventMeta(String event) {
  return switch (event) {
    'login_success' => (Icons.login, 'Signed in'),
    'login_failed' => (Icons.error_outline, 'Failed sign-in'),
    'logout' => (Icons.logout, 'Signed out'),
    'logout_all' => (Icons.logout, 'Signed out everywhere'),
    'password_changed' => (Icons.lock, 'Password changed'),
    'device_registered' => (Icons.devices, 'Device registered'),
    'device_revoked' => (Icons.phonelink_erase, 'Device revoked'),
    'profile_updated' => (Icons.person, 'Profile updated'),
    'preferences_updated' => (Icons.settings, 'Preferences updated'),
    'totp_enrolled' => (Icons.security, 'Authenticator added'),
    'totp_removed' => (Icons.security, 'Authenticator removed'),
    'mfa_challenge_success' => (Icons.verified_user, 'MFA verified'),
    'mfa_challenge_failed' => (Icons.gpp_bad, 'MFA failed'),
    'passkey_registered' => (Icons.fingerprint, 'Passkey registered'),
    'passkey_login' => (Icons.fingerprint, 'Signed in with passkey'),
    'passkey_revoked' => (Icons.fingerprint, 'Passkey revoked'),
    'account_locked' => (Icons.lock_person, 'Account locked'),
    'account_unlocked' => (Icons.lock_open, 'Account unlocked'),
    'user_registered' => (Icons.person_add, 'Account created'),
    'authz_denied' => (Icons.block, 'Access denied'),
    'token_reuse_detected' => (Icons.warning_amber, 'Token reuse detected'),
    // Admin: user management
    'admin_user_created' => (Icons.person_add, 'Admin: user created'),
    'admin_force_password_change' => (Icons.password, 'Admin: force password change'),
    'admin_password_reset_link' => (Icons.link, 'Admin: password reset link'),
    'admin_sessions_revoked' => (Icons.device_hub, 'Admin: sessions revoked'),
    'admin_totp_deleted' => (Icons.security, 'Admin: TOTP deleted'),
    'admin_passkeys_revoked' => (Icons.fingerprint, 'Admin: passkeys revoked'),
    // Admin: invitations
    'invitation_created' => (Icons.mail_outline, 'Invitation created'),
    'invitation_revoked' => (Icons.mail, 'Invitation revoked'),
    // Admin: groups
    'group_created' => (Icons.group_add, 'Group created'),
    'group_renamed' => (Icons.drive_file_rename_outline, 'Group renamed'),
    'group_deleted' => (Icons.group_remove, 'Group deleted'),
    'group_member_added' => (Icons.person_add_alt, 'Group member added'),
    'group_member_removed' => (Icons.person_remove, 'Group member removed'),
    'group_role_assigned' => (Icons.badge, 'Group role assigned'),
    'group_role_removed' => (Icons.badge, 'Group role removed'),
    // Admin: custom roles
    'role_created' => (Icons.admin_panel_settings, 'Role created'),
    'role_updated' => (Icons.admin_panel_settings, 'Role updated'),
    'role_deleted' => (Icons.admin_panel_settings, 'Role deleted'),
    'role_permission_set' => (Icons.policy, 'Role permission set'),
    'role_permission_removed' => (Icons.policy, 'Role permission removed'),
    'role_assigned_to_user' => (Icons.manage_accounts, 'Role assigned to user'),
    'role_unassigned_from_user' => (Icons.manage_accounts, 'Role unassigned from user'),
    // Admin: instance
    'instance_settings_updated' => (Icons.tune, 'Instance settings updated'),
    _ => (Icons.info_outline, event.replaceAll('_', ' ')),
  };
}

String auditFormatTime(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

// ── Audit section in Settings ───────────────────────────────────────────────

class _AuditSection extends StatefulWidget {
  final UserService userService;

  const _AuditSection({required this.userService});

  @override
  State<_AuditSection> createState() => _AuditSectionState();
}

class _AuditSectionState extends State<_AuditSection> {
  AuditPage? _page;
  bool _loading = false;
  String _search = '';
  String? _selectedEvent;

  static const _limit = 10;

  // Available event type options (excludes token_refreshed — hidden from users)
  static const _eventOptions = <(String?, String)>[
    (null, 'All activity'),
    ('login_success', 'Signed in'),
    ('login_failed', 'Failed sign-in'),
    ('logout', 'Signed out'),
    ('password_changed', 'Password changed'),
    ('device_revoked', 'Device revoked'),
    ('profile_updated', 'Profile updated'),
    ('totp_enrolled', 'Authenticator added'),
    ('totp_removed', 'Authenticator removed'),
    ('passkey_registered', 'Passkey registered'),
    ('passkey_revoked', 'Passkey revoked'),
    ('mfa_challenge_failed', 'MFA failed'),
  ];

  @override
  void initState() {
    super.initState();
    _load(offset: 0);
  }

  Future<void> _load({required int offset}) async {
    setState(() => _loading = true);
    try {
      final page = await widget.userService.loadAudit(
        limit: _limit,
        offset: offset,
        search: _search.isEmpty ? null : _search,
        eventFilter: _selectedEvent,
      );
      if (mounted) setState(() => _page = page);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load activity: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilters() => _load(offset: 0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = _page;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Activity log', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),

            // Filter row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search activity…',
                      prefixIcon: Icon(Icons.search, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (v) => _search = v,
                    onSubmitted: (_) => _applyFilters(),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButtonFormField<String?>(
                  initialValue: _selectedEvent,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: _eventOptions
                      .map((opt) => DropdownMenuItem(
                            value: opt.$1,
                            child: Text(opt.$2),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _selectedEvent = v);
                    _applyFilters();
                  },
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Content
            if (_loading && page == null)
              const Center(child: CircularProgressIndicator())
            else if (page == null || page.events.isEmpty)
              const Text('No activity yet.')
            else
              Column(
                children:
                    page.events.map((e) => _eventTile(context, e)).toList(),
              ),

            // Pagination
            if (page != null && page.total > _limit) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Page ${page.currentPage + 1} of ${page.totalPages}',
                    style: theme.textTheme.bodySmall,
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: page.offset > 0
                            ? () => _load(offset: page.offset - _limit)
                            : null,
                        child: const Text('← Prev'),
                      ),
                      TextButton(
                        onPressed: page.hasMore
                            ? () => _load(offset: page.offset + _limit)
                            : null,
                        child: const Text('Next →'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _eventTile(BuildContext context, AuditEvent event) {
    final (icon, label) = auditEventMeta(event.event);
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(label),
      subtitle: Text(event.ipAddress),
      trailing: Text(
        auditFormatTime(event.occurredAt),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }
}
