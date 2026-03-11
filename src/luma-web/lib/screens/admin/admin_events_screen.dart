import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

import '../../models/user.dart';
import '../../services/user_service.dart';
import '../settings/settings_screen.dart' show auditEventMeta, auditFormatTime;

class AdminEventsScreen extends StatefulWidget {
  final UserService userService;

  const AdminEventsScreen({super.key, required this.userService});

  @override
  State<AdminEventsScreen> createState() => _AdminEventsScreenState();
}

class _AdminEventsScreenState extends State<AdminEventsScreen> {
  AuditPage? _page;
  bool _loading = false;
  bool _exportLoading = false;

  final _searchController = TextEditingController();
  String? _selectedEventType;
  DateTimeRange? _dateRange;

  // Key incremented on clearFilters to force DropdownButtonFormField rebuild
  // with new initialValue (Flutter's initialValue is read only on first build).
  int _dropdownKey = 0;

  static const _limit = 30;

  static const _eventOptions = <(String?, String)>[
    (null, 'All event types'),
    // Auth events
    ('login_success', 'Signed in'),
    ('login_failed', 'Failed sign-in'),
    ('logout', 'Signed out'),
    ('logout_all', 'Signed out everywhere'),
    ('password_changed', 'Password changed'),
    ('device_registered', 'Device registered'),
    ('device_revoked', 'Device revoked'),
    ('token_refreshed', 'Session refreshed'),
    ('token_reuse_detected', 'Token reuse detected'),
    ('profile_updated', 'Profile updated'),
    ('totp_enrolled', 'Authenticator added'),
    ('totp_removed', 'Authenticator removed'),
    ('mfa_challenge_success', 'MFA verified'),
    ('mfa_challenge_failed', 'MFA failed'),
    ('passkey_registered', 'Passkey registered'),
    ('passkey_login', 'Passkey sign-in'),
    ('passkey_revoked', 'Passkey revoked'),
    ('account_locked', 'Account locked'),
    ('account_unlocked', 'Account unlocked'),
    ('user_registered', 'Account created'),
    ('authz_denied', 'Access denied'),
    // Admin: user management
    ('admin_user_created', 'Admin: user created'),
    ('admin_force_password_change', 'Admin: force password change'),
    ('admin_password_reset_link', 'Admin: password reset link'),
    ('admin_sessions_revoked', 'Admin: sessions revoked'),
    ('admin_totp_deleted', 'Admin: TOTP deleted'),
    ('admin_passkeys_revoked', 'Admin: passkeys revoked'),
    // Admin: invitations
    ('invitation_created', 'Invitation created'),
    ('invitation_revoked', 'Invitation revoked'),
    // Admin: groups
    ('group_created', 'Group created'),
    ('group_renamed', 'Group renamed'),
    ('group_deleted', 'Group deleted'),
    ('group_member_added', 'Group member added'),
    ('group_member_removed', 'Group member removed'),
    ('group_role_assigned', 'Group role assigned'),
    ('group_role_removed', 'Group role removed'),
    // Admin: custom roles
    ('role_created', 'Role created'),
    ('role_updated', 'Role updated'),
    ('role_deleted', 'Role deleted'),
    ('role_permission_set', 'Role permission set'),
    ('role_permission_removed', 'Role permission removed'),
    ('role_assigned_to_user', 'Role assigned to user'),
    ('role_unassigned_from_user', 'Role unassigned from user'),
    // Admin: instance
    ('instance_settings_updated', 'Instance settings updated'),
  ];

