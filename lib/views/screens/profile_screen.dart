import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/user_profile.dart';
import '../../services/firebase_service.dart';
import 'landing_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final Color _navy = const Color(0xFF1E1B4B);
  final Color _lavender = const Color(0xFF7C6FA8);
  final Color _lavLight = const Color(0xFFF0EDF9);
  final Color _bgWhite = const Color(0xFFFAFAFA);
  final Color _green = const Color(0xFF43A047);
  final Color _gold = const Color(0xFFFFA000);

  Widget _buildAvatarWidget({
    required String? photoUrl,
    required String initials,
    required Color tierColor,
    double size = 68,
    File? localFile,
  }) {
    if (localFile != null) {
      return ClipOval(
        child: Image.file(
          localFile,
          width: size,
          height: size,
          fit: BoxFit.cover,
        ),
      );
    }
    if (photoUrl != null && photoUrl.isNotEmpty) {
      if (photoUrl.startsWith('data:image')) {
        try {
          final commaIdx = photoUrl.indexOf(',');
          final b64 = commaIdx != -1 ? photoUrl.substring(commaIdx + 1) : photoUrl;
          final bytes = base64Decode(b64);
          return ClipOval(
            child: Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallbackAvatar(initials, tierColor, size),
            ),
          );
        } catch (_) {}
      }
      if (photoUrl.startsWith('http://') || photoUrl.startsWith('https://')) {
        return ClipOval(
          child: Image.network(
            photoUrl,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _fallbackAvatar(initials, tierColor, size),
          ),
        );
      }
    }
    return _fallbackAvatar(initials, tierColor, size);
  }

  Widget _fallbackAvatar(String initials, Color tierColor, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            tierColor.withValues(alpha: 0.3),
            tierColor,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: GoogleFonts.nunito(
            fontSize: size * 0.36,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  void _showEditProfileSheet(UserProfile profile) {
    final nameCtrl = TextEditingController(text: profile.displayName);
    final bioCtrl = TextEditingController(text: profile.bio);
    final cityCtrl = TextEditingController(text: profile.city);
    File? selectedPhotoFile;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
          final safeBottom = MediaQuery.paddingOf(ctx).bottom;

          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * 0.88,
                ),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(20, 16, 20, 24 + safeBottom),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: _navy.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          'Edit Rescuer Profile',
                          style: GoogleFonts.nunito(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Avatar with edit photo button
                      Center(
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: profile.trustTierColor.withValues(alpha: 0.35),
                                  width: 2.5,
                                ),
                              ),
                              child: _buildAvatarWidget(
                                photoUrl: profile.photoUrl,
                                initials: profile.initials,
                                tierColor: profile.trustTierColor,
                                size: 84,
                                localFile: selectedPhotoFile,
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: GestureDetector(
                                onTap: () async {
                                  final picker = ImagePicker();
                                  final source = await showModalBottomSheet<ImageSource>(
                                    context: context,
                                    backgroundColor: Colors.transparent,
                                    builder: (bCtx) => Container(
                                      padding: EdgeInsets.fromLTRB(
                                          20, 16, 20, 24 + MediaQuery.paddingOf(bCtx).bottom),
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            BorderRadius.vertical(top: Radius.circular(24)),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 40,
                                            height: 4,
                                            decoration: BoxDecoration(
                                              color: _navy.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(2),
                                            ),
                                          ),
                                          const SizedBox(height: 16),
                                          Text(
                                            'Change Profile Photo',
                                            style: GoogleFonts.nunito(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 16,
                                              color: _navy,
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                          ListTile(
                                            leading: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: _lavLight,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Icon(Icons.camera_alt_rounded,
                                                  color: _lavender, size: 20),
                                            ),
                                            title: Text('Take Photo',
                                                style: GoogleFonts.nunito(
                                                    fontWeight: FontWeight.w700, color: _navy)),
                                            onTap: () => Navigator.pop(bCtx, ImageSource.camera),
                                          ),
                                          ListTile(
                                            leading: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: _lavLight,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Icon(Icons.photo_library_rounded,
                                                  color: _lavender, size: 20),
                                            ),
                                            title: Text('Choose from Gallery',
                                                style: GoogleFonts.nunito(
                                                    fontWeight: FontWeight.w700, color: _navy)),
                                            onTap: () => Navigator.pop(bCtx, ImageSource.gallery),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                  if (source != null) {
                                    final picked = await picker.pickImage(
                                      source: source,
                                      maxWidth: 800,
                                      maxHeight: 800,
                                      imageQuality: 85,
                                    );
                                    if (picked != null) {
                                      setSheetState(
                                          () => selectedPhotoFile = File(picked.path));
                                    }
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(7),
                                  decoration: BoxDecoration(
                                    color: _lavender,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                    boxShadow: [
                                      BoxShadow(
                                        color: _navy.withValues(alpha: 0.15),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(Icons.camera_alt_rounded,
                                      size: 15, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text('Display Name',
                          style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _navy)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: nameCtrl,
                        style: GoogleFonts.nunito(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _navy),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: _lavLight,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('City / Neighborhood',
                          style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _navy)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: cityCtrl,
                        style: GoogleFonts.nunito(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _navy),
                        decoration: InputDecoration(
                          hintText: 'e.g. Jakarta Selatan, Indonesia',
                          filled: true,
                          fillColor: _lavLight,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('Bio / Rescue Motivation',
                          style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _navy)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: bioCtrl,
                        maxLines: 3,
                        style: GoogleFonts.nunito(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _navy),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: _lavLight,
                          contentPadding: const EdgeInsets.all(14),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _lavender,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          onPressed: isSaving
                              ? null
                              : () async {
                                  setSheetState(() => isSaving = true);
                                  try {
                                    String? uploadedPhotoUrl;
                                    if (selectedPhotoFile != null) {
                                      try {
                                        final urls = await FirebaseService.instance
                                            .uploadPhotos(
                                          [selectedPhotoFile!],
                                          'profile_${profile.uid}',
                                        );
                                        if (urls.isNotEmpty) {
                                          uploadedPhotoUrl = urls.first;
                                        }
                                      } catch (uploadErr) {
                                        debugPrint('Photo upload fallback to base64: $uploadErr');
                                        try {
                                          final bytes = await selectedPhotoFile!.readAsBytes();
                                          uploadedPhotoUrl =
                                              'data:image/jpeg;base64,${base64Encode(bytes)}';
                                        } catch (_) {}
                                      }
                                    }

                                    await FirebaseService.instance.updateUserProfile(
                                      uid: profile.uid,
                                      displayName: nameCtrl.text.trim(),
                                      city: cityCtrl.text.trim(),
                                      bio: bioCtrl.text.trim(),
                                      photoUrl: uploadedPhotoUrl ?? profile.photoUrl,
                                    );
                                    if (ctx.mounted) Navigator.pop(ctx);
                                  } catch (e) {
                                    setSheetState(() => isSaving = false);
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Error updating profile: $e')),
                                      );
                                    }
                                  }
                                },
                          child: isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : Text(
                                  'Save Changes',
                                  style: GoogleFonts.nunito(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showTrustTierModal(UserProfile profile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _navy.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.shield_outlined, color: _lavender, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'PawWatch Trust & Safety Tiers',
                    style: GoogleFonts.nunito(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Trust tiers protect animal welfare by ensuring only verified, high-rated volunteers take physical foster custody of vulnerable cats.',
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  color: _navy.withValues(alpha: 0.65),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 18),
              _buildTierStep(
                title: '🟢 Community Member (Level 1)',
                desc: 'Open to all users. Spotting, feeding, status check-ins, and photo updates.',
                isActive: profile.trustTier == TrustTier.community,
                color: _lavender,
              ),
              const SizedBox(height: 12),
              _buildTierStep(
                title: '🐾 Verified Rescuer (Level 2)',
                desc: 'Unlocked with 3+ verified rescues & 4.2+ trust rating. Eligible for "I\'m on my way" physical rescue trips and vet transports.',
                isActive: profile.trustTier == TrustTier.verifiedRescuer,
                color: _green,
              ),
              const SizedBox(height: 12),
              _buildTierStep(
                title: '🏅 Trusted Foster (Level 3)',
                desc: 'Highest safety tier (10+ rescues, 3+ fosters, 4.7+ trust rating). Certified to take vulnerable kittens into in-home custody.',
                isActive: profile.trustTier == TrustTier.trustedFoster,
                color: const Color(0xFF673AB7),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(
                    'Understood',
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTierStep({
    required String title,
    required String desc,
    required bool isActive,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isActive ? color.withValues(alpha: 0.08) : _bgWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? color : _navy.withValues(alpha: 0.1),
          width: isActive ? 1.8 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.nunito(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: isActive ? color : _navy,
                  ),
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'CURRENT TIER',
                    style: GoogleFonts.nunito(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            desc,
            style: GoogleFonts.nunito(
              fontSize: 12,
              color: _navy.withValues(alpha: 0.7),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/signoutpop.png',
              width: 90,
              height: 90,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(
                Icons.logout_rounded,
                size: 64,
                color: Color(0xFFEF5350),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Sign Out',
              style: GoogleFonts.nunito(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Are you sure you want to sign out of PawWatch?',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 14,
                color: _navy.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _navy.withValues(alpha: 0.2)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w700,
                      color: _navy,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF5350),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(
                    'Sign Out',
                    style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirm == true) {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LandingScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? 'anon';

    return StreamBuilder<UserProfile>(
      stream: FirebaseService.instance.streamUserProfile(uid),
      builder: (context, snapshot) {
        final profile = snapshot.data ??
            UserProfile(
              uid: uid,
              displayName: user?.displayName ?? 'PawWatcher',
              email: user?.email ?? '',
              joinedAt: DateTime.now(),
            );

        return Scaffold(
          backgroundColor: _bgWhite,
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    children: [
                      _buildHeader(profile),
                      const SizedBox(height: 16),
                      _buildDualDashboard(profile),
                      const SizedBox(height: 16),
                      _buildBadgesSection(profile),
                      const SizedBox(height: 16),
                      _buildReviewsSection(profile),
                      const SizedBox(height: 20),
                      _buildSignOutBtn(),
                      const SizedBox(height: 90), // Spacing for bottom nav
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(UserProfile profile) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  _buildAvatarWidget(
                    photoUrl: profile.photoUrl,
                    initials: profile.initials,
                    tierColor: profile.trustTierColor,
                    size: 68,
                  ),
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: profile.trustTierColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Icon(
                        profile.trustTierIcon,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            profile.displayName,
                            style: GoogleFonts.nunito(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _navy,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _showEditProfileSheet(profile),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: _lavLight,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.edit_outlined, size: 16, color: _lavender),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 12, color: _navy.withValues(alpha: 0.45)),
                        const SizedBox(width: 3),
                        Text(
                          profile.city,
                          style: GoogleFonts.nunito(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _navy.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: () => _showTrustTierModal(profile),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: profile.trustTierColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: profile.trustTierColor.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(profile.trustTierIcon, size: 12, color: profile.trustTierColor),
                            const SizedBox(width: 4),
                            Text(
                              profile.trustTierTitle,
                              style: GoogleFonts.nunito(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: profile.trustTierColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.chevron_right, size: 14, color: profile.trustTierColor),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (profile.bio.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _bgWhite,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                profile.bio,
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: _navy.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDualDashboard(UserProfile profile) {
    return Row(
      children: [
        // Gamification XP Card
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
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
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _lavender.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.bolt_rounded, size: 16, color: _lavender),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Your Level',
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _lavender,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Level ${profile.level}',
                  style: GoogleFonts.nunito(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: _navy,
                  ),
                ),
                Text(
                  '${profile.totalXp} Total XP',
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _navy.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: profile.levelProgress,
                    minHeight: 6,
                    backgroundColor: _lavLight,
                    valueColor: AlwaysStoppedAnimation<Color>(_lavender),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Trust & Reliability Card
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
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
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _gold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.star_rounded, size: 16, color: _gold),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Trust & Safety',
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: _gold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${profile.trustScore.toStringAsFixed(1)} ★',
                      style: GoogleFonts.nunito(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: _navy,
                      ),
                    ),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${profile.successfulRescues} Rescues',
                          style: GoogleFonts.nunito(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: _green,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '${profile.checkInRate.toStringAsFixed(0)}% Check-in rate',
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _navy.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (profile.trustScore / 5.0).clamp(0.0, 1.0),
                    minHeight: 6,
                    backgroundColor: _lavLight,
                    valueColor: AlwaysStoppedAnimation<Color>(_gold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<AchievementItem> _getAchievements(UserProfile profile) {
    return [
      AchievementItem(
        id: 'street_scout',
        title: 'Street Scout',
        description: 'Reported first stray cat sighting to the community radar',
        icon: Icons.explore_rounded,
        assetPath: 'assets/images/streetscout.png',
        color: const Color(0xFF673AB7),
        isUnlocked: true,
        progressText: 'Completed',
      ),
      AchievementItem(
        id: 'five_star',
        title: 'Five-Star Caregiver',
        description: 'Maintained a high-trust reputation with confirmed reporter reviews',
        icon: Icons.star_rounded,
        assetPath: 'assets/images/fivestarcaregiver.png',
        color: _gold,
        isUnlocked: profile.trustScore >= 4.5,
        progressText: profile.trustScore >= 4.5
            ? 'Completed'
            : '${profile.trustScore.toStringAsFixed(1)} / 5.0 Rating Required',
      ),
      AchievementItem(
        id: 'fast_responder',
        title: 'Fast Responder',
        description: 'Responded and arrived within 15 minutes of an emergency alert',
        icon: Icons.bolt_rounded,
        assetPath: 'assets/images/fastresponder.png',
        color: Colors.orange.shade700,
        isUnlocked: true,
        progressText: 'Completed',
      ),
      AchievementItem(
        id: 'colony_feeder',
        title: 'Colony Feeder',
        description: 'Provided consistent water and feeding check-ins for neighborhood cats',
        icon: Icons.restaurant_rounded,
        assetPath: 'assets/images/colonyfeeder.png',
        color: _green,
        isUnlocked: profile.totalXp >= 100,
        progressText: profile.totalXp >= 100
            ? 'Completed'
            : '${profile.totalXp} / 100 XP Required',
      ),
      AchievementItem(
        id: 'guardian_angel',
        title: 'Guardian Angel',
        description: 'Successfully transported a distressed cat to emergency vet clinic',
        icon: Icons.medical_services_rounded,
        assetPath: 'assets/images/guardianangel.png',
        color: Colors.blue.shade600,
        isUnlocked: profile.successfulRescues >= 1,
        progressText: profile.successfulRescues >= 1
            ? 'Completed'
            : '1 Rescue Required',
      ),
      AchievementItem(
        id: 'warm_haven',
        title: 'Warm Haven Foster',
        description: 'Provided temporary in-home foster custody until adoption handover',
        icon: Icons.home_rounded,
        assetPath: 'assets/images/warmhavenfoster.png',
        color: Colors.purple.shade600,
        isUnlocked: profile.completedFosters >= 1,
        progressText: profile.completedFosters >= 1
            ? 'Completed'
            : '1 Foster Required',
      ),
      AchievementItem(
        id: 'kitten_whisperer',
        title: 'Kitten Whisperer',
        description: 'Nursed and rehabilitated vulnerable newborn or orphaned kittens',
        icon: Icons.pets_rounded,
        assetPath: 'assets/images/kittenwhisperer.png',
        color: Colors.pink.shade400,
        isUnlocked: false,
        progressText: 'Foster Tier Level 3 Required',
      ),
      AchievementItem(
        id: 'night_patrol',
        title: 'Night Patrol',
        description: 'Completed evening welfare check-ins after dark in high-risk zones',
        icon: Icons.nightlight_round,
        assetPath: 'assets/images/nightpatrol.png',
        color: const Color(0xFF3F51B5),
        isUnlocked: false,
        progressText: '5 Night Spotting Reports Required',
      ),
    ];
  }

  Widget _buildAchievementCard(AchievementItem item) {
    final isLocked = !item.isUnlocked;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isLocked
            ? _bgWhite.withValues(alpha: 0.6)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLocked
              ? _navy.withValues(alpha: 0.08)
              : item.color.withValues(alpha: 0.25),
          width: isLocked ? 1.0 : 1.4,
        ),
        boxShadow: isLocked
            ? null
            : [
                BoxShadow(
                  color: item.color.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Title on the top (locked icon removed as lock is on the logo emblem)
          Text(
            item.title,
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: isLocked ? _navy.withValues(alpha: 0.5) : _navy,
            ),
          ),
          const SizedBox(height: 12),

          // 2. Logo / Badge in the center
          Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 66,
                height: 66,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isLocked
                      ? _navy.withValues(alpha: 0.04)
                      : item.color.withValues(alpha: 0.08),
                  border: Border.all(
                    color: isLocked
                        ? _navy.withValues(alpha: 0.12)
                        : item.color.withValues(alpha: 0.35),
                    width: isLocked ? 1.0 : 1.8,
                  ),
                  boxShadow: isLocked
                      ? null
                      : [
                          BoxShadow(
                            color: item.color.withValues(alpha: 0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                ),
                child: Center(
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: isLocked
                            ? [
                                _navy.withValues(alpha: 0.04),
                                _navy.withValues(alpha: 0.10),
                              ]
                            : [
                                item.color.withValues(alpha: 0.18),
                                item.color.withValues(alpha: 0.35),
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: isLocked
                            ? _navy.withValues(alpha: 0.1)
                            : item.color.withValues(alpha: 0.5),
                        width: 1.2,
                      ),
                    ),
                    child: Center(
                      child: item.assetPath != null
                          ? Opacity(
                              opacity: isLocked ? 0.38 : 1.0,
                              child: Image.asset(
                                item.assetPath!,
                                width: 36,
                                height: 36,
                                fit: BoxFit.contain,
                              ),
                            )
                          : Icon(
                              item.icon,
                              size: 26,
                              color: isLocked
                                  ? _navy.withValues(alpha: 0.35)
                                  : item.color,
                            ),
                    ),
                  ),
                ),
              ),
              if (isLocked)
                Positioned(
                  bottom: -2,
                  right: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF90A4AE),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // 3. Small description at the bottom
          Text(
            item.description,
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 12,
              color: isLocked
                  ? _navy.withValues(alpha: 0.5)
                  : _navy.withValues(alpha: 0.72),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            item.isUnlocked ? 'Completed' : (item.progressText ?? 'Locked'),
            style: GoogleFonts.nunito(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: isLocked
                  ? _navy.withValues(alpha: 0.45)
                  : item.color,
            ),
          ),
        ],
      ),
    );
  }

  void _showAllAchievementsModal(UserProfile profile) {
    final achievements = _getAchievements(profile);
    final unlockedCount = achievements.where((a) => a.isUnlocked).length;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(bCtx).height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          24 + MediaQuery.paddingOf(bCtx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _navy.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.military_tech_rounded, color: _gold, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Badges & Achievements',
                        style: GoogleFonts.nunito(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                      Text(
                        '$unlockedCount of ${achievements.length} Unlocked',
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          color: _navy.withValues(alpha: 0.55),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: _navy.withValues(alpha: 0.6),
                  onPressed: () => Navigator.pop(bCtx),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: _navy.withValues(alpha: 0.08)),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                itemCount: achievements.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (ctx, i) {
                  return _buildAchievementCard(achievements[i]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgesSection(UserProfile profile) {
    final achievements = _getAchievements(profile);
    final previewAchievements = achievements.take(3).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
              Icon(Icons.military_tech_outlined, color: _gold, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Badges & Achievements',
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => _showAllAchievementsModal(profile),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View All',
                        style: GoogleFonts.nunito(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF673AB7),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: Color(0xFF673AB7),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...previewAchievements.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildAchievementCard(item),
              )),
        ],
      ),
    );
  }

  void _showAllReviewsModal(UserProfile profile) {
    final reviews = profile.reviews.reversed.toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(bCtx).height * 0.85,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          24 + MediaQuery.paddingOf(bCtx).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _navy.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _lavLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.reviews_outlined, color: _lavender, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'All Reviews & Endorsements',
                        style: GoogleFonts.nunito(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                      Text(
                        '${reviews.length} community reviews • ${profile.trustScore.toStringAsFixed(1)} ★ Trust Rating',
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          color: _navy.withValues(alpha: 0.55),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: _navy.withValues(alpha: 0.6),
                  onPressed: () => Navigator.pop(bCtx),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Divider(height: 1, color: _navy.withValues(alpha: 0.08)),
            const SizedBox(height: 12),
            Expanded(
              child: reviews.isEmpty
                  ? Center(
                      child: Text(
                        'No reviews yet.',
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          color: _navy.withValues(alpha: 0.5),
                        ),
                      ),
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: reviews.length,
                      itemBuilder: (ctx, i) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _buildReviewItem(reviews[i], profileUid: profile.uid),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewItem(Map<String, dynamic> r, {required String profileUid}) {
    final rName = r['reviewerName']?.toString() ?? 'Reporter';
    final rScore = (r['rating'] is num) ? (r['rating'] as num).toDouble() : 5.0;
    final rComment = r['comment']?.toString() ?? 'Great rescue effort!';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bgWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _navy.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _lavLight,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    rName.isNotEmpty ? rName[0].toUpperCase() : '🐾',
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _lavender,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  rName,
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, size: 14, color: _gold),
                    const SizedBox(width: 2),
                    Text(
                      rScore.toStringAsFixed(1),
                      style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: _gold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => _showReportReviewDialog(r, profileUid),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.flag_outlined,
                    size: 15,
                    color: _navy.withValues(alpha: 0.35),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            rComment,
            style: GoogleFonts.nunito(
              fontSize: 12.5,
              color: _navy.withValues(alpha: 0.75),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showReportReviewDialog(
    Map<String, dynamic> review,
    String profileUid,
  ) async {
    final rName = review['reviewerName']?.toString() ?? 'Reporter';
    final rComment = review['comment']?.toString() ?? '';
    final rScore = (review['rating'] is num) ? (review['rating'] as num).toDouble() : 5.0;

    String selectedReason = 'Fake or fraudulent review';
    final detailsCtrl = TextEditingController();
    bool isSubmitting = false;

    final reasons = [
      'Fake or fraudulent review',
      'Unnecessary or irrelevant content',
      'Harassment, abusive or offensive',
      'Incorrect cat rescue details',
      'Spam or advertising',
      'Other',
    ];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final bottomInset = MediaQuery.viewInsetsOf(ctx).bottom;
          final safeBottom = MediaQuery.paddingOf(ctx).bottom;

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottomInset + safeBottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _navy.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.flag_rounded, color: Colors.red.shade600, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Report Review',
                              style: GoogleFonts.nunito(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: _navy,
                              ),
                            ),
                            Text(
                              'Flag suspicious or fake reviews for admin review',
                              style: GoogleFonts.nunito(
                                fontSize: 12,
                                color: _navy.withValues(alpha: 0.55),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: _navy.withValues(alpha: 0.6),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _bgWhite,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _navy.withValues(alpha: 0.06)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              rName,
                              style: GoogleFonts.nunito(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: _navy,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '$rScore ★',
                              style: GoogleFonts.nunito(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: _gold,
                              ),
                            ),
                          ],
                        ),
                        if (rComment.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '"$rComment"',
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: _navy.withValues(alpha: 0.7),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Why are you reporting this review?',
                    style: GoogleFonts.nunito(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...reasons.map((reason) {
                    final isSelected = selectedReason == reason;
                    return GestureDetector(
                      onTap: () => setModalState(() => selectedReason = reason),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF673AB7).withValues(alpha: 0.08)
                              : _bgWhite,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF673AB7)
                                : _navy.withValues(alpha: 0.08),
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_off_rounded,
                              size: 18,
                              color: isSelected
                                  ? const Color(0xFF673AB7)
                                  : _navy.withValues(alpha: 0.35),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                reason,
                                style: GoogleFonts.nunito(
                                  fontSize: 13,
                                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                  color: isSelected ? const Color(0xFF673AB7) : _navy,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 10),
                  Text(
                    'Additional details (optional):',
                    style: GoogleFonts.nunito(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: detailsCtrl,
                    maxLines: 2,
                    style: GoogleFonts.nunito(fontSize: 13, color: _navy),
                    decoration: InputDecoration(
                      hintText: 'Provide any context to help the admin verify...',
                      hintStyle: GoogleFonts.nunito(fontSize: 12.5, color: _navy.withValues(alpha: 0.4)),
                      filled: true,
                      fillColor: _bgWhite,
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _navy.withValues(alpha: 0.1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: _navy.withValues(alpha: 0.1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF673AB7), width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF5350),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              setModalState(() => isSubmitting = true);
                              try {
                                await FirebaseService.instance.flagReview(
                                  targetUserId: profileUid,
                                  reviewerName: rName,
                                  comment: rComment,
                                  rating: rScore,
                                  reason: selectedReason,
                                  details: detailsCtrl.text.trim(),
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Row(
                                        children: [
                                          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Review reported for admin inspection. Thank you!',
                                              style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                        ],
                                      ),
                                      backgroundColor: const Color(0xFF2E7D32),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  );
                                }
                              } catch (e) {
                                setModalState(() => isSubmitting = false);
                                if (ctx.mounted) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(content: Text('Failed to submit report: $e')),
                                  );
                                }
                              }
                            },
                      child: isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              'Submit Report to Admin',
                              style: GoogleFonts.nunito(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildReviewsSection(UserProfile profile) {
    final reviews = profile.reviews;
    final previewReviews = reviews.reversed.take(3).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
              Icon(Icons.reviews_outlined, color: _lavender, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Reviews & Endorsements',
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (reviews.isNotEmpty)
                GestureDetector(
                  onTap: () => _showAllReviewsModal(profile),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'View All',
                          style: GoogleFonts.nunito(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF673AB7),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: Color(0xFF673AB7),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (reviews.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.rate_review_outlined, size: 32, color: _navy.withValues(alpha: 0.2)),
                    const SizedBox(height: 6),
                    Text(
                      'No reporter reviews yet.',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _navy.withValues(alpha: 0.5),
                      ),
                    ),
                    Text(
                      'Complete confirmed rescues to earn trusted endorsements!',
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        color: _navy.withValues(alpha: 0.4),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            ...previewReviews.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildReviewItem(r, profileUid: profile.uid),
            )),
            if (reviews.length > 3) ...[
              const SizedBox(height: 8),
              InkWell(
                onTap: () => _showAllReviewsModal(profile),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3EDFC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'View All',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF673AB7),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 15,
                        color: Color(0xFF673AB7),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildSignOutBtn() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFEF5350),
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: _signOut,
        icon: const Icon(Icons.logout_rounded, size: 20),
        label: Text(
          'Sign Out',
          style: GoogleFonts.nunito(
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class AchievementItem {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final bool isUnlocked;
  final String? progressText;
  final String? assetPath;

  const AchievementItem({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.isUnlocked,
    this.progressText,
    this.assetPath,
  });
}
