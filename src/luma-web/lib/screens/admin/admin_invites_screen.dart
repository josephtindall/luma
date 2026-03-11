import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/user.dart';
import '../../services/user_service.dart';

class AdminInvitesScreen extends StatefulWidget {
  final UserService userService;

  const AdminInvitesScreen({super.key, required this.userService});

  @override
  State<AdminInvitesScreen> createState() => _AdminInvitesScreenState();
}

class _AdminInvitesScreenState extends State<AdminInvitesScreen> {
  late Future<List<InvitationRecord>> _invFuture;

  @override
  void initState() {
    super.initState();
    _invFuture = widget.userService.listInvitations();
  }

  void _reload() {
    setState(() {
      _invFuture = widget.userService.listInvitations();
    });
  }

  void _showInvitePanel([String? initialEmail, String? revokeId]) {
    showDialog<void>(
      context: context,
      builder: (_) => _InvitePanel(
        userService: widget.userService,
        initialEmail: initialEmail,
        revokeId: revokeId,
      ),
    ).then((_) => _reload());
  }

  Future<void> _revokeWithConfirm(InvitationRecord inv) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dlg) => AlertDialog(
        title: const Text('Revoke invitation'),
        content: Text(
            'Revoke the invitation for ${inv.email}? '
            'The invite link will stop working immediately.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dlg, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(dlg, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.userService.revokeInvitation(inv.id);
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _InvitationsContent(
      future: _invFuture,
      onRevoke: _revokeWithConfirm,
      onReinvite: (inv) => _showInvitePanel(inv.email, inv.id),
      onCreateInvite: () => _showInvitePanel(),
      onReload: _reload,
    );
  }
}

// ── Invitations content ───────────────────────────────────────────────────────

class _InvitationsContent extends StatefulWidget {
  final Future<List<InvitationRecord>> future;
  final void Function(InvitationRecord) onRevoke;
  final void Function(InvitationRecord) onReinvite;
  final VoidCallback onCreateInvite;
  final VoidCallback onReload;

  const _InvitationsContent({
    required this.future,
    required this.onRevoke,
    required this.onReinvite,
    required this.onCreateInvite,
    required this.onReload,
  });

  @override
  State<_InvitationsContent> createState() => _InvitationsContentState();
}

class _InvitationsContentState extends State<_InvitationsContent> {
  String? _filter;