  @override
  void initState() {
    super.initState();
    _load(offset: 0);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({required int offset}) async {
    setState(() => _loading = true);
    try {
      final page = await widget.userService.loadAdminAudit(
        limit: _limit,
        offset: offset,
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        eventFilter: _selectedEventType,
        after: _dateRange?.start,
        before: _dateRange?.end != null
            ? _dateRange!.end.add(const Duration(days: 1))
            : null,
      );
      if (mounted) setState(() => _page = page);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not load events: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _exportCSV() async {
    if (_exportLoading) return;
    setState(() => _exportLoading = true);
    try {
      final page = await widget.userService.loadAdminAudit(
        limit: 1000,
        offset: 0,
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        eventFilter: _selectedEventType,
        after: _dateRange?.start,
        before: _dateRange?.end != null
            ? _dateRange!.end.add(const Duration(days: 1))
            : null,
      );

      final buf = StringBuffer();
      buf.writeln(
          'id,event,user_email,user_display_name,ip_address,user_agent,metadata,occurred_at');
      for (final e in page.events) {
        buf.writeln([
          e.id,
          _csvCell(e.event),
          _csvCell(e.userEmail ?? ''),
          _csvCell(e.userDisplayName ?? ''),
          _csvCell(e.ipAddress),
          _csvCell(e.userAgent),
          _csvCell(e.metadata.isEmpty ? '' : jsonEncode(e.metadata)),
          e.occurredAt.toUtc().toIso8601String(),
        ].join(','));
      }

      final encoded = base64Encode(utf8.encode(buf.toString()));
      final a = web.document.createElement('a') as web.HTMLAnchorElement;
      a.href = 'data:text/csv;base64,$encoded';
      a.download = 'luma-audit-events.csv';
      a.click();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _exportLoading = false);
    }
  }

  String _csvCell(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  Future<void> _pickDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _dateRange,
    );
    if (range != null) {
      setState(() => _dateRange = range);
      _load(offset: 0);
    }
  }

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _selectedEventType = null;
      _dateRange = null;
      _dropdownKey++; // force DropdownButtonFormField to rebuild with new initialValue
    });
    _load(offset: 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = _page;
    final hasFilters = _searchController.text.isNotEmpty ||
        _selectedEventType != null ||
        _dateRange != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Filter bar ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search events…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    // Show a clear-and-reload button when there's text
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                              _load(offset: 0);
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => setState(() {}), // refresh suffixIcon
                  onSubmitted: (_) => _load(offset: 0),
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String?>(
                  key: ValueKey(_dropdownKey),
                  initialValue: _selectedEventType,
                  decoration: const InputDecoration(
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: _eventOptions
                      .map((opt) => DropdownMenuItem(
                            value: opt.$1,
                            child: Text(opt.$2,
                                overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    setState(() => _selectedEventType = v);
                    _load(offset: 0);
                  },
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickDateRange,
                icon: const Icon(Icons.date_range, size: 16),
                label: Text(_dateRange == null
                    ? 'Date range'
                    : '${_fmtDate(_dateRange!.start)} – ${_fmtDate(_dateRange!.end)}'),
              ),
              if (hasFilters)
                TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.clear, size: 16),
                  label: const Text('Clear filters'),
                ),
              if (widget.userService.canExportAuditLog)
                OutlinedButton.icon(
                  onPressed: _exportLoading ? null : _exportCSV,
                  icon: _exportLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download, size: 16),
                  label: const Text('Export CSV'),
                ),
            ],
          ),
        ),

        // ── Pagination bar (sticky, between filter and list) ────────────
        if (page != null && page.total > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  page.events.isEmpty
                      ? 'No results'
                      : 'Showing ${page.offset + 1}–'
                          '${page.offset + page.events.length}'
                          ' of ${page.total}',
                  style: theme.textTheme.bodySmall,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.only(right: 8),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    TextButton(
                      onPressed: page.offset > 0
                          ? () => _load(offset: page.offset - _limit)
                          : null,
                      child: const Text('← Prev'),
                    ),
                    Text(
                      'Page ${page.currentPage + 1} of ${page.totalPages}',
                      style: theme.textTheme.bodySmall,
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
          ),

        // Thin separator between controls and list
        const Divider(height: 1),

        // ── Event list ──────────────────────────────────────────────────
        Expanded(
          child: _loading && page == null
              ? const Center(child: CircularProgressIndicator())
              : page == null || page.events.isEmpty
                  ? Center(
                      child: Text(
                        hasFilters
                            ? 'No events match your filters.'
                            : 'No events yet.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: page.events.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, indent: 56),
                      itemBuilder: (context, i) =>
                          _EventRow(event: page.events[i]),
                    ),
        ),
      ],
    );
  }

  String _fmtDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// Event row with expandable metadata details
// ---------------------------------------------------------------------------

class _EventRow extends StatefulWidget {
  final AuditEvent event;

  const _EventRow({required this.event});

  @override
  State<_EventRow> createState() => _EventRowState();
}

