import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../services/firebase_service.dart';
import '../../services/text_moderation_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  static const Color _navy = Color(0xFF1B2A4A);
  static const Color _lavender = Color(0xFF9B8EC4);
  static const Color _green = Color(0xFF7BBF5E);
  static const Color _bgWhite = Color(0xFFFAF9F7);
  static const Color _inputBg = Color(0xFFFFFFFF);
  static const Color _inputBorder = Color(0xFFE8E5F0);

  final _formKey = GlobalKey<FormState>();
  final _displayNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _agreedToTerms = false;
  bool _showTermsDropdown = false;
  bool _hasViewedTerms = false;
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  String? _displayNameError;
  String? _emailError;

  late AnimationController _animController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _displayNameCtrl.addListener(() {
      if (_displayNameError != null) {
        setState(() => _displayNameError = null);
      }
    });
    _emailCtrl.addListener(() {
      if (_emailError != null) {
        setState(() => _emailError = null);
      }
    });
    _animController = AnimationController(
      duration: const Duration(milliseconds: 700),
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
    _displayNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleEmailRegister() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedToTerms) {
      _showSnackBar('Please agree to Terms of Service and Privacy Policy');
      return;
    }
    setState(() => _isLoading = true);

    final displayName = _displayNameCtrl.text.trim();
    final email = _emailCtrl.text.trim();


    final isNameTaken =
        await FirebaseService.instance.isDisplayNameTaken(displayName);
    if (isNameTaken) {
      if (mounted) {
        setState(() {
          _displayNameError = 'This display name is already taken';
          _isLoading = false;
        });
        _formKey.currentState?.validate();
        _showSnackBar('The display name "$displayName" is already taken. Please choose another.');
      }
      return;
    }


    final isEmailTaken =
        await FirebaseService.instance.isEmailRegistered(email);
    if (isEmailTaken) {
      if (mounted) {
        setState(() {
          _emailError = 'This email address is already registered';
          _isLoading = false;
        });
        _formKey.currentState?.validate();
        _showSnackBar('This email address is already registered. Please log in instead.');
      }
      return;
    }

    try {
      final credential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: email,
        password: _passwordCtrl.text,
      );
      await credential.user?.updateDisplayName(displayName);
      if (credential.user != null) {
        await FirebaseService.instance.ensureUserDoc(
          credential.user!,
          displayName: displayName,
        );
      }
      if (mounted) {
        final curEmail = FirebaseAuth.instance.currentUser?.email;
        if (curEmail == 'admin@example.com') {
          Navigator.pushReplacementNamed(context, '/admin');
        } else {
          Navigator.pushReplacementNamed(context, '/home');
        }
      }
    } on FirebaseAuthException catch (e) {
      if (e.code == 'email-already-in-use') {
        setState(() => _emailError = 'This email address is already registered');
        _formKey.currentState?.validate();
      }
      _showSnackBar(_authErrorMessage(e.code));
    } catch (_) {
      _showSnackBar('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    if (!_agreedToTerms) {
      _showSnackBar('Please agree to Terms of Service and Privacy Policy');
      return;
    }
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
      if (!isNewUser) {
        await FirebaseAuth.instance.signOut();
        await GoogleSignIn().signOut();
        _showSnackBar('This Google account is already registered. Please log in instead.');
        return;
      }

      if (userCredential.user != null) {
        await FirebaseService.instance.ensureUserDoc(
          userCredential.user!,
          displayName: userCredential.user!.displayName,
        );
      }

      if (mounted) {
        final email = FirebaseAuth.instance.currentUser?.email;
        if (email == 'admin@example.com') {
          Navigator.pushReplacementNamed(context, '/admin');
        } else {
          Navigator.pushReplacementNamed(context, '/home');
        }
      }
    } catch (e, stack) {
      debugPrint('Google Sign-In Error: $e');
      debugPrint('$stack');
      _showSnackBar('Google sign-in failed: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isGoogleLoading = false);
    }
  }

  String _authErrorMessage(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'This account is already registered. Please log in instead.';
      case 'weak-password':
        return 'Password must be at least 8 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      default:
        return 'Registration failed. Please try again.';
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
                  'assets/images/registerpagebg.png',
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
                                const SizedBox(height: 24),
                                _buildDisplayNameField(),
                                const SizedBox(height: 16),
                                _buildEmailField(),
                                const SizedBox(height: 16),
                                _buildPasswordField(),
                                const SizedBox(height: 16),
                                _buildConfirmPasswordField(),
                                const SizedBox(height: 14),
                                _buildPasswordHint(),
                                const SizedBox(height: 14),
                                _buildTermsSection(),
                                const SizedBox(height: 20),
                                _buildCreateAccountButton(),
                                const SizedBox(height: 16),
                                _buildDivider(),
                                const SizedBox(height: 16),
                                _buildSocialButtons(),
                                const SizedBox(height: 20),
                                _buildLoginLink(),
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
            child: const Icon(
              Icons.arrow_back,
              color: _navy,
              size: 20,
            ),
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
          'Create your account',
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
            'Join our community and help make streets kinder for cats.',
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

  Widget _buildDisplayNameField() {
    return _buildInputField(
      controller: _displayNameCtrl,
      label: 'Display name',
      hint: 'e.g. Sarah Jones',
      icon: Icons.person_outline,
      helperText: 'Letters only (at least 3 characters). No numbers or symbols.',
      validator: (v) {
        final modErr = TextModerationService.validateDisplayName(v);
        if (modErr != null) return modErr;
        if (_displayNameError != null) return _displayNameError;
        return null;
      },
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
        if (_emailError != null) return _emailError;
        return null;
      },
    );
  }

  Widget _buildPasswordField() {
    return _buildInputField(
      controller: _passwordCtrl,
      label: 'Password',
      hint: 'Create a strong password',
      icon: Icons.lock_outline,
      isObscure: _obscurePassword,
      onToggleObscure: () =>
          setState(() => _obscurePassword = !_obscurePassword),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Password is required';
        if (v.length < 8) return 'Must be at least 8 characters';
        return null;
      },
    );
  }

  Widget _buildConfirmPasswordField() {
    return _buildInputField(
      controller: _confirmPasswordCtrl,
      label: 'Confirm password',
      hint: 'Re-enter your password',
      icon: Icons.lock_outline,
      isObscure: _obscureConfirm,
      onToggleObscure: () =>
          setState(() => _obscureConfirm = !_obscureConfirm),
      validator: (v) {
        if (v == null || v.isEmpty) return 'Please confirm your password';
        if (v != _passwordCtrl.text) return 'Passwords do not match';
        return null;
      },
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    String? helperText,
    bool isObscure = false,
    VoidCallback? onToggleObscure,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
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
                        isObscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
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
        ),
        if (helperText != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              helperText,
              style: GoogleFonts.nunito(
                fontSize: 11.5,
                color: _navy.withValues(alpha: 0.45),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPasswordHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _lavender.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _lavender.withValues(alpha: 0.20), width: 1),
      ),
      child: Row(
        children: [
          Icon(Icons.shield_outlined, color: _lavender, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Use 8+ characters with a mix of letters, numbers and symbols for a stronger account.',
              style: GoogleFonts.nunito(
                fontSize: 12,
                color: _navy.withValues(alpha: 0.65),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTermsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () {
                if (!_hasViewedTerms) {
                  _showSnackBar('Please preview or read the Terms & Privacy Policy first');
                  setState(() {
                    _showTermsDropdown = true;
                    _hasViewedTerms = true;
                  });
                  return;
                }
                setState(() => _agreedToTerms = !_agreedToTerms);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: _agreedToTerms ? _lavender : Colors.transparent,
                  border: Border.all(
                    color: _agreedToTerms ? _lavender : _lavender.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: _agreedToTerms
                    ? const Icon(Icons.check, color: Colors.white, size: 13)
                    : null,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    color: _navy.withValues(alpha: 0.7),
                  ),
                  children: [
                    const TextSpan(text: 'I agree to the '),
                    TextSpan(
                      text: 'Terms of Service',
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        color: _lavender,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationColor: _lavender,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => _showFullTermsModal(context, initialTab: 0),
                    ),
                    const TextSpan(text: ' and '),
                    TextSpan(
                      text: 'Privacy Policy',
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        color: _lavender,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationColor: _lavender,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () => _showFullTermsModal(context, initialTab: 1),
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                setState(() {
                  _showTermsDropdown = !_showTermsDropdown;
                  if (_showTermsDropdown) {
                    _hasViewedTerms = true;
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _lavender.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _showTermsDropdown
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: _lavender,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
        if (_showTermsDropdown) ...[
          const SizedBox(height: 10),
          _buildTermsDropdownPreview(),
        ],
      ],
    );
  }

  Widget _buildTermsDropdownPreview() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _lavender.withValues(alpha: 0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.description_outlined, color: _lavender, size: 16),
              const SizedBox(width: 6),
              Text(
                'Terms & Privacy Summary',
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildPreviewBullet(
            'Community Care',
            'PawWatch connects rescuers and cat lovers. All reports must be accurate, respectful, and intended to help stray cats.',
          ),
          const SizedBox(height: 6),
          _buildPreviewBullet(
            'Location & Privacy',
            'Your location is used solely to alert nearby helpers to cat sightings. Personal contact info is never publicly shared or sold.',
          ),
          const SizedBox(height: 6),
          _buildPreviewBullet(
            'Fair Play & XP',
            'Spam or fake reports will result in account suspension and loss of rescue points.',
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: GestureDetector(
              onTap: () => _showFullTermsModal(context),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Read Full Document',
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _lavender,
                      decoration: TextDecoration.underline,
                      decorationColor: _lavender,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.open_in_new, size: 13, color: _lavender),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewBullet(String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: _green,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.nunito(
                fontSize: 11.5,
                color: _navy.withValues(alpha: 0.75),
                height: 1.35,
              ),
              children: [
                TextSpan(
                  text: '$title: ',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                TextSpan(text: description),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _showFullTermsModal(BuildContext context, {int initialTab = 0}) {
    setState(() => _hasViewedTerms = true);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return DefaultTabController(
          length: 2,
          initialIndex: initialTab,
          child: Container(
            height: MediaQuery.sizeOf(context).height * 0.78,
            decoration: const BoxDecoration(
              color: _bgWhite,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _navy.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 16, 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Legal Information',
                        style: GoogleFonts.nunito(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: _navy, size: 22),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: _lavender.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: TabBar(
                    indicatorSize: TabBarIndicatorSize.tab,
                    indicator: BoxDecoration(
                      color: _navy,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    labelColor: Colors.white,
                    unselectedLabelColor: _navy,
                    labelStyle: GoogleFonts.nunito(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    tabs: const [
                      Tab(text: 'Terms of Service'),
                      Tab(text: 'Privacy Policy'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildTermsFullText(),
                      _buildPrivacyFullText(),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() => _agreedToTerms = true);
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _navy,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'I Understand & Agree',
                        style: GoogleFonts.nunito(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTermsFullText() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLegalSection(
            '1. Acceptance of Terms',
            'By creating an account on PawWatch, you agree to comply with these terms, community guidelines, and all applicable local animal welfare laws.',
          ),
          _buildLegalSection(
            '2. Community Mission & Cat Rescue',
            'PawWatch is dedicated to the safety and welfare of community cats. Users agree to report genuine sightings and avoid providing misleading medical or location data.',
          ),
          _buildLegalSection(
            '3. User Conduct & Content',
            'You may not upload abusive, graphic, or false photos. Harassment of other volunteers or shelters will result in immediate termination of account access.',
          ),
          _buildLegalSection(
            '4. Gamification, XP & Badges',
            'Points and rescue badges are community incentives and possess no monetary value. Tampering with geolocation to claim false rescues is prohibited.',
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyFullText() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLegalSection(
            '1. Information We Collect',
            'We collect your display name, email address, reported sighting photos, and device GPS location when submitting or browsing nearby stray cat alerts.',
          ),
          _buildLegalSection(
            '2. How Location is Used',
            'Location data is solely used to plot sighting pins on the interactive map and notify nearby volunteers when a cat requires attention.',
          ),
          _buildLegalSection(
            '3. Data Protection & Security',
            'Authentication is securely managed by Firebase. We never sell or distribute your personal contact information to third-party advertisers.',
          ),
          _buildLegalSection(
            '4. Account & Data Deletion',
            'You can request complete deletion of your account and associated sighting contributions at any time through your Profile settings.',
          ),
        ],
      ),
    );
  }

  Widget _buildLegalSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: _navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            content,
            style: GoogleFonts.nunito(
              fontSize: 12.5,
              color: _navy.withValues(alpha: 0.75),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreateAccountButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleEmailRegister,
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
                  Text(
                    'Create Account',
                    style: GoogleFonts.nunito(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(Icons.pets, size: 20, color: Colors.white),
                ],
              ),
      ),
    );
  }

  Widget _buildDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: _navy.withValues(alpha: 0.12), thickness: 1)),
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
        Expanded(child: Divider(color: _navy.withValues(alpha: 0.12), thickness: 1)),
      ],
    );
  }

  Widget _buildSocialButtons() {
    return SizedBox(
      width: double.infinity,
      child: _buildSocialButton(
        label: 'Continue with Google',
        icon: const _GoogleIcon(),
        onTap: _isGoogleLoading ? null : _handleGoogleSignIn,
        isLoading: _isGoogleLoading,
      ),
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
        height: 50,
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
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      label,
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _navy,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildLoginLink() {
    return Center(
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.nunito(
            fontSize: 13,
            color: _navy.withValues(alpha: 0.6),
          ),
          children: [
            const TextSpan(text: 'Already have an account? '),
            TextSpan(
              text: 'Log in',
              style: GoogleFonts.nunito(
                fontSize: 13,
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

    final bluePaint = Paint()..color = const Color(0xFF4285F4);
    final redPaint = Paint()..color = const Color(0xFFEA4335);
    final yellowPaint = Paint()..color = const Color(0xFFFBBC05);
    final greenPaint = Paint()..color = const Color(0xFF34A853);

    final strokeW = r * 0.28;

    final outerR = r * 0.85;

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: outerR);

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawArc(rect, -0.26, 1.83, false, bluePaint..style = PaintingStyle.stroke..strokeWidth = strokeW);
    canvas.drawArc(rect, 1.57, 1.57, false, greenPaint..style = PaintingStyle.stroke..strokeWidth = strokeW);
    canvas.drawArc(rect, 3.14, 0.79, false, yellowPaint..style = PaintingStyle.stroke..strokeWidth = strokeW);
    canvas.drawArc(rect, 3.93, 0.5, false, redPaint..style = PaintingStyle.stroke..strokeWidth = strokeW);

    final armPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromLTWH(cx, cy - strokeW * 0.5, r + 2, strokeW),
      armPaint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

