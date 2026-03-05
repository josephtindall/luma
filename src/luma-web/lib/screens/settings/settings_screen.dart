import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../services/user_service.dart';
import '../../services/webauthn_interop.dart' as webauthn;
import '../../widgets/user_avatar.dart';
import '../login/login_email_store.dart';

class SettingsScreen extends StatefulWidget {
  final UserService userService;

  const SettingsScreen({super.key, required this.userService});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _hasTOTP = false;

  @override
  void initState() {
    super.initState();
    // Load initial TOTP state.
    widget.userService.loadTOTPApps().then((apps) {
      if (mounted) setState(() => _hasTOTP = apps.isNotEmpty);
    });
  }

  void _onTOTPChanged(bool hasTOTP) {
    setState(() => _hasTOTP = hasTOTP);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: widget.userService,
        builder: (context, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  children: [
                    _ProfileSection(userService: widget.userService),
                    const SizedBox(height: 24),
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
                    _PreferencesSection(userService: widget.userService),
                    const SizedBox(height: 24),
                    _DevicesSection(userService: widget.userService),
                    const SizedBox(height: 24),
                    _AuditSection(userService: widget.userService),
                  ],
                ),
              ),
            ),
          );
        },
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
                                  return '${code.padRight(12)}${codes[i + 1]}';
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
                          return '${code.padRight(12)}${codes[i + 1]}';
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

class _AuditSection extends StatefulWidget {
  final UserService userService;

  const _AuditSection({required this.userService});

  @override
  State<_AuditSection> createState() => _AuditSectionState();
}

class _AuditSectionState extends State<_AuditSection> {
  late final Future<List<AuditEvent>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.userService.loadAudit();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Activity log',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            FutureBuilder<List<AuditEvent>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Text('Could not load activity: ${snap.error}',
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error));
                }
                final events = snap.data ?? [];
                if (events.isEmpty) {
                  return const Text('No activity yet.');
                }
                return Column(
                  children: events
                      .take(50)
                      .map((e) => _eventTile(context, e))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _eventTile(BuildContext context, AuditEvent event) {
    final (icon, label) = _eventMeta(event.event);
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(label),
      subtitle: Text(event.ipAddress),
      trailing: Text(
        _formatTime(event.occurredAt),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    );
  }

  (IconData, String) _eventMeta(String event) {
    return switch (event) {
      'login_success' => (Icons.login, 'Signed in'),
      'login_failed' => (Icons.error_outline, 'Failed sign-in attempt'),
      'logout' => (Icons.logout, 'Signed out'),
      'password_changed' => (Icons.lock, 'Password changed'),
      'device_revoked' => (Icons.phonelink_erase, 'Device revoked'),
      'token_refreshed' => (Icons.refresh, 'Session refreshed'),
      'profile_updated' => (Icons.person, 'Profile updated'),
      'preferences_updated' => (Icons.settings, 'Preferences updated'),
      _ => (Icons.info_outline, event.replaceAll('_', ' ')),
    };
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