class _EventRowState extends State<_EventRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final e = widget.event;
    final (icon, label) = auditEventMeta(e.event);
    final actor = e.actorLabel;

    // Build a concise subtitle: IP · parsed-UA
    final uaParsed = _parseUA(e.userAgent);
    final subtitleParts = [
      if (e.ipAddress.isNotEmpty) e.ipAddress,
      if (uaParsed.isNotEmpty) uaParsed,
    ];

    final hasDetails = e.metadata.isNotEmpty ||
        (e.userEmail != null) ||
        (e.userDisplayName != null) ||
        e.userAgent.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: hasDetails ? () => setState(() => _expanded = !_expanded) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Leading icon
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: 12),
                  child: Icon(icon, size: 20, color: cs.onSurfaceVariant),
                ),
                // Main content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title row: label + actor chip
                      Row(
                        children: [
                          Text(label,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500)),
                          if (actor != '—') ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: cs.secondaryContainer,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                actor,
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: cs.onSecondaryContainer),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (subtitleParts.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            subtitleParts.join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
                // Trailing: timestamp + expand chevron
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(auditFormatTime(e.occurredAt),
                        style: theme.textTheme.bodySmall),
                    if (hasDetails)
                      Icon(
                        _expanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Expanded details panel
        if (_expanded)
          _DetailsPanel(event: e, theme: theme),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Details panel shown when a row is expanded
// ---------------------------------------------------------------------------

class _DetailsPanel extends StatelessWidget {
  final AuditEvent event;
  final ThemeData theme;

  const _DetailsPanel({required this.event, required this.theme});

  @override
  Widget build(BuildContext context) {
    final cs = theme.colorScheme;
    final e = event;

    final rows = <(String, String)>[
      ('Occurred at', e.occurredAt.toLocal().toIso8601String().replaceFirst('T', ' ').split('.').first),
      if (e.userEmail != null) ('User email', e.userEmail!),
      if (e.userDisplayName != null) ('Display name', e.userDisplayName!),
      if (e.userId != null) ('User ID', e.userId!),
      if (e.ipAddress.isNotEmpty) ('IP address', e.ipAddress),
      if (e.userAgent.isNotEmpty) ('User agent', e.userAgent),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(48, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(label,
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant)),
                  ),
                  Expanded(
                    child: SelectableText(value,
                        style: theme.textTheme.bodySmall),
                  ),
                ],
              ),
            ),
          if (e.metadata.isNotEmpty) ...[
            if (rows.isNotEmpty)
              Divider(
                  height: 12,
                  color: cs.outlineVariant.withValues(alpha: 0.5)),
            Text('Details',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            SelectableText(
              const JsonEncoder.withIndent('  ')
                  .convert(e.metadata),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// User-agent parser — extracts a readable "Browser vN on OS" string
// ---------------------------------------------------------------------------

/// Parses a raw user-agent string into a concise, human-readable label.
/// Returns empty string if the input is empty or unrecognisable.
String _parseUA(String ua) {
  if (ua.isEmpty) return '';

  // Detect OS
  String os = '';
  if (ua.contains('Windows NT')) {
    final m = RegExp(r'Windows NT ([\d.]+)').firstMatch(ua);
    final ver = m?.group(1);
    os = switch (ver) {
      '10.0' => 'Windows 10/11',
      '6.3' => 'Windows 8.1',
      '6.2' => 'Windows 8',
      '6.1' => 'Windows 7',
      _ => 'Windows',
    };
  } else if (ua.contains('Mac OS X')) {
    final m = RegExp(r'Mac OS X ([\d_]+)').firstMatch(ua);
    final ver = (m?.group(1) ?? '').replaceAll('_', '.');
    os = ver.isNotEmpty ? 'macOS $ver' : 'macOS';
  } else if (ua.contains('Android')) {
    final m = RegExp(r'Android ([\d.]+)').firstMatch(ua);
    os = m != null ? 'Android ${m.group(1)}' : 'Android';
  } else if (ua.contains('iPhone') || ua.contains('iPad')) {
    final m = RegExp(r'OS ([\d_]+)').firstMatch(ua);
    final ver = (m?.group(1) ?? '').replaceAll('_', '.');
    final dev = ua.contains('iPad') ? 'iPadOS' : 'iOS';
    os = ver.isNotEmpty ? '$dev $ver' : dev;
  } else if (ua.contains('Linux')) {
    os = 'Linux';
  }

  // Detect browser (most specific first)
  String browser = '';
  if (ua.contains('Edg/') || ua.contains('EdgA/')) {
    final m = RegExp(r'Edg[A]?/([\d.]+)').firstMatch(ua);
    final v = _majorVersion(m?.group(1));
    browser = 'Edge$v';
  } else if (ua.contains('OPR/') || ua.contains('Opera/')) {
    final m = RegExp(r'OPR/([\d.]+)').firstMatch(ua);
    final v = _majorVersion(m?.group(1));
    browser = 'Opera$v';
  } else if (ua.contains('Firefox/')) {
    final m = RegExp(r'Firefox/([\d.]+)').firstMatch(ua);
    final v = _majorVersion(m?.group(1));
    browser = 'Firefox$v';
  } else if (ua.contains('SamsungBrowser/')) {
    final m = RegExp(r'SamsungBrowser/([\d.]+)').firstMatch(ua);
    final v = _majorVersion(m?.group(1));
    browser = 'Samsung Browser$v';
  } else if (ua.contains('Chrome/')) {
    final m = RegExp(r'Chrome/([\d.]+)').firstMatch(ua);
    final v = _majorVersion(m?.group(1));
    browser = 'Chrome$v';
  } else if (ua.contains('Safari/') && ua.contains('Version/')) {
    final m = RegExp(r'Version/([\d.]+)').firstMatch(ua);
    final v = _majorVersion(m?.group(1));
    browser = 'Safari$v';
  } else if (ua.contains('MSIE') || ua.contains('Trident/')) {
    browser = 'IE';
  }

  if (browser.isEmpty && os.isEmpty) return ua; // fallback: raw string
  if (browser.isEmpty) return os;
  if (os.isEmpty) return browser;
  return '$browser on $os';
}

String _majorVersion(String? ver) {
  if (ver == null || ver.isEmpty) return '';
  final parts = ver.split('.');
  return ' ${parts[0]}';
}
