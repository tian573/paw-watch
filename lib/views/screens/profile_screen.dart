import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

  void _showEditProfileSheet(UserProfile profile) {
    final nameCtrl = TextEditingController(text: profile.displayName);
    final bioCtrl = TextEditingController(text: profile.bio);
    final cityCtrl = TextEditingController(text: profile.city);
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
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
                  Text(
                    'Edit Rescuer Profile',
                    style: GoogleFonts.nunito(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 14),
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
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _lavender,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: isSaving
                          ? null
                          : () async {
                              setSheetState(() => isSaving = true);
                              try {
                                await FirebaseService.instance.updateUserProfile(
                                  uid: profile.uid,
                                  displayName: nameCtrl.text.trim(),
                                  city: cityCtrl.text.trim(),
                                  bio: bioCtrl.text.trim(),
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                              } catch (e) {
                                setSheetState(() => isSaving = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Error updating profile: $e')),
                                );
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Sign Out', style: GoogleFonts.nunito(fontWeight: FontWeight.w800, color: _navy)),
        content: Text('Are you sure you want to sign out of PawWatch?', style: GoogleFonts.nunito(color: _navy.withValues(alpha: 0.75))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.nunito(fontWeight: FontWeight.w700, color: _navy)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sign Out', style: GoogleFonts.nunito(fontWeight: FontWeight.w800)),
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
                      _buildTrustTierCard(profile),
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
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          profile.trustTierColor.withValues(alpha: 0.3),
                          profile.trustTierColor,
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        profile.initials,
                        style: GoogleFonts.nunito(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
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
                      'Gamification',
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

  Widget _buildTrustTierCard(UserProfile profile) {
    return GestureDetector(
      onTap: () => _showTrustTierModal(profile),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: profile.trustTierColor.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: _navy.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: profile.trustTierColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(profile.trustTierIcon, color: profile.trustTierColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        profile.trustTierTitle,
                        style: GoogleFonts.nunito(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.verified, size: 16, color: profile.trustTierColor),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    profile.trustTierSubtitle,
                    style: GoogleFonts.nunito(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: _navy.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: _navy.withValues(alpha: 0.35)),
          ],
        ),
      ),
    );
  }

  Widget _buildBadgesSection(UserProfile profile) {
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
              Text(
                'Badges & Achievements',
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _navy,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildBadgeChip('🐾 Street Guardian', Colors.purple.shade400),
              _buildBadgeChip('⭐ Five-Star Caregiver', _gold),
              _buildBadgeChip('⚡ Fast Responder', Colors.orange.shade400),
              _buildBadgeChip('🍲 Community Feeder', _green),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadgeChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: GoogleFonts.nunito(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _buildReviewsSection(UserProfile profile) {
    final reviews = profile.reviews;

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
              const SizedBox(width: 8),
              Text(
                '${reviews.length} reviews',
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _navy.withValues(alpha: 0.4),
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
          else
            ...reviews.map((r) {
              final rName = r['reviewerName']?.toString() ?? 'Reporter';
              final rScore = (r['rating'] is num) ? (r['rating'] as num).toDouble() : 5.0;
              final rComment = r['comment']?.toString() ?? 'Great rescue effort!';
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _bgWhite,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            rName,
                            style: GoogleFonts.nunito(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _navy,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '$rScore ★',
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: _gold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        rComment,
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          color: _navy.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildSignOutBtn() {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: Colors.red.shade400,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        onPressed: _signOut,
        icon: const Icon(Icons.logout_rounded, size: 18),
        label: Text(
          'Sign Out of Account',
          style: GoogleFonts.nunito(
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
