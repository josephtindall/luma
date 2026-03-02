import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../services/user_service.dart';
import '../../widgets/user_avatar.dart';

class SettingsScreen extends StatelessWidget {
  final UserService userService;

  const SettingsScreen({super.key, required this.userService});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: userService,
        builder: (context, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  children: [
                    _ProfileSection(userService: userService),
                    const SizedBox(height: 24),
                    _PasswordSection(userService: userService),
                    const SizedBox(height: 24),
                    _TOTPSection(userService: userService),
                    const SizedBox(height: 24),
                    _PasskeysSection(userService: userService),
                    const SizedBox(height: 24),
                    _PreferencesSection(userService: userService),
                    const SizedBox(height: 24),
                    _DevicesSection(userService: userService),
                    const SizedBox(height: 24),
                    _AuditSection(userService: userService),
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
    setState(() => _saving = true);
    try {
      await widget.userService.updateProfile(
        displayName: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
      );
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

  const _TOTPSection({required this.userService});

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
      _future = widget.userService.loadTOTPApps();
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
                  return Text('Could not load authenticator apps: ${snap.error}',
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error));
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
                        hintText: 'e.g. Work phone',
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

  const _PasskeysSection({required this.userService});

  @override
  State<_PasskeysSection> createState() => _PasskeysSectionState();
}

class _PasskeysSectionState extends State<_PasskeysSection> {
  late Future<List<Passkey>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.userService.loadPasskeys();
  }

  void _refresh() {
    setState(() {
      _future = widget.userService.loadPasskeys();
    });
  }

  Future<void> _revoke(Passkey passkey) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove passkey'),
        content: Text('Remove "${passkey.name}"? You won\'t be able to sign in with it.'),
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
    if (confirmed != true) return;

    try {
      await widget.userService.revokePasskey(passkey.id);
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
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error));
                }
                final passkeys = snap.data ?? [];
                if (passkeys.isEmpty) {
                  return const Text('No passkeys registered.');
                }
                return Column(
                  children:
                      passkeys.map((p) => _passkeyTile(context, p)).toList(),
                );
              },
            ),
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
            Text('Preferences',
                style: Theme.of(context).textTheme.titleMedium),
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
            Text(prefs.timezone,
                style: Theme.of(context).textTheme.bodyMedium),
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
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error));
                }
                final devices = snap.data ?? [];
                if (devices.isEmpty) {
                  return const Text('No active devices.');
                }
                return Column(
                  children: devices.map((d) => _deviceTile(context, d)).toList(),
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
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error));
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
