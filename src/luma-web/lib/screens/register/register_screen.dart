import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/user_service.dart';

/// Registration screen for users accepting an invitation.
///
/// Reached via `/join?token=<raw>`. Looks up the invitation metadata,
/// then lets the user set their display name and password before
/// calling [AuthService.register] to create the account.
class RegisterScreen extends StatefulWidget {
  final AuthService auth;
  final UserService userService;
  final String token;

  const RegisterScreen({
    super.key,
    required this.auth,
    required this.userService,
    required this.token,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // Invitation lookup state
  bool _lookingUp = true;
  String? _lookupError;
  String? _invitationId;
  String? _email;
  String? _note;

  // Registration form state
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _submitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _lookupInvite();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _lookupInvite() async {
    if (widget.token.isEmpty) {
      setState(() {
        _lookingUp = false;
        _lookupError = 'No invitation token provided.';
      });
      return;
    }
    try {
      final data = await widget.auth.lookupInvite(widget.token);
      setState(() {
        _lookingUp = false;
        _invitationId = data['invitation_id'] as String?;
        _email = data['email'] as String?;
        _note = data['note'] as String?;
      });
    } catch (e) {
      setState(() {
        _lookingUp = false;
        _lookupError = 'This invitation is invalid or has expired.';
      });
    }
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final password = _passwordController.text;
    if (name.isEmpty || password.isEmpty) return;

    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await widget.auth.register(
        invitationId: _invitationId!,
        email: _email!,
        password: password,
        displayName: name,
      );
      // Load profile/preferences now that we have a session.
      await Future.wait([
        widget.userService.loadProfile(),
        widget.userService.loadPreferences(),
      ]);
      // Router's refreshListenable will redirect to /home automatically.
    } catch (e) {
      setState(() {
        _submitting = false;
        _submitError = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _buildContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);

    if (_lookingUp) {
      return const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Validating invitation…'),
        ],
      );
    }

    if (_lookupError != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.link_off_outlined,
              size: 48, color: theme.colorScheme.error),
          const SizedBox(height: 16),
          Text(
            _lookupError!,
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Create your account',
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        if (_note != null && _note!.isNotEmpty) ...[
          Text(
            _note!,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
        ] else
          const SizedBox(height: 16),
        // Email — read-only, pre-filled from invitation
        TextField(
          readOnly: true,
          decoration: InputDecoration(
            labelText: 'Email',
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest,
          ),
          controller: TextEditingController(text: _email ?? ''),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(
            labelText: 'Display name',
            border: OutlineInputBorder(),
          ),
          textCapitalization: TextCapitalization.words,
          autofocus: true,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordController,
          decoration: InputDecoration(
            labelText: 'Password',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          obscureText: _obscurePassword,
          onSubmitted: (_) => _submit(),
        ),
        if (_submitError != null) ...[
          const SizedBox(height: 8),
          Text(
            _submitError!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create account'),
        ),
      ],
    );
  }
}
