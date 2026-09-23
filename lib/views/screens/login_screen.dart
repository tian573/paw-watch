import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  static const Color _navy = Color(0xFF1B2A4A);
  static const Color _lavender = Color(0xFF9B8EC4);
  static const Color _green = Color(0xFF7BBF5E);
  static const Color _bgWhite = Color(0xFFFAF9F7);
  static const Color _inputBg = Color(0xFFFFFFFF);
  static const Color _inputBorder = Color(0xFFE8E5F0);

  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _rememberMe = true;
  bool _isLoading = false;
  bool _isGoogleLoading = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 650),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleEmailLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } on FirebaseAuthException catch (e) {
      _showSnackBar(_authErrorMessage(e.code));
    } catch (_) {
      _showSnackBar('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleLogin() async {
    setState(() => _isGoogleLoading = true);
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        setState(() => _isGoogleLoading = false);
        return;
      }
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);

      final isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;
      if (isNewUser) {
        await FirebaseAuth.instance.signOut();
        await GoogleSignIn().signOut();
        _showSnackBar('No account found for this Google account. Please register first.');
        return;
      }

      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e, stack) {
      debugPrint('Google Login Error: $e');
      debugPrint('$stack');
      _showSnackBar('Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      _showSnackBar('Enter your email address above first');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showSnackBar('Password reset email sent! Check your inbox 📬');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'user-not-found') {
        _showSnackBar('No account found with this email.');
      } else {
        _showSnackBar('Could not send reset email. Please try again.');
      }
    }
  }

  String _authErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email. Sign up first!';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password. Please try again.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many failed attempts. Try again later.';
      default:
        return 'Login failed. Please try again.';
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.nunito(fontWeight: FontWeight.w600),
        ),
        backgroundColor: _navy,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _navigateToHome() {
    Navigator.popUntil(context, (route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _navigateToHome();
        }
      },
      child: Scaffold(
        backgroundColor: _bgWhite,
        body: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.70,
                child: Image.asset(
                  'assets/images/loginbg.png',
                  fit: BoxFit.cover,
                ),
              ),
            ),
            SafeArea(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    children: [
                      _buildTopBar(),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                _buildHeader(),
                                const SizedBox(height: 28),
                                _buildEmailField(),
                                const SizedBox(height: 16),
                                _buildPasswordField(),
                                const SizedBox(height: 14),
                                _buildRememberAndForgot(),
                                const SizedBox(height: 22),
                                _buildLoginButton(),
                                const SizedBox(height: 16),
                                _buildDivider(),
                                const SizedBox(height: 16),
                                _buildGoogleButton(),
                                const SizedBox(height: 22),
                                _buildSignUpLink(),
                                const SizedBox(height: 16),
                                Center(
                                  child: Icon(
                                    Icons.pets,
                                    size: 16,
                                    color: _green.withValues(alpha: 0.8),
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: _navigateToHome,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _navy.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.arrow_back, color: _navy, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset(
          'assets/images/AppLogo.png',
          height: 60,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 6),
        RichText(
          text: TextSpan(
            style: GoogleFonts.nunito(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
            children: const [
              TextSpan(text: 'Rescue.', style: TextStyle(color: _navy)),
              TextSpan(text: ' '),
              TextSpan(text: 'Report.', style: TextStyle(color: _lavender)),
              TextSpan(text: ' '),
              TextSpan(text: 'Earn.', style: TextStyle(color: _green)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Welcome back!',
          style: GoogleFonts.nunito(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: _navy,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: MediaQuery.sizeOf(context).width * 0.55,
          child: Text(
            'Log in to continue helping cats and your community.',
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _navy.withValues(alpha: 0.75),
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmailField() {
    return _buildInputField(
      controller: _emailCtrl,
      label: 'Email',
      hint: 'you@example.com',
      icon: Icons.mail_outline,
      keyboardType: TextInputType.emailAddress,
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Email is required';
        if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,}$').hasMatch(v.trim())) {
          return 'Enter a valid email address';
        }
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return _buildInputField(
      controller: _passwordCtrl,
      label: 'Password',
      hint: 'Enter your password',
      icon: Icons.lock_outline,
      isObscure: _obscurePassword,
      onToggleObscure: () =>
          setState(() => _obscurePassword = !_obscurePassword),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Password is required';
        return null;
      },
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isObscure = false,
    VoidCallback? onToggleObscure,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _inputBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _inputBorder, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextFormField(
        controller: controller,
        obscureText: isObscure,
        keyboardType: keyboardType,
        validator: validator,
        style: GoogleFonts.nunito(
          fontSize: 14,
          color: _navy,
          fontWeight: FontWeight.w600,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.nunito(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _lavender,
          ),
          hintText: hint,
          hintStyle: GoogleFonts.nunito(
            fontSize: 13,
            color: _navy.withValues(alpha: 0.35),
          ),
          prefixIcon: Icon(icon, color: _lavender, size: 20),
          suffixIcon: onToggleObscure != null
              ? IconButton(
                  onPressed: onToggleObscure,
                  icon: Icon(
                    isObscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: _lavender.withValues(alpha: 0.7),
                    size: 20,
                  ),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          errorStyle: GoogleFonts.nunito(
            fontSize: 11,
            color: Colors.redAccent,
          ),
        ),
      ),
    );
  }

  Widget _buildRememberAndForgot() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: () => setState(() => _rememberMe = !_rememberMe),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _rememberMe ? _lavender : Colors.transparent,
                  border: Border.all(
                    color: _rememberMe
                        ? _lavender
                        : _lavender.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: _rememberMe
                    ? const Icon(Icons.check, color: Colors.white, size: 13)
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Remember me',
              style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _navy.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
        GestureDetector(
          onTap: _handleForgotPassword,
          child: Text(
            'Forgot password?',
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _lavender,
              decoration: TextDecoration.underline,
              decorationColor: _lavender,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoginButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleEmailLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          elevation: 0,
          disabledBackgroundColor: _navy.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.pets, size: 20, color: Colors.white),
                  const SizedBox(width: 10),
                  Text(
                    'Log In',
                    style: GoogleFonts.nunito(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(
            child: Divider(color: _navy.withValues(alpha: 0.12), thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'or',
            style: GoogleFonts.nunito(
              fontSize: 13,
              color: _navy.withValues(alpha: 0.45),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
            child: Divider(color: _navy.withValues(alpha: 0.12), thickness: 1)),
      ],
    );
  }

  Widget _buildGoogleButton() {
    return _buildSocialButton(
      label: 'Continue with Google',
      icon: const _GoogleIcon(),
      onTap: _isGoogleLoading ? null : _handleGoogleLogin,
      isLoading: _isGoogleLoading,
    );
  }

  Widget _buildSocialButton({
    required String label,
    required Widget icon,
    VoidCallback? onTap,
    bool isLoading = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _inputBorder, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: _navy.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: isLoading
            ? const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _navy,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSignUpLink() {
    return Center(
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.nunito(
            fontSize: 13,
            color: _navy.withValues(alpha: 0.6),
          ),
          children: [
            const TextSpan(text: "Don't have an account? "),
            TextSpan(
              text: 'Sign up',
              style: GoogleFonts.nunito(
                fontSize: 13,
                color: _lavender,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationColor: _lavender,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () => Navigator.pushNamed(context, '/register'),
            ),
            const TextSpan(text: ' '),
            WidgetSpan(
              child: Icon(Icons.pets, size: 14, color: _green),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoogleIcon extends StatelessWidget {
  const _GoogleIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 20,
      height: 20,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    final double r = size.width / 2;

    final bgPaint = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(cx, cy), r, bgPaint);

    final strokeW = r * 0.28;
    final outerR = r * 0.85;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: outerR);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawArc(
        rect,
        -0.26,
        1.83,
        false,
        Paint()
          ..color = const Color(0xFF4285F4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW);
    canvas.drawArc(
        rect,
        1.57,
        1.57,
        false,
        Paint()
          ..color = const Color(0xFF34A853)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW);
    canvas.drawArc(
        rect,
        3.14,
        0.79,
        false,
        Paint()
          ..color = const Color(0xFFFBBC05)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW);
    canvas.drawArc(
        rect,
        3.93,
        0.5,
        false,
        Paint()
          ..color = const Color(0xFFEA4335)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW);

    canvas.drawRect(
      Rect.fromLTWH(cx, cy - strokeW * 0.5, r + 2, strokeW),
      Paint()
        ..color = const Color(0xFF4285F4)
        ..style = PaintingStyle.fill,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
