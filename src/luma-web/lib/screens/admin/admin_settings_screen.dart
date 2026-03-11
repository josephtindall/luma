import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/instance_settings.dart';
import '../../services/user_service.dart';

class AdminSettingsScreen extends StatefulWidget {
  final UserService userService;

  const AdminSettingsScreen({super.key, required this.userService});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  bool _loading = true;
  String? _error;
  bool _saving = false;

  final _nameController = TextEditingController();
  final _minLengthController = TextEditingController();
  final _historyCountController = TextEditingController();

  String _contentWidth = 'wide';
  bool _requireUppercase = false;
  bool _requireLowercase = false;
  bool _requireNumbers = false;
  bool _requireSymbols = false;
  bool _showGithubButton = true;
  bool _showDonateButton = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _minLengthController.dispose();
    _historyCountController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final s = await widget.userService.getInstanceSettings();
      _applySettings(s);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  void _applySettings(InstanceSettings s) {
    _nameController.text = s.name;
    _contentWidth = s.contentWidth;
    _minLengthController.text = s.passwordMinLength.toString();
    _historyCountController.text = s.passwordHistoryCount.toString();
    _requireUppercase = s.passwordRequireUppercase;
    _requireLowercase = s.passwordRequireLowercase;
    _requireNumbers = s.passwordRequireNumbers;
    _requireSymbols = s.passwordRequireSymbols;
    _showGithubButton = s.showGithubButton;
    _showDonateButton = s.showDonateButton;
  }

  Future<void> _save() async {
    final minLen = int.tryParse(_minLengthController.text) ?? 8;
    final histCount = int.tryParse(_historyCountController.text) ?? 0;

    if (minLen < 6 || minLen > 128) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Minimum length must be between 6 and 128')),
      );
      return;
    }
    if (histCount < 0 || histCount > 24) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Password history count must be between 0 and 24')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final updated = await widget.userService.updateInstanceSettings(
        InstanceSettings(
          name: _nameController.text.trim(),
          contentWidth: _contentWidth,
          passwordMinLength: minLen,
          passwordRequireUppercase: _requireUppercase,
          passwordRequireLowercase: _requireLowercase,
          passwordRequireNumbers: _requireNumbers,
          passwordRequireSymbols: _requireSymbols,
          passwordHistoryCount: histCount,
          showGithubButton: _showGithubButton,
          showDonateButton: _showDonateButton,
        ),
      );
      _applySettings(updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Instance Settings',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 24),

            // ── Instance section ──────────────────────────────────────────
            _SectionHeader('Instance'),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Instance name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            Text('Content width',
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'narrow',
                  label: Text('Narrow'),
                  tooltip: 'Smaller centered layout',
                ),
                ButtonSegment(
                  value: 'wide',
                  label: Text('Wide'),
                  tooltip: 'Wider centered layout, good for 16:9 screens',
                ),
                ButtonSegment(
                  value: 'max',
                  label: Text('Max'),
                  tooltip: 'Near full-width layout',
                ),
              ],
              selected: {_contentWidth},
              onSelectionChanged: (s) =>
                  setState(() => _contentWidth = s.first),
            ),
            const SizedBox(height: 24),

            // ── Password requirements ─────────────────────────────────────
            _SectionHeader('Password Requirements'),
            const SizedBox(height: 12),
            SizedBox(
              width: 200,
              child: TextField(
                controller: _minLengthController,
                decoration: const InputDecoration(
                  labelText: 'Minimum length',
                  border: OutlineInputBorder(),
                  helperText: '6 – 128',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
            const SizedBox(height: 12),
            _BoolTile(
              label: 'Require uppercase letter',
              value: _requireUppercase,
              onChanged: (v) => setState(() => _requireUppercase = v),
            ),
            _BoolTile(
              label: 'Require lowercase letter',
              value: _requireLowercase,
              onChanged: (v) => setState(() => _requireLowercase = v),
            ),
            _BoolTile(
              label: 'Require number',
              value: _requireNumbers,
              onChanged: (v) => setState(() => _requireNumbers = v),
            ),
            _BoolTile(
              label: 'Require symbol',
              value: _requireSymbols,
              onChanged: (v) => setState(() => _requireSymbols = v),
            ),
            const SizedBox(height: 24),

            // ── Password history ──────────────────────────────────────────
            _SectionHeader('Password History'),
            const SizedBox(height: 12),
            SizedBox(
              width: 200,
              child: TextField(
                controller: _historyCountController,
                decoration: const InputDecoration(
                  labelText: 'Prevent reuse of last N passwords',
                  border: OutlineInputBorder(),
                  helperText: '0 = disabled, max 24',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
            ),
            const SizedBox(height: 24),

            // ── UI Settings ───────────────────────────────────────────────
            _SectionHeader('UI Settings'),
            const SizedBox(height: 12),
            _BoolTile(
              label: 'Show GitHub button in top bar',
              value: _showGithubButton,
              onChanged: (v) => setState(() => _showGithubButton = v),
            ),
            _BoolTile(
              label: 'Show Donate button in top bar',
              value: _showDonateButton,
              onChanged: (v) => setState(() => _showDonateButton = v),
            ),
            const SizedBox(height: 32),

            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save settings'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}

class _BoolTile extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _BoolTile({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      title: Text(label),
      value: value,
      onChanged: (v) => onChanged(v ?? false),
      contentPadding: EdgeInsets.zero,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}
