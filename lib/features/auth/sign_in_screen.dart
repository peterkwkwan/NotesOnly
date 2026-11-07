import 'package:flutter/material.dart';

import '../../data/auth.dart';
import '../../theme/theme.dart';
import '../../widgets/show_snack.dart';

/// Signed-out landing — Google only (M2).
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _busy = false;

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await NotesAuth.signInWithGoogle();
      if (!ok && mounted) {
        showPelviSnackBar(context, 'Sign-in cancelled');
      }
    } catch (e) {
      if (mounted) {
        showPelviSnackBar(context, 'Sign-in failed: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = PelviColors.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(PelviSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Text(
                'NotesOnly',
                textAlign: TextAlign.center,
                style: text.titleLarge?.copyWith(color: c.pink700),
              ),
              const SizedBox(height: PelviSpace.sm),
              Text(
                'Sign in with Google to use your practice book.',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: c.inkMuted),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _busy ? null : _signIn,
                child: _busy
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.inkInverse,
                        ),
                      )
                    : const Text('Sign in with Google'),
              ),
              const SizedBox(height: PelviSpace.md),
            ],
          ),
        ),
      ),
    );
  }
}
