import 'package:flutter/material.dart';

import '../config.dart';
import '../services.dart';
import '../social/backend.dart';
import 'widgets.dart';

/// Shown on Friends and Trades when you're not signed in (or online features
/// aren't configured in this build).
class SignInPanel extends StatefulWidget {
  final AppServices services;
  const SignInPanel({super.key, required this.services});

  @override
  State<SignInPanel> createState() => _SignInPanelState();
}

class _SignInPanelState extends State<SignInPanel> {
  bool _signUp = false;
  bool _busy = false;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final b = widget.services.backend;
    setState(() => _busy = true);
    try {
      if (_signUp) {
        final signedIn = await b.signUp(email: _email.text, password: _password.text, username: _username.text);
        if (!signedIn && mounted) {
          showMessage(context, 'Check your email to confirm your account, then sign in.');
          setState(() => _signUp = false);
        }
      } else {
        await b.signIn(_email.text, _password.text);
      }
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AppConfig.onlineEnabled) {
      return const EmptyState(
        icon: Icons.cloud_off,
        title: 'Friends and trading are not set up in this build',
        body: 'This build has no Supabase project, so everything stays on this phone. '
            'Follow "Online setup" in the README, then rebuild with SUPABASE_URL and SUPABASE_ANON_KEY.',
      );
    }
    return ListView(padding: const EdgeInsets.all(24), children: [
      Icon(Icons.people, size: 48, color: Theme.of(context).colorScheme.primary),
      const SizedBox(height: 12),
      Text(
        _signUp ? 'Create an account' : 'Sign in to trade with friends',
        style: Theme.of(context).textTheme.titleLarge,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 8),
      const Text(
        'Your collection is backed up, friends can see your Showcase, Up for trade binder and wants, '
        'and the app suggests trades. Everything else stays private.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 20),
      if (_signUp) ...[
        TextField(
          controller: _username,
          decoration: const InputDecoration(
            labelText: 'Username',
            helperText: 'Friends add you by this. 3–20 letters, numbers or _',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
      ],
      TextField(
        controller: _email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _password,
        obscureText: true,
        decoration: InputDecoration(
          labelText: 'Password',
          helperText: _signUp ? 'At least 6 characters' : null,
          border: const OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: _busy ? null : _submit,
        child: _busy
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(_signUp ? 'Create account' : 'Sign in'),
      ),
      TextButton(
        onPressed: _busy ? null : () => setState(() => _signUp = !_signUp),
        child: Text(_signUp ? 'I already have an account' : 'New here? Create an account'),
      ),
    ]);
  }
}
