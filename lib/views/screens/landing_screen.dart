import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  static const Color _navy = Color(0xFF1B2A4A);
  static const Color _lavender = Color(0xFF9B8EC4);
  static const Color _green = Color(0xFF7BBF5E);
  static const Color _bgWhite = Color(0xFFFAF9F7);

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));

    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgWhite,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      children: [
                        const SizedBox(height: 24),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Image.asset(
                            'assets/images/AppLogo.png',
                            height: 80,
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 6),
                        _buildTagline(),
                        const SizedBox(height: 6),
                        _buildSubtitle(),
                        _buildHeroSection(),
                        const SizedBox(height: 20),
                        _buildFeatureRow(),
                        const SizedBox(height: 28),
                      ],
                    ),
                  ),
                ),
                _buildBottomCTA(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTagline() {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: GoogleFonts.nunito(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
        children: const [
          TextSpan(text: 'Rescue.', style: TextStyle(color: _navy)),
          TextSpan(text: ' '),
          TextSpan(text: 'Report.', style: TextStyle(color: _lavender)),
          TextSpan(text: ' '),
          TextSpan(text: 'Earn.', style: TextStyle(color: _green)),
        ],
      ),
    );
  }

  Widget _buildSubtitle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _lavender.withValues(alpha: 0.2),
                    _lavender.withValues(alpha: 0.8),
                    _lavender.withValues(alpha: 0.2),
                  ],
                ),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Small actions, big impact for stray cats.',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 13.5,
                fontStyle: FontStyle.italic,
                color: _navy.withValues(alpha: 0.75),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroSection() {
    return SizedBox(
      height: 340,
      width: double.infinity,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            top: -160,
            left: 0,
            right: 0,
            child: Image.asset(
              'assets/images/LandingPageBG.png',
              width: double.infinity,
              fit: BoxFit.fitWidth,
            ),
          ),
          Positioned(
            right: 8,
            top: 100,
            child: _buildSpeechBubble(),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeechBubble() {
    const double tailWidth = 16.0;
    return CustomPaint(
      painter: _ComicBubblePainter(tailWidth: tailWidth),
      child: Padding(
        padding: EdgeInsets.fromLTRB(tailWidth + 10, 10, 12, 12),
        child: SizedBox(
          width: 112,
          child: _bubbleLine(
            'We\'re pawsitively\ngrateful for your\nhelp! ~ meow',
          ),
        ),
      ),
    );
  }

  Widget _bubbleLine(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: GoogleFonts.bangers(
        fontSize: 13,
        letterSpacing: 1.0,
        color: _navy,
        height: 1.4,
      ),
    );
  }

  Widget _buildFeatureRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _buildFeatureColumn(
              icon: Icons.location_on_outlined,
              iconColor: _lavender,
              title: 'Report',
              subtitle: 'Spot a cat\nand share',
            ),
          ),
          Container(height: 52, width: 1, color: const Color(0xFFE0DDE8)),
          Expanded(
            child: _buildFeatureColumn(
              icon: Icons.group_outlined,
              iconColor: _green,
              title: 'Respond',
              subtitle: 'Nearby helpers\ntake action',
              titleBold: true,
            ),
          ),
          Container(height: 52, width: 1, color: const Color(0xFFE0DDE8)),
          Expanded(
            child: _buildFeatureColumn(
              icon: Icons.star_border_rounded,
              iconColor: _lavender,
              title: 'Earn',
              subtitle: 'Get XP, level up\nand earn badges',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureColumn({
    required Color iconColor,
    required IconData icon,
    required String title,
    required String subtitle,
    bool titleBold = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 28),
        const SizedBox(height: 8),
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(
            fontSize: 13.5,
            fontWeight: titleBold ? FontWeight.w800 : FontWeight.w700,
            color: _navy,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.nunito(
            fontSize: 11,
            color: _navy.withValues(alpha: 0.55),
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomCTA(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      decoration: BoxDecoration(
        color: _bgWhite,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 58,
            child: ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, '/register'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 20),
                  const Spacer(),
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.pets, size: 18, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Get Started',
                    style: GoogleFonts.nunito(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.arrow_forward, size: 20, color: Colors.white),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          RichText(
            text: TextSpan(
              style: GoogleFonts.nunito(
                fontSize: 13,
                color: _navy.withValues(alpha: 0.6),
              ),
              children: [
                const TextSpan(text: 'Already have an account? '),
                TextSpan(
                  text: 'Log in',
                  style: const TextStyle(
                    color: _lavender,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                    decorationColor: _lavender,
                  ),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => Navigator.pushNamed(context, '/login'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Icon(Icons.pets, size: 16, color: _green.withValues(alpha: 0.8)),
        ],
      ),
    );
  }
}

class _ComicBubblePainter extends CustomPainter {
  const _ComicBubblePainter({required this.tailWidth});

  final double tailWidth;

  @override
  void paint(Canvas canvas, Size size) {
    const double r = 14.0;
    final double tailTopY = size.height - 38.0;
    final double tailBottomY = size.height - 14.0;
    final double tailTipY = size.height - 6.0;

    final path = Path();

    final double left = tailWidth;
    final double right = size.width;
    final double top = 0;
    final double bottom = size.height;

    path.moveTo(left + r, top);
    path.lineTo(right - r, top);
    path.arcToPoint(Offset(right, top + r),
        radius: const Radius.circular(r), clockwise: true);
    path.lineTo(right, bottom - r);
    path.arcToPoint(Offset(right - r, bottom),
        radius: const Radius.circular(r), clockwise: true);
    path.lineTo(left + r, bottom);
    path.arcToPoint(Offset(left, bottom - r),
        radius: const Radius.circular(r), clockwise: true);

    path.lineTo(left, tailBottomY);
    path.lineTo(0, tailTipY);
    path.lineTo(left, tailTopY);

    path.lineTo(left, top + r);
    path.arcToPoint(Offset(left + r, top),
        radius: const Radius.circular(r), clockwise: true);
    path.close();

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x221B2A4A)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _ComicBubblePainter old) =>
      old.tailWidth != tailWidth;
}

