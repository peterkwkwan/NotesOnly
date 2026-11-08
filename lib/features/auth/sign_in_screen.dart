import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/auth.dart';
import '../../features/shell/desktop_chrome.dart';
import '../../theme/theme.dart';
import '../../widgets/show_snack.dart';

/// Signed-out landing — Google only.
/// Narrow (phones / Android): Figma `41:117`. Wide (≥960): Figma `54:46` split.
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
    // Width-only (same breakpoint as desktop shell). Phones stay on mobile
    // layout; avoids kIsWeb so widget-test capture can hit the split.
    final wide = isDesktopShell(context);
    return Scaffold(
      backgroundColor: PelviColors.of(context).canvas,
      body: wide ? _buildDesktop(context) : _buildMobile(context),
    );
  }

  /// Figma `54:46` — marketing left + Google sign-in right.
  Widget _buildDesktop(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = PelviColors.of(context);
    // Figma left panel fill (not in palette — keep local).
    const leftBg = Color(0xFFF8F4F3);

    // Figma 1440: left ~660 / right ~780. Flex keeps split on narrower wide viewports.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 660,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: leftBg,
              border: Border(right: BorderSide(color: c.border)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(64),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Image.asset(
                        'assets/brand/notesonly-monogram.png',
                        width: 32,
                        height: 35,
                        filterQuality: FilterQuality.high,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'NotesOnly',
                        style: text.headlineMedium?.copyWith(
                          fontSize: 26,
                          height: 1,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.9,
                          color: c.ink,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YOUR PRACTICE, SIMPLIFIED',
                        style: text.labelMedium?.copyWith(
                          fontSize: 11,
                          height: 1,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 1.4,
                          color: c.purple700,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'A little less admin.\nMore room for care.',
                        style: text.displayLarge?.copyWith(
                          fontSize: 46,
                          height: 56 / 46,
                          fontWeight: FontWeight.w500,
                          letterSpacing: -1.8,
                          color: c.ink,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 432),
                        child: Text(
                          'Clinical notes, clients and appointments — together in one calm space.',
                          style: text.bodyLarge?.copyWith(
                            fontSize: 16,
                            height: 27 / 16,
                            fontWeight: FontWeight.w400,
                            color: c.inkMuted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 48),
                      Row(
                        children: [
                          Expanded(
                            child: _FeatureTile(
                              icon: Icons.edit_note_outlined,
                              label: 'Clinical notes',
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _FeatureTile(
                              icon: Icons.people_outline,
                              label: 'Clients',
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _FeatureTile(
                              icon: Icons.calendar_today_outlined,
                              label: 'Appointments',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Divider(height: 1, thickness: 1, color: c.border),
                      const SizedBox(height: 24),
                      Text(
                        'A calm space for your practice.',
                        style: text.bodyMedium?.copyWith(
                          fontSize: 13,
                          height: 1,
                          fontWeight: FontWeight.w400,
                          color: c.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          flex: 780,
          child: Padding(
            padding: const EdgeInsets.all(64),
            child: Column(
              children: [
                Expanded(
                  // Figma auth area: centered in the right half.
                  child: Align(
                    alignment: Alignment.center,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Welcome to NotesOnly',
                            textAlign: TextAlign.center,
                            style: text.titleLarge?.copyWith(
                              fontSize: 30,
                              height: 39 / 30,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.9,
                              color: c.ink,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Sign in to your practitioner workspace.',
                            textAlign: TextAlign.center,
                            style: text.bodyMedium?.copyWith(
                              fontSize: 15,
                              height: 25 / 15,
                              fontWeight: FontWeight.w400,
                              color: c.inkMuted,
                            ),
                          ),
                          const SizedBox(height: 32),
                          _GoogleButton(busy: _busy, onPressed: _signIn),
                          const SizedBox(height: 16),
                          Text(
                            'For new and returning practitioners',
                            textAlign: TextAlign.center,
                            style: text.labelSmall?.copyWith(
                              fontSize: 13,
                              height: 21 / 13,
                              fontWeight: FontWeight.w400,
                              color: c.inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Text.rich(
                  TextSpan(
                    style: text.labelSmall?.copyWith(
                      fontSize: 12,
                      height: 20 / 12,
                      fontWeight: FontWeight.w400,
                      color: c.inkMuted,
                    ),
                    children: [
                      const TextSpan(text: 'By continuing, you agree to our\n'),
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
          ),
        ),
      ],
    );
  }

  /// Figma `41:117` — centered mobile gate (unchanged for Android).
  Widget _buildMobile(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = PelviColors.of(context);

    return SafeArea(
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
                    _GoogleButton(
                      busy: _busy,
                      onPressed: _signIn,
                      radius: PelviRadius.button,
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
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = PelviColors.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: c.canvas,
            borderRadius: BorderRadius.circular(PelviRadius.md),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 19, color: c.pink700),
        ),
        const SizedBox(height: 14),
        Text(
          label,
          style: text.labelLarge?.copyWith(
            fontSize: 13,
            height: 1,
            fontWeight: FontWeight.w500,
            color: c.ink,
          ),
        ),
      ],
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({
    required this.busy,
    required this.onPressed,
    this.radius = PelviRadius.sm,
  });

  final bool busy;
  final VoidCallback onPressed;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final c = PelviColors.of(context);
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: OutlinedButton(
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: c.surface,
          foregroundColor: c.ink,
          side: BorderSide(color: c.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radius),
          ),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: busy
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Image.asset(
                      'assets/brand/google-g.png',
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Continue with Google',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelLarge?.copyWith(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
