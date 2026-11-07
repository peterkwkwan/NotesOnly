import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/auth.dart';
import '../../theme/theme.dart';
import '../../widgets/show_snack.dart';

/// Signed-out landing — Google only. Layout matches Figma `41:117`.
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
      backgroundColor: c.canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Fixed blocks ≈ logo 160 + brand text ~60 + gap 52 + welcome ~140
            // + button block ~82 + legal ~40 (+ padding 76+32 handled separately).
            const used = 160 + 60 + 52 + 140 + 82 + 40.0;
            final free = math.max(
              24.0,
              constraints.maxHeight - 76 - 32 - used,
            );

            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 76, 28, 32),
              child: Column(
                children: [
                  Column(
                    children: [
                      SizedBox(
                        width: 160,
                        height: 160,
                        child: Center(
                          child: Image.asset(
                            'assets/brand/notesonly-monogram.png',
                            width: 95,
                            height: 102.5,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                      const SizedBox(height: PelviSpace.sm),
                      Text(
                        'NotesOnly',
                        textAlign: TextAlign.center,
                        style: text.headlineMedium?.copyWith(
                          fontSize: 32,
                          height: 1,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -1.2,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: PelviSpace.sm),
                      Text(
                        'YOUR PRACTICE, SIMPLIFIED',
                        textAlign: TextAlign.center,
                        style: text.labelMedium?.copyWith(
                          fontSize: 11,
                          height: 1,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.2,
                          color: c.purple700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 52),
                  Column(
                    children: [
                      Text(
                        'A little less admin.\nMore room for care.',
                        textAlign: TextAlign.center,
                        style: text.displayLarge?.copyWith(
                          fontSize: 30,
                          height: 38 / 30,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -0.9,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: PelviSpace.md),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 314),
                        child: Text(
                          'Clinical notes, clients and appointments — together in one calm space.',
                          textAlign: TextAlign.center,
                          style: text.bodyMedium?.copyWith(
                            fontSize: 15,
                            height: 1.65,
                            fontWeight: FontWeight.w400,
                            color: c.inkMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: free * 0.65),
                  Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: OutlinedButton(
                          onPressed: _busy ? null : _signIn,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: c.surface,
                            foregroundColor: c.ink,
                            side: BorderSide(color: c.border),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(PelviRadius.button),
                            ),
                            padding: EdgeInsets.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: _busy
                              ? SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: c.inkMuted,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Image.asset(
                                      'assets/brand/google-g.png',
                                      width: 24,
                                      height: 24,
                                      filterQuality: FilterQuality.high,
                                    ),
                                    const SizedBox(width: 12),
                                    Flexible(
                                      child: Text(
                                        'Continue with Google',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: text.labelLarge?.copyWith(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: c.ink,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: PelviSpace.md),
                      Text(
                        'For new and returning practitioners',
                        textAlign: TextAlign.center,
                        style: text.labelSmall?.copyWith(
                          fontSize: 12,
                          height: 1,
                          fontWeight: FontWeight.w400,
                          color: c.inkMuted,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: free * 0.35),
                  Text.rich(
                    TextSpan(
                      style: text.labelSmall?.copyWith(
                        fontSize: 12,
                        height: 19 / 12,
                        fontWeight: FontWeight.w400,
                        color: c.inkMuted,
                      ),
                      children: [
                        const TextSpan(
                          text: 'By continuing, you agree to our\n',
                        ),
                        TextSpan(
                          text: 'Terms of Service',
                          style: TextStyle(color: c.purple700),
                        ),
                        const TextSpan(text: '  and  '),
                        TextSpan(
                          text: 'Privacy Policy',
                          style: TextStyle(color: c.purple700),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