  List<InvitationRecord> _applyFilter(List<InvitationRecord> all) {
    return switch (_filter) {
      'pending' => all.where((i) => i.isPendingValid).toList(),
      'expired' => all.where((i) => i.isExpired).toList(),
      'accepted' => all.where((i) => i.isAccepted).toList(),
      'revoked' => all.where((i) => i.isRevoked).toList(),
      _ => all,
    };
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<InvitationRecord>>(
      future: widget.future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Could not load invitations: ${snap.error}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 16),
                FilledButton(
                    onPressed: widget.onReload, child: const Text('Retry')),
              ],
            ),
          );
        }

        final all = snap.data ?? [];
        final visible = _applyFilter(all);

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Chip(
                    label: Text('Invitations (${visible.length})'),
                    backgroundColor:
                        Theme.of(context).colorScheme.secondaryContainer,
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    icon: const Icon(Icons.person_add_outlined),
                    label: const Text('Create invite'),
                    onPressed: widget.onCreateInvite,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  _chip(context, null, 'All', all.length),
                  _chip(context, 'pending', 'Pending',
                      all.where((i) => i.isPendingValid).length),
                  _chip(context, 'expired', 'Expired',
                      all.where((i) => i.isExpired).length),
                  _chip(context, 'accepted', 'Accepted',
                      all.where((i) => i.isAccepted).length),
                  _chip(context, 'revoked', 'Revoked',
                      all.where((i) => i.isRevoked).length),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: visible.isEmpty
                    ? Center(
                        child: Text(
                          'No invitations to show.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: visible.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1),
                        itemBuilder: (_, i) => _InvitationRow(
                          inv: visible[i],
                          onRevoke: () => widget.onRevoke(visible[i]),
                          onReinvite: () => widget.onReinvite(visible[i]),
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(BuildContext context, String? value, String label, int count) {
    return FilterChip(
      label: Text('$label ($count)'),
      selected: _filter == value,
      onSelected: (_) => setState(() => _filter = value),
    );
  }
}

// ── Invitation row ────────────────────────────────────────────────────────────

class _InvitationRow extends StatelessWidget {
  final InvitationRecord inv;
  final VoidCallback onRevoke;
  final VoidCallback onReinvite;

  const _InvitationRow({
    required this.inv,
    required this.onRevoke,
    required this.onReinvite,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  inv.email.isEmpty ? '(no email)' : inv.email,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (inv.note.isNotEmpty)
                  Text(
                    inv.note,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                const SizedBox(height: 4),
                Text(
                  _dateLabel(),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _statusBadge(context),
          const SizedBox(width: 8),
          _actions(context),
        ],
      ),
    );
  }

  Widget _statusBadge(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (label, bg, fg) = switch (true) {
      _ when inv.isPendingValid => (
          'Pending',
          cs.primaryContainer,
          cs.onPrimaryContainer
        ),
      _ when inv.isExpired =>
        ('Expired', cs.errorContainer, cs.onErrorContainer),
      _ when inv.isAccepted => (
          'Accepted',
          cs.secondaryContainer,
          cs.onSecondaryContainer
        ),
      _ => ('Revoked', cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };
    return _Badge(label: label, color: bg, textColor: fg);
  }

  Widget _actions(BuildContext context) {
    if (inv.isAccepted || inv.isRevoked) {
      return const SizedBox(width: 40);
    }
    return MenuAnchor(
      menuChildren: [
        if (inv.isPendingValid)
          MenuItemButton(
            leadingIcon: const Icon(Icons.link_outlined),
            onPressed: onReinvite,
            child: const Text('View / resend link'),
          ),
        if (inv.isExpired)
          MenuItemButton(
            leadingIcon: const Icon(Icons.refresh_outlined),
            onPressed: onReinvite,
            child: const Text('Re-invite'),
          ),
        MenuItemButton(
          leadingIcon: Icon(Icons.cancel_outlined,
              color: Theme.of(context).colorScheme.error),
          onPressed: onRevoke,
          child: Text(
            'Revoke',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      ],
      builder: (context, controller, _) => IconButton(
        icon: const Icon(Icons.more_vert),
        tooltip: 'Actions',
        onPressed: () {
          if (controller.isOpen) {
            controller.close();
          } else {
            controller.open();
          }
        },
      ),
    );
  }

  String _dateLabel() {
    if (inv.isAccepted && inv.acceptedAt != null) {
      return 'Joined ${_fmtDate(inv.acceptedAt!)}';
    }
    if (inv.isRevoked && inv.revokedAt != null) {
      return 'Revoked ${_fmtDate(inv.revokedAt!)}';
    }
    if (inv.isExpired) {
      return 'Expired ${_fmtDate(inv.expiresAt)}';
    }
    return 'Expires ${_fmtDate(inv.expiresAt)}';
  }

  String _fmtDate(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-'
        '${l.day.toString().padLeft(2, '0')}';
  }
}

// ── Invite panel dialog ───────────────────────────────────────────────────────

class _InvitePanel extends StatefulWidget {
  final UserService userService;
  final String? initialEmail;
  final String? revokeId;

  const _InvitePanel(
      {required this.userService, this.initialEmail, this.revokeId});

  @override
  State<_InvitePanel> createState() => _InvitePanelState();
}

class _InvitePanelState extends State<_InvitePanel> {
  late final TextEditingController _emailController;
  bool _creating = false;
  String? _joinUrl;
  String? _error;
  bool _copied = false;
  String? _createdInvId;

  bool get _hasInitialEmail =>
      widget.initialEmail != null && widget.initialEmail!.isNotEmpty;
  bool get _isResend => widget.revokeId != null;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail ?? '');
    if (_hasInitialEmail && !_isResend) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _create());
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final idToRevoke = _createdInvId ?? widget.revokeId;
      if (idToRevoke != null) {
        await widget.userService.revokeInvitation(idToRevoke);
      }
      final result = await widget.userService.createInvitation(email);
      final url = '${Uri.base.origin}/join?token=${result.token}';
      setState(() {
        _joinUrl = url;
        _createdInvId = result.id;
        _creating = false;
      });
    } catch (e) {
      setState(() {
        _creating = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _copyUrl() async {
    if (_joinUrl == null) return;
    await Clipboard.setData(ClipboardData(text: _joinUrl!));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    _isResend ? 'Resend Invite' : 'Create Invite',
                    style: theme.textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _emailController,
                enabled: !_hasInitialEmail && _joinUrl == null && !_creating,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  hintText: 'user@example.com',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                autofocus: !_hasInitialEmail,
                onSubmitted: (_) => _isResend ? null : _create(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              if (_joinUrl == null) ...[
                if (_isResend) ...[
                  const SizedBox(height: 12),
                  Text(
                    'The original invite link cannot be retrieved. '
                    'Generating a new link will revoke the current one.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _creating ? null : _create,
                  child: _creating
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(_isResend ? 'Generate new link' : 'Create invite'),
                ),
              ] else ...[
                const SizedBox(height: 24),
                Text(
                  'Invite URL',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: SelectableText(
                          _joinUrl!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(fontFamily: 'monospace'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon:
                          Icon(_copied ? Icons.check : Icons.copy_outlined),
                      tooltip: _copied ? 'Copied!' : 'Copy',
                      onPressed: _copyUrl,
                    ),
                    IconButton(
                      icon: _creating
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_outlined),
                      tooltip: 'Regenerate link',
                      onPressed: _creating ? null : _create,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.email_outlined),
                  label: const Text('Send invite via Email'),
                  onPressed: null,
                ),
                const SizedBox(height: 24),
                Center(
                  child: QrImageView(
                    data: _joinUrl!,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared badge ──────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;

  const _Badge({
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: textColor),
      ),
    );
  }
}
