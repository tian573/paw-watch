import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/sighting.dart';
import '../../services/firebase_service.dart';
import '../../services/location_service.dart';
import 'report_form.dart';
import 'sighting_detail.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const Color _navy = Color(0xFF1B2A4A);
  static const Color _lavender = Color(0xFF9B8EC4);
  static const Color _green = Color(0xFF7BBF5E);
  static const Color _bgWhite = Color(0xFFFAF9F7);
  static const Color _urgent = Color(0xFFE53935);
  static const Color _needsHelp = Color(0xFFFF7043);
  static const Color _resolved = Color(0xFF43A047);
  static const Color _cardBg = Color(0xFFFFFFFF);

  int _currentTab = 0;
  String _activeFilter = 'All';
  bool _showNewUserTip = false;
  double? _userLat;
  double? _userLng;
  late AnimationController _arrowAnimController;
  late Animation<double> _arrowBounce;

  @override
  void initState() {
    super.initState();
    _checkFirstTimeUser();
    _fetchUserLocation();
    _arrowAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _arrowBounce = Tween<double>(begin: 0, end: 10).animate(
      CurvedAnimation(parent: _arrowAnimController, curve: Curves.easeInOut),
    );
  }

  Future<void> _fetchUserLocation() async {
    try {
      final res = await LocationService().getCurrentUserLocation();
      if (mounted) {
        setState(() {
          _userLat = res.latitude;
          _userLng = res.longitude;
        });
      }
    } catch (_) {}
  }

  Future<void> _checkFirstTimeUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasSeenTip = prefs.getBool('has_seen_report_tip') ?? false;
      if (!hasSeenTip && mounted) {
        setState(() {
          _showNewUserTip = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _dismissTip() async {
    setState(() => _showNewUserTip = false);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_seen_report_tip', true);
    } catch (_) {}
  }

  @override
  void dispose() {
    _arrowAnimController.dispose();
    super.dispose();
  }

  final List<String> _filters = [
    'All',
    'Trapped',
    'Vulnerable',
    'Injured',
    'Needs Foster',
    'Stray',
    'Resolved',
  ];

  int _categoryPriority(Sighting s) {
    if (s.urgency == 'resolved' || s.status == 'resolved' || s.category == 'Resolved') {
      return 20;
    }
    final isClaimed = s.rescueClaimed;
    final int baseOffset = isClaimed ? 5 : 0;

    switch (s.category) {
      case 'Urgent Rescue':
        return 1 + baseOffset; // Top 1: Trapped (Unclaimed = 1, Claimed = 6)
      case 'Kitten':
        return 2 + baseOffset; // Priority 2: Vulnerable Kitten (Unclaimed = 2, Claimed = 7)
      case 'Injured':
      case 'Needs Vet':
        return 3 + baseOffset; // Priority 3: Injured / Sick (Unclaimed = 3, Claimed = 8)
      case 'Needs Foster':
      case 'Rehomed':
        return 4 + baseOffset; // Priority 4: Needs Foster (Unclaimed = 4, Claimed = 9)
      case 'Stray':
      case 'Feeding Spot':
      case 'Spotted':
      default:
        return 5 + baseOffset; // Priority 5: Stray / Feeding (Unclaimed = 5, Claimed = 10)
    }
  }

  List<Sighting> _filterAndSortSightings(List<Sighting> list) {
    List<Sighting> filtered;
    if (_activeFilter == 'All') {
      filtered = List<Sighting>.from(list);
    } else if (_activeFilter == 'Trapped') {
      filtered = list.where((s) => s.category == 'Urgent Rescue').toList();
    } else if (_activeFilter == 'Vulnerable') {
      filtered = list.where((s) => s.category == 'Kitten').toList();
    } else if (_activeFilter == 'Injured') {
      filtered = list
          .where((s) => s.category == 'Injured' || s.category == 'Needs Vet')
          .toList();
    } else if (_activeFilter == 'Needs Foster') {
      filtered = list
          .where((s) =>
              s.category == 'Needs Foster' || s.category == 'Rehomed')
          .toList();
    } else if (_activeFilter == 'Stray') {
      filtered = list
          .where((s) =>
              s.category == 'Stray' ||
              s.category == 'Feeding Spot' ||
              s.category == 'Spotted')
          .toList();
    } else if (_activeFilter == 'Resolved') {
      filtered = list
          .where((s) =>
              s.category == 'Resolved' ||
              s.status == 'resolved' ||
              s.urgency == 'resolved' ||
              s.status == 'notUrgent')
          .toList();
    } else {
      filtered = List<Sighting>.from(list);
    }

    filtered.sort((a, b) {
      // 1. Prioritize by Category Order
      final pA = _categoryPriority(a);
      final pB = _categoryPriority(b);
      if (pA != pB) {
        return pA.compareTo(pB);
      }

      // 2. Prioritize by Closest Distance to the user
      final distA = a.calculateDistanceInMeters(_userLat, _userLng);
      final distB = b.calculateDistanceInMeters(_userLat, _userLng);
      final distDiff = (distA - distB).abs();
      if (distDiff > 30) {
        return distA.compareTo(distB);
      }

      // 3. Fallback to newest timestamp
      return b.createdAt.compareTo(a.createdAt);
    });

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    return Stack(
      children: [
        Scaffold(
          backgroundColor: _bgWhite,
          body: SafeArea(
            child: IndexedStack(
              index: _currentTab,
              children: [
                _buildHomeTab(),
                _buildPlaceholderTab('Map', Icons.map_outlined),
                const SizedBox.shrink(),
                _buildPlaceholderTab('Notifications', Icons.notifications_outlined),
                _buildPlaceholderTab('Profile', Icons.person_outline),
              ],
            ),
          ),
          floatingActionButton: _buildReportFab(),
          floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
          bottomNavigationBar: _buildBottomNav(),
        ),
        if (_showNewUserTip) _buildSpotlightCoachmark(),
      ],
    );
  }

  Widget _buildHomeTab() {
    return Column(
      children: [
        _buildAppBar(),
        Expanded(
          child: StreamBuilder<List<Sighting>>(
            stream: FirebaseService.instance.streamSightings(),
            builder: (context, snapshot) {
              final allSightings = snapshot.data ?? [];
              final filtered = _filterAndSortSightings(allSightings);

              return CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _buildFilterChips()),
                  if (snapshot.connectionState == ConnectionState.waiting && allSightings.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(
                          child: CircularProgressIndicator(color: _lavender),
                        ),
                      ),
                    )
                  else if (filtered.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 88,
                                height: 88,
                                decoration: BoxDecoration(
                                  color: _lavender.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: _lavender.withValues(alpha: 0.15),
                                      blurRadius: 16,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Image.asset(
                                    'assets/images/LogoReportPage.png',
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 18),
                              Text(
                                _activeFilter == 'All'
                                    ? 'No Cat Sightings Yet 🐾'
                                    : 'No $_activeFilter Sightings 🐾',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.nunito(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: _navy,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: Text(
                                  _activeFilter == 'All'
                                      ? 'All cats around you seem safe, or no reports have been posted yet. Tap below to report a cat in need!'
                                      : 'No reports under "$_activeFilter" right now. Check other filters or post a new sighting.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.nunito(
                                    fontSize: 13,
                                    color: _navy.withValues(alpha: 0.6),
                                    fontWeight: FontWeight.w600,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _lavender,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 22, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  elevation: 2,
                                  shadowColor: _lavender.withValues(alpha: 0.4),
                                ),
                                onPressed: _openReportForm,
                                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                                label: Text(
                                  'Report a Cat',
                                  style: GoogleFonts.nunito(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            if (i >= filtered.length) return null;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _buildSightingCard(filtered[i]),
                            );
                          },
                          childCount: filtered.length,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAppBar() {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName ?? user?.email ?? 'PawWatcher';
    final initials = _getInitials(displayName);

    return Container(
      color: _bgWhite,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _buildNotificationBell(),
          ),
          Center(
            child: _buildPawWatchLogo(),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _buildUserXpWidget(initials),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationBell() {
    return Stack(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _navy.withValues(alpha: 0.07),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(Icons.notifications_outlined, color: _navy, size: 22),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: _lavender,
              shape: BoxShape.circle,
              border: Border.all(color: _bgWhite, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPawWatchLogo() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/images/AppLogo.png',
          height: 38,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 2),
        RichText(
          text: TextSpan(
            style: GoogleFonts.nunito(fontSize: 10.5, fontWeight: FontWeight.w800),
            children: [
              TextSpan(text: 'Rescue.', style: TextStyle(color: _navy)),
              const TextSpan(text: ' '),
              TextSpan(text: 'Report.', style: TextStyle(color: _lavender)),
              const TextSpan(text: ' '),
              TextSpan(text: 'Earn.', style: TextStyle(color: _green)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildUserXpWidget(String initials) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _lavender.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(color: _lavender, width: 2),
              ),
              child: Center(
                child: Text(
                  initials,
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _lavender,
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -4,
              right: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: _lavender,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Lv.4',
                  style: GoogleFonts.nunito(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '640 / 800 XP',
          style: GoogleFonts.nunito(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: _navy.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: 60,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: 640 / 800,
              minHeight: 5,
              backgroundColor: _lavender.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation<Color>(_lavender),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpotlightCoachmark() {
    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: _dismissTip,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.65),
                ),
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              bottom: 95,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: _lavender.withValues(alpha: 0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 16,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _lavender.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.pets,
                                      size: 14, color: _lavender),
                                  const SizedBox(width: 4),
                                  Text(
                                    'New Rescuer Guide',
                                    style: GoogleFonts.nunito(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: _lavender,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: _dismissTip,
                              child: Icon(
                                Icons.close_rounded,
                                size: 20,
                                color: _navy.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Spotted a cat in need? 🐱',
                          style: GoogleFonts.nunito(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tap this plus (+) button below to create a quick rescue report, snap photos, and alert nearby rescuers!',
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            color: _navy.withValues(alpha: 0.65),
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            GestureDetector(
                              onTap: _dismissTip,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: _navy,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Got it, thanks! 👍',
                                  style: GoogleFonts.nunito(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _arrowBounce,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _arrowBounce.value),
                        child: child,
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _lavender,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _lavender.withValues(alpha: 0.7),
                              blurRadius: 16,
                              spreadRadius: 2,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.keyboard_double_arrow_down_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: () {
                    _dismissTip();
                    _openReportForm();
                  },
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _lavender.withValues(alpha: 0.8),
                          blurRadius: 20,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Container(
                      decoration: const BoxDecoration(
                        color: _lavender,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add,
                        color: Colors.white,
                        size: 34,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 0, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            ..._filters.map((filter) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _buildChip(filter),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(String label) {
    final isActive = _activeFilter == label;
    Color chipColor;
    IconData? chipIcon;

    switch (label) {
      case 'Trapped':
        chipColor = const Color(0xFFFF5722);
        chipIcon = Icons.warning_amber_rounded;
        break;
      case 'Vulnerable':
        chipColor = const Color(0xFFE91E63);
        chipIcon = Icons.pets;
        break;
      case 'Injured':
        chipColor = _urgent;
        chipIcon = Icons.healing_outlined;
        break;
      case 'Needs Foster':
        chipColor = const Color(0xFF9C27B0);
        chipIcon = Icons.home_outlined;
        break;
      case 'Stray':
        chipColor = _lavender;
        chipIcon = Icons.restaurant_outlined;
        break;
      case 'Resolved':
        chipColor = _resolved;
        chipIcon = Icons.check_circle_outline;
        break;
      default:
        chipColor = _navy;
        chipIcon = Icons.grid_view_rounded;
    }

    return GestureDetector(
      onTap: () => setState(() => _activeFilter = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7.5),
        decoration: BoxDecoration(
          color: isActive ? chipColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? chipColor : _navy.withValues(alpha: 0.12),
          ),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: chipColor.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: _navy.withValues(alpha: 0.04),
                    blurRadius: 6,
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              chipIcon,
              size: 13,
              color: isActive ? Colors.white : chipColor,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: isActive ? Colors.white : _navy.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSightingCard(Sighting data) {
    return GestureDetector(
      onTap: () => _openSightingDetail(data),
      child: Container(
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _navy.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCardImage(data),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildAvatar(data.initials, data.avatarColor),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data.reporterName,
                                  style: GoogleFonts.nunito(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: _navy,
                                  ),
                                ),
                                Row(
                                  children: [
                                    Text(
                                      data.timeAgo,
                                      style: GoogleFonts.nunito(
                                        fontSize: 11,
                                        color: _navy.withValues(alpha: 0.5),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(Icons.location_on_outlined,
                                        size: 11,
                                        color: _navy.withValues(alpha: 0.4)),
                                    Text(
                                      data.formatDistance(_userLat, _userLng),
                                      style: GoogleFonts.nunito(
                                        fontSize: 11,
                                        color: _navy.withValues(alpha: 0.5),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.more_horiz,
                              color: _navy.withValues(alpha: 0.3), size: 18),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        data.displayTitle,
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        data.description.isNotEmpty ? data.description : 'Cat spotted in the area.',
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          color: _navy.withValues(alpha: 0.6),
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      if (data.isInCare) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF673AB7).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: const Color(0xFF673AB7).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(data.careIcon,
                                  size: 12, color: const Color(0xFF673AB7)),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '${data.careLabel} • with ${data.careTakerName?.isNotEmpty == true ? data.careTakerName : "Rescuer"}',
                                  style: GoogleFonts.nunito(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF673AB7),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else if (data.rescueClaimed && data.urgency != 'resolved') ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: _lavender.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: _lavender.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.directions_run,
                                  size: 12, color: _lavender),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '${data.rescueClaimedByName.isNotEmpty ? data.rescueClaimedByName : "Rescuer"} is on the way',
                                  style: GoogleFonts.nunito(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: _lavender,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      _buildLocationChip(data.displayLocation),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                _buildCategoryTag(data.category),
                const SizedBox(width: 10),
                Icon(Icons.chat_bubble_outline,
                    size: 14, color: _navy.withValues(alpha: 0.4)),
                const SizedBox(width: 4),
                Text(
                  '${data.commentCount}',
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    color: _navy.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                ..._buildActionButtons(data),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildCardImage(Sighting data) {
    final Color statusColor;
    final String statusLabel;
    final IconData statusIcon;

    if (data.status == 'resolved' || data.urgency == 'resolved') {
      statusColor = _resolved;
      statusLabel = 'Resolved';
      statusIcon = Icons.check_circle;
    } else if (data.isInCare) {
      statusColor = const Color(0xFF673AB7);
      statusLabel = data.careLabel;
      statusIcon = data.careIcon;
    } else if (data.rescueClaimed) {
      statusColor = _lavender;
      statusLabel = 'On The Way';
      statusIcon = Icons.directions_run;
    } else if (data.status == 'urgent' || data.urgency == 'urgent') {
      statusColor = _urgent;
      statusLabel = 'Urgent';
      statusIcon = Icons.error;
    } else {
      statusColor = _needsHelp;
      statusLabel = 'Needs Help';
      statusIcon = Icons.pets;
    }

    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(18),
        bottomLeft: Radius.circular(0),
      ),
      child: SizedBox(
        width: 120,
        height: 140,
        child: Stack(
          children: [
            if (data.photoUrls.isNotEmpty)
              Positioned.fill(
                child: data.photoUrls.first.startsWith('http')
                    ? Image.network(
                        data.photoUrls.first,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: _lavender.withValues(alpha: 0.15),
                          child: Center(
                            child: Icon(Icons.pets,
                                size: 40, color: _lavender.withValues(alpha: 0.4)),
                          ),
                        ),
                      )
                    : Image.file(
                        File(data.photoUrls.first),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: _lavender.withValues(alpha: 0.15),
                          child: Center(
                            child: Icon(Icons.pets,
                                size: 40, color: _lavender.withValues(alpha: 0.4)),
                          ),
                        ),
                      ),
              )
            else
              Container(
                color: _lavender.withValues(alpha: 0.15),
                child: Center(
                  child: Icon(Icons.pets,
                      size: 40, color: _lavender.withValues(alpha: 0.4)),
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      statusIcon,
                      size: 10,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      statusLabel,
                      style: GoogleFonts.nunito(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 6,
              right: 6,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image_outlined, size: 10, color: Colors.white),
                    const SizedBox(width: 3),
                    Text(
                      '${data.imageCount}',
                      style: GoogleFonts.nunito(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(String initials, Color color) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Center(
        child: Text(
          initials,
          style: GoogleFonts.nunito(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildLocationChip(String location) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _lavender.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on_outlined,
              size: 11, color: _lavender),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              location,
              style: GoogleFonts.nunito(
                fontSize: 11,
                color: _lavender,
                fontWeight: FontWeight.w700,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTag(String category) {
    IconData icon;
    switch (category) {
      case 'Kitten':
        icon = Icons.pets;
        break;
      case 'Injured':
        icon = Icons.healing_outlined;
        break;
      case 'Needs Foster':
      case 'Rehomed':
        icon = Icons.home_outlined;
        break;
      case 'Needs Vet':
      case 'Vet Visit':
        icon = Icons.medical_services_outlined;
        break;
      case 'Feeding Spot':
        icon = Icons.restaurant_outlined;
        break;
      case 'Urgent Rescue':
        icon = Icons.emergency_outlined;
        break;
      case 'Resolved':
        icon = Icons.check_circle_outline;
        break;
      default:
        icon = Icons.remove_red_eye_outlined;
    }

    final String displayCategory = (category == 'Stray Cat' || category == 'Stray')
        ? 'Stray'
        : (category == 'Urgent Rescue' ? 'Trapped' : category);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: _navy.withValues(alpha: 0.5)),
        const SizedBox(width: 3),
        Text(
          displayCategory,
          style: GoogleFonts.nunito(
            fontSize: 11.5,
            color: _navy.withValues(alpha: 0.6),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  void _openSightingDetail(Sighting data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SightingDetailScreen(sighting: data),
      ),
    );
  }

  List<Widget> _buildActionButtons(Sighting data) {
    final Color outlineColor = data.status == 'urgent'
        ? _urgent
        : (data.status == 'resolved' ? _resolved : _needsHelp);

    return [
      GestureDetector(
        onTap: () => _openSightingDetail(data),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6.5),
          decoration: BoxDecoration(
            border: Border.all(color: outlineColor, width: 1.2),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'View Details',
            style: GoogleFonts.nunito(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: outlineColor,
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildPlaceholderTab(String label, IconData icon) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: _lavender.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Coming soon 🐾',
            style: GoogleFonts.nunito(
              fontSize: 14,
              color: _navy.withValues(alpha: 0.45),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportFab() {
    return GestureDetector(
      onTap: _openReportForm,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          color: _lavender,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _lavender.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 30),
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomAppBar(
      color: Colors.white,
      elevation: 8,
      shadowColor: _navy.withValues(alpha: 0.08),
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      padding: EdgeInsets.zero,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(0, Icons.home_rounded, Icons.home_outlined, 'Home'),
              _buildNavItem(1, Icons.map_rounded, Icons.map_outlined, 'Map'),
              const SizedBox(width: 60),
              _buildNavItemWithBadge(3, Icons.notifications_rounded,
                  Icons.notifications_outlined, 'Notifications'),
              _buildNavItem(
                  4, Icons.person_rounded, Icons.person_outlined, 'Profile'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
      int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final isActive = _currentTab == index;
    return GestureDetector(
      onTap: () => setState(() => _currentTab = index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : inactiveIcon,
              color: isActive ? _lavender : _navy.withValues(alpha: 0.35),
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                color: isActive ? _lavender : _navy.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItemWithBadge(
      int index, IconData activeIcon, IconData inactiveIcon, String label) {
    final isActive = _currentTab == index;
    return GestureDetector(
      onTap: () => setState(() => _currentTab = index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isActive ? activeIcon : inactiveIcon,
                  color: isActive ? _lavender : _navy.withValues(alpha: 0.35),
                  size: 24,
                ),
                Positioned(
                  top: -2,
                  right: -2,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _lavender,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                color: isActive ? _lavender : _navy.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openReportForm() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReportFormScreen()),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts[0].length >= 2) {
      return parts[0].substring(0, 2).toUpperCase();
    }
    return parts[0][0].toUpperCase();
  }
}
