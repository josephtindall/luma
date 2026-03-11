import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:web/web.dart' as web;

import '../../services/auth_service.dart';

class RecoveryCodeScreen extends StatefulWidget {
  final AuthService auth;

  const RecoveryCodeScreen({super.key, required this.auth});

  @override
  State<RecoveryCodeScreen> createState() => _RecoveryCodeScreenState();
}

class _RecoveryCodeScreenState extends State<RecoveryCodeScreen> {
  bool _acknowledged = false;
  bool _generatingPdf = false;

  String get _token => widget.auth.pendingRecoveryToken ?? '';

  /// Formats the raw 64-digit token into 16 groups of 4 digits.
  List<String> get _groups {
    final t = _token;
    final groups = <String>[];
    for (int i = 0; i < t.length; i += 4) {
      groups.add(t.substring(i, (i + 4).clamp(0, t.length)));
    }
    return groups;
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: _token));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Recovery code copied to clipboard')),
    );
  }

  Future<void> _downloadPDF() async {
    if (_generatingPdf) return;
    setState(() => _generatingPdf = true);
    try {
      final bytes = await _buildPdf();
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

  Future<Uint8List> _buildPdf() async {
    final groups = _groups;
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(60),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'Luma — Account Recovery Code',
              style: pw.TextStyle(
                  fontSize: 22, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 24),
            pw.Text(
              'This code is the only way to recover your account if you forget '
              'your password. Keep it in a safe place — it cannot be retrieved '
              'from your account if lost.',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.SizedBox(height: 32),
            // 4×4 grid of digit groups
            ...List.generate(4, (row) => pw.Padding(
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
              'Do not share this code with anyone. Luma support will never ask for it.',
              style: const pw.TextStyle(
                  fontSize: 10, color: PdfColors.red900),
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

  void _proceed() {
    if (!_acknowledged) return;
    widget.auth.acknowledgeRecoveryToken();
    // Router redirect will navigate to /home now that token is cleared.
    context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final groups = _groups;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Icon(Icons.shield_outlined,
                    size: 48, color: colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  'Your Recovery Code',
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: colorScheme.onErrorContainer, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This is how you recover your account in case you lose your password. '
                          'Save it somewhere safe — it cannot be retrieved later.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onErrorContainer),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Code + action buttons side by side
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 4×4 grid
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: List.generate(4, (row) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: List.generate(4, (col) {
                              final idx = row * 4 + col;
                              final group =
                                  idx < groups.length ? groups[idx] : '';
                              return Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                      right: col < 3 ? 8 : 0),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                          color: colorScheme.outline),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                      color: colorScheme
                                          .surfaceContainerHighest,
                                    ),
                                    child: Text(
                                      group,
                                      textAlign: TextAlign.center,
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
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
                      ),
                    ),

                    const SizedBox(width: 16),

                    // Action buttons (stacked vertically)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(
                          width: 160,
                          child: OutlinedButton.icon(
                            onPressed: _copyCode,
                            icon: const Icon(Icons.copy, size: 18),
                            label: const Text('Copy Recovery\nCode'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              alignment: Alignment.centerLeft,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: 160,
                          child: OutlinedButton.icon(
                            onPressed: _generatingPdf ? null : _downloadPDF,
                            icon: _generatingPdf
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.download, size: 18),
                            label: const Text('Download\nPDF File'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              alignment: Alignment.centerLeft,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Mandatory acknowledgement checkbox
                InkWell(
                  onTap: () =>
                      setState(() => _acknowledged = !_acknowledged),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _acknowledged,
                          onChanged: (v) => setState(
                              () => _acknowledged = v ?? false),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              'I understand the risks and importance of saving this code '
                              'for resetting my password. Without this code my account '
                              'cannot be recovered.',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _acknowledged ? _proceed : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 32, vertical: 16),
                    ),
                    child: const Text(
                      "Let's get started",
                      style: TextStyle(fontSize: 16),
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
