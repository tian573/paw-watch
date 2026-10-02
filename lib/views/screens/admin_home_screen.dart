import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_profile.dart';
import '../../services/firebase_service.dart';
import 'map_screen.dart';
import 'sighting_detail.dart';
import 'landing_screen.dart';
import '../../models/sighting.dart';
import '../widgets/paw_image.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _PlatformBadge {
  final String title;
  final String description;
  final String requirement;
  final IconData icon;
  final Color color;
  final String? assetPath;

  const _PlatformBadge({
    required this.title,
    required this.description,
    required this.requirement,
    required this.icon,
    required this.color,
    this.assetPath,
  });
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  static const Color _navy = Color(0xFF1B2A4A);
  static const Color _adminPurple = Color(0xFF6C3FC5);
  static const Color _adminPurpleLight = Color(0xFFF3EDFF);
  static const Color _bgWhite = Color(0xFFFAF9F7);
  static const Color _green = Color(0xFF43A047);
  static const Color _red = Color(0xFFE53935);
  static const Color _amber = Color(0xFFFFA000);

  static const List<_PlatformBadge> _platformBadges = [
    _PlatformBadge(
      title: 'Street Scout',
      description: 'Reported first stray cat sighting to the community radar',
      requirement: '1 Community Report',
      icon: Icons.explore_rounded,
      color: Color(0xFF673AB7),
      assetPath: 'assets/images/streetscout.png',
    ),
    _PlatformBadge(
      title: 'Five-Star Caregiver',
      description: 'Maintained a high-trust reputation with confirmed reporter reviews',
      requirement: 'Trust score >= 4.5',
      icon: Icons.star_rounded,
      color: Color(0xFFFFA000),
      assetPath: 'assets/images/fivestarcaregiver.png',
    ),
    _PlatformBadge(
      title: 'Fast Responder',
      description: 'Responded and arrived within 15 minutes of an emergency alert',
      requirement: 'Emergency dispatch response',
      icon: Icons.bolt_rounded,
      color: Color(0xFFE65100),
      assetPath: 'assets/images/fastresponder.png',
    ),
    _PlatformBadge(
      title: 'Colony Feeder',
      description: 'Provided consistent water and feeding check-ins for neighborhood cats',
      requirement: '100+ Total XP',
      icon: Icons.restaurant_rounded,
      color: Color(0xFF43A047),
      assetPath: 'assets/images/colonyfeeder.png',
    ),
    _PlatformBadge(
      title: 'Guardian Angel',
      description: 'Successfully transported a distressed cat to emergency vet clinic',
      requirement: '1+ Verified Rescues',
      icon: Icons.medical_services_rounded,
      color: Color(0xFF1E88E5),
      assetPath: 'assets/images/guardianangel.png',
    ),
    _PlatformBadge(
      title: 'Warm Haven Foster',
      description: 'Provided temporary in-home foster custody until adoption handover',
      requirement: '1+ Completed Fosters',
      icon: Icons.home_rounded,
      color: Color(0xFF8E24AA),
      assetPath: 'assets/images/warmhavenfoster.png',
    ),
    _PlatformBadge(
      title: 'Kitten Whisperer',
      description: 'Nursed and rehabilitated vulnerable newborn or orphaned kittens',
      requirement: 'Foster Tier Level 3',
      icon: Icons.pets_rounded,
      color: Color(0xFFEC407A),
      assetPath: 'assets/images/kittenwhisperer.png',
    ),
    _PlatformBadge(
      title: 'Night Patrol',
      description: 'Completed evening welfare check-ins after dark in high-risk zones',
      requirement: '5 Night Spotting Reports',
      icon: Icons.nightlight_round,
      color: Color(0xFF3F51B5),
      assetPath: 'assets/images/nightpatrol.png',
    ),
  ];

  int _currentTab = 0;
  String _flagFilter = 'all';
  String _flagStatusTab = 'pending';

  final Map<String, Future<Sighting?>> _sightingCache = {};
  final Map<String, Future<Map<String, dynamic>?>> _commentCache = {};

  StreamSubscription<List<Sighting>>? _sightingsSub;
  final Map<String, Sighting> _sightingMap = {};
  final Map<String, String> _commentTextMap = {};

  @override
  void initState() {
    super.initState();

    for (final s in FirebaseService.sampleSightings) {
      _sightingMap[s.id] = s;
    }

    _sightingsSub =
        FirebaseService.instance.streamSightings().listen((sightings) {
      if (mounted) {
        setState(() {
          for (final s in sightings) {
            _sightingMap[s.id] = s;
          }
        });
      }
    });

    FirebaseService.instance.syncMissingUsersFromActivity();
  }

  @override
  void dispose() {
    _sightingsSub?.cancel();
    super.dispose();
  }

  void _ensureCommentLoaded(String sightingId, String commentId) {
    final key = '$sightingId/$commentId';
    if (_commentTextMap.containsKey(key)) return;
    _commentTextMap[key] = '';
    _getCachedComment(sightingId, commentId).then((data) {
      if (data != null && mounted) {
        final text = data['text']?.toString().trim() ??
            data['customNote']?.toString().trim() ??
            data['note']?.toString().trim() ??
            data['message']?.toString().trim() ??
            '';
        if (text.isNotEmpty) {
          setState(() {
            _commentTextMap[key] = text;
          });
        }
      }
    });
  }

  void _ensureSightingLoaded(String sightingId) {
    final sId = sightingId.trim();
    if (sId.isEmpty || _sightingMap.containsKey(sId)) return;
    _getCachedSighting(sId).then((s) {
      if (s != null && mounted) {
        setState(() {
          _sightingMap[sId] = s;
        });
      }
    });
  }

  String _resolveFlagType(Map<String, dynamic> f) {
    final raw = (f['type']?.toString() ?? '').toLowerCase().trim();
    if (raw == 'comment' || raw == 'comment_flag') return 'comment';
    if (raw == 'sighting' || raw == 'sighting_flag') return 'sighting';
    if (raw == 'review' || raw == 'review_flag') return 'review';
    if (raw == 'chat_message' || raw == 'chat' || raw == 'chat_flag') return 'chat_message';


    if (f['commentId'] != null && f['commentId'].toString().trim().isNotEmpty) {
      return 'comment';
    }
    if (f['sightingId'] != null && f['sightingId'].toString().trim().isNotEmpty) {
      return 'sighting';
    }
    if (f['chatId'] != null && f['chatId'].toString().trim().isNotEmpty) {
      return 'chat_message';
    }
    if (f['targetUserId'] != null && f['targetUserId'].toString().trim().isNotEmpty) {
      return 'review';
    }
    return raw.isNotEmpty ? raw : 'unknown';
  }

  Future<Sighting?> _getCachedSighting(String sightingId) {
    final trimmedId = sightingId.trim();
    if (trimmedId.isEmpty) return Future.value(null);

    return _sightingCache.putIfAbsent(trimmedId, () async {

      try {
        final doc = await FirebaseFirestore.instance
            .collection('sightings')
            .doc(trimmedId)
            .get()
            .timeout(const Duration(seconds: 3));
        if (doc.exists && doc.data() != null) {
          return Sighting.fromFirestore(doc);
        }
      } catch (e) {
        debugPrint('Error loading sighting $trimmedId: $e');
      }


      try {
        final sample = FirebaseService.sampleSightings
            .where((s) => s.id == trimmedId)
            .firstOrNull;
        if (sample != null) return sample;
      } catch (_) {}

      return null;
    });
  }

  Future<Map<String, dynamic>?> _getCachedComment(
      String sightingId, String commentId) {
    final sId = sightingId.trim();
    final cId = commentId.trim();
    if (sId.isEmpty || cId.isEmpty) return Future.value(null);

    final key = '$sId/$cId';
    return _commentCache.putIfAbsent(key, () async {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('sightings')
            .doc(sId)
            .collection('updates')
            .doc(cId)
            .get()
            .timeout(const Duration(seconds: 3));
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          data['id'] = doc.id;
          return data;
        }
      } catch (_) {}

      try {
        final doc = await FirebaseFirestore.instance
            .collection('sightings')
            .doc(sId)
            .collection('comments')
            .doc(cId)
            .get()
            .timeout(const Duration(seconds: 3));
        if (doc.exists && doc.data() != null) {
          final data = doc.data()!;
          data['id'] = doc.id;
          return data;
        }
      } catch (e) {
        debugPrint('Error loading comment $cId: $e');
      }
      return null;
    });
  }

  bool _isFlagOlderThan30Days(dynamic ts) {
    if (ts == null) return false;
    DateTime? dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else if (ts is DateTime) {
      dt = ts;
    } else if (ts is String) {
      dt = DateTime.tryParse(ts);
    }
    if (dt == null) return false;
    return DateTime.now().difference(dt).inDays >= 30;
  }

  void _confirmClearResolvedFlags() {
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.delete_sweep_rounded, color: _red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Clear Resolved History',
                style: GoogleFonts.nunito(fontWeight: FontWeight.w900, color: _navy),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete all resolved and dismissed flags from history? This will permanently remove them from database storage to free up space.',
          style: GoogleFonts.nunito(color: _navy.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: Text('Cancel',
                style: GoogleFonts.nunito(color: _navy, fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(dCtx);
              final count = await FirebaseService.instance.clearResolvedFlags();
              _snack('Cleared $count resolved items from history ✓');
            },
            child: Text('Clear All',
                style: GoogleFonts.nunito(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic ts) {
    if (ts == null) return '';
    DateTime dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else if (ts is DateTime) {
      dt = ts;
    } else {
      return '';
    }
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    return Scaffold(
      backgroundColor: _bgWhite,
      body: SafeArea(
        child: IndexedStack(
          index: _currentTab,
          children: [
            _buildDashboardTab(),
            MapScreen(
              onNotificationTap: () => setState(() => _currentTab = 0),
              onProfileTap: () => setState(() => _currentTab = 4),
              isAdmin: true,
            ),
            const SizedBox.shrink(),
            _buildUsersTab(),
            _buildAdminProfileTab(),
          ],
        ),
      ),
      floatingActionButton: _buildAnnouncementFab(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: _buildBottomNav(),
    );
  }


  Widget _buildDashboardTab() {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          _buildAdminAppBar('Dashboard'),

          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF6C3FC5), Color(0xFF9B6FE8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: _adminPurple.withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: FutureBuilder<List<int>>(
              future: Future.wait([
                FirebaseService.instance.getUserCount(),
                FirebaseService.instance.getSightingCount(),
                FirebaseService.instance.getFlagCount(),
              ]),
              builder: (context, snapshot) {
                final counts = snapshot.data ?? [0, 0, 0];
                return Row(
                  children: [
                    _buildStatChip(Icons.people_rounded, '${counts[0]}', 'Users'),
                    const SizedBox(width: 10),
                    _buildStatChip(Icons.pets_rounded, '${counts[1]}', 'Reports'),
                    const SizedBox(width: 10),
                    _buildStatChip(Icons.flag_rounded, '${counts[2]}', 'Flags'),
                  ],
                );
              },
            ),
          ),

          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: _navy.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              indicator: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: _navy.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: _adminPurple,
              unselectedLabelColor: _navy.withValues(alpha: 0.5),
              labelStyle: GoogleFonts.nunito(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
              unselectedLabelStyle: GoogleFonts.nunito(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              dividerColor: Colors.transparent,
              tabs: [
                Tab(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: FirebaseService.instance.streamAllFlags(),
                    builder: (context, snap) {
                      final pending = (snap.data ?? [])
                          .where((f) => (f['status'] ?? 'pending') == 'pending')
                          .length;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Flagged'),
                          if (pending > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: _red,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$pending',
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
                Tab(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: FirebaseService.instance.streamAllClinicSuggestions(),
                    builder: (context, snap) {
                      final pending = (snap.data ?? [])
                          .where((c) => (c['status'] ?? 'pending') == 'pending')
                          .length;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Clinics'),
                          if (pending > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: _amber,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '$pending',
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ),
                const Tab(text: 'Announcements'),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: TabBarView(
              children: [
                _buildFlaggedItemsTab(),
                _buildClinicRequestsTab(),
                _buildAnnouncementsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(height: 2),
            Text(
              value,
              style: GoogleFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildUsersTab() {
    return Column(
      children: [
        _buildAdminAppBar(
          'User Management',
          actions: [
            IconButton(
              icon: const Icon(Icons.person_add_rounded, color: _adminPurple),
              tooltip: 'Add / Link User',
              onPressed: () => _showAddUserDialog(context),
            ),
            IconButton(
              icon: const Icon(Icons.sync_rounded, color: _adminPurple),
              tooltip: 'Sync Users from Activity',
              onPressed: () async {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Syncing registered and active users...'),
                    duration: Duration(seconds: 1),
                  ),
                );
                await FirebaseService.instance.syncMissingUsersFromActivity();
              },
            ),
          ],
        ),
        Expanded(
          child: StreamBuilder<List<UserProfile>>(
            stream: FirebaseService.instance.streamAllUsers(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(
                    color: _adminPurple,
                    strokeWidth: 2.5,
                  ),
                );
              }
              final users = snapshot.data ?? [];
              if (users.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.people_outline_rounded,
                          size: 60, color: _navy.withValues(alpha: 0.15)),
                      const SizedBox(height: 12),
                      Text(
                        'No users found',
                        style: GoogleFonts.nunito(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _navy.withValues(alpha: 0.3),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: users.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final u = users[index];
                  return _buildUserCard(u);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  void _showAddUserDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String selectedRole = 'user';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            'Add / Link User',
            style: GoogleFonts.nunito(fontWeight: FontWeight.w900, color: _navy),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Full Name / Display Name',
                  hintText: 'e.g. Sarah Jones',
                  prefixIcon: Icon(Icons.badge_rounded, color: _adminPurple),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  hintText: 'e.g. sarahjones@gmail.com',
                  prefixIcon: Icon(Icons.email_rounded, color: _adminPurple),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedRole,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'user', child: Text('Community User')),
                  DropdownMenuItem(value: 'admin', child: Text('Administrator')),
                ],
                onChanged: (val) => setDlgState(() => selectedRole = val ?? 'user'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _adminPurple,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final email = emailCtrl.text.trim();
                final messenger = ScaffoldMessenger.of(context);
                if (name.isEmpty || email.isEmpty) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Please enter both name and email')),
                  );
                  return;
                }
                final isNameTaken =
                    await FirebaseService.instance.isDisplayNameTaken(name);
                if (isNameTaken) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('The display name "$name" is already taken')),
                  );
                  return;
                }
                final isEmailTaken =
                    await FirebaseService.instance.isEmailRegistered(email);
                if (isEmailTaken) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('The email "$email" is already registered')),
                  );
                  return;
                }
                if (ctx.mounted) Navigator.pop(ctx);
                await FirebaseService.instance.adminAddUser(
                  displayName: name,
                  email: email,
                  role: selectedRole,
                );
                if (mounted) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('User "$name" registered in management! 🎉')),
                  );
                }
              },
              child: const Text('Add User'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserCard(UserProfile u) {
    final statusColor = u.isBanned
        ? _red
        : u.isSuspended
            ? _amber
            : _green;
    final statusLabel = u.isBanned
        ? 'BANNED'
        : u.isSuspended
            ? 'SUSPENDED'
            : 'ACTIVE';

    return GestureDetector(
      onTap: () => _showUserDetailSheet(u),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _navy.withValues(alpha: 0.06)),
          boxShadow: [
            BoxShadow(
              color: _navy.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [

            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: u.trustTierColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: u.trustTierColor, width: 2),
              ),
              child: u.isAdmin
                  ? ClipOval(
                      child: Image.asset(
                        'assets/images/admin.png',
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Center(
                          child: Text(
                            u.initials,
                            style: GoogleFonts.nunito(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: u.trustTierColor,
                            ),
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        u.initials,
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: u.trustTierColor,
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    u.displayName,
                    style: GoogleFonts.nunito(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    u.email,
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _navy.withValues(alpha: 0.5),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusLabel,
                style: GoogleFonts.nunito(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: statusColor,
                ),
              ),
            ),
            const SizedBox(width: 4),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: _adminPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                u.isMaxLevel ? 'Lv.MAX' : 'Lv.${u.level}',
                style: GoogleFonts.nunito(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: _adminPurple,
                ),
              ),
            ),
            if (u.isBanned) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    color: _red, size: 20),
                tooltip: 'Remove from User Management',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () async {
                  final confirm = await _confirmAction(
                    'Remove ${u.displayName}?',
                    'This will remove this banned user from User Management to free up space.',
                  );
                  if (confirm == true) {
                    await FirebaseService.instance.deleteUserDocument(u.uid);
                    _snack('${u.displayName} removed from User Management.');
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showUserDetailSheet(UserProfile u) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.sizeOf(ctx).height * 0.75,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          bottom: true,
          child: StatefulBuilder(
            builder: (ctx, setSheetState) => Column(
            children: [

              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _navy.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: u.trustTierColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: u.trustTierColor, width: 2.5),
                ),
                child: u.isAdmin
                    ? ClipOval(
                        child: Image.asset(
                          'assets/images/admin.png',
                          width: 70,
                          height: 70,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Center(
                            child: Text(
                              u.initials,
                              style: GoogleFonts.nunito(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: u.trustTierColor,
                              ),
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          u.initials,
                          style: GoogleFonts.nunito(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: u.trustTierColor,
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 10),
              Text(
                u.displayName,
                style: GoogleFonts.nunito(
                    fontSize: 20, fontWeight: FontWeight.w900, color: _navy),
              ),
              Text(
                u.email,
                style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _navy.withValues(alpha: 0.5)),
              ),
              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildUserStat('Level', u.isMaxLevel ? '${u.level} (MAX)' : '${u.level}'),
                    _buildUserStat('XP', '${u.totalXp}'),
                    _buildUserStat('Rescues', '${u.totalRescues}'),
                    _buildUserStat('Trust', u.trustScore.toStringAsFixed(1)),
                    _buildUserStat('Fosters', '${u.completedFosters}'),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildUserStat('Tier', u.trustTierTitle),
                    _buildUserStat('Flags', '${u.flagCount}'),
                    _buildUserStat('Check-in', '${u.checkInRate.toStringAsFixed(0)}%'),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Badges',
                      style: GoogleFonts.nunito(
                          fontSize: 13, fontWeight: FontWeight.w800, color: _navy),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: u.badges.map((b) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: _adminPurpleLight,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              b,
                              style: GoogleFonts.nunito(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _adminPurple),
                            ),
                          )).toList(),
                    ),
                  ],
                ),
              ),
              const Spacer(),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    if (!u.isBanned)
                      _buildAdminActionButton(
                        icon: Icons.block_rounded,
                        label: 'Ban User',
                        color: _red,
                        onTap: () async {
                          final confirm = await _confirmAction(
                              'Ban ${u.displayName}?',
                              'This will prevent the user from accessing PawWatch.');
                          if (confirm == true) {
                            await FirebaseService.instance
                                .banUser(u.uid, reason: 'Admin ban');
                            if (ctx.mounted) Navigator.pop(ctx);
                            _snack('${u.displayName} has been banned.');
                          }
                        },
                      ),
                    if (u.isBanned) ...[
                      _buildAdminActionButton(
                        icon: Icons.lock_open_rounded,
                        label: 'Unban User',
                        color: _green,
                        onTap: () async {
                          await FirebaseService.instance.unbanUser(u.uid);
                          if (ctx.mounted) Navigator.pop(ctx);
                          _snack('${u.displayName} has been unbanned.');
                        },
                      ),
                      const SizedBox(height: 8),
                      _buildAdminActionButton(
                        icon: Icons.person_remove_rounded,
                        label: 'Remove from User Management',
                        color: _red,
                        onTap: () async {
                          final confirm = await _confirmAction(
                              'Remove ${u.displayName}?',
                              'This will permanently remove this banned user from User Management to free up space.');
                          if (confirm == true) {
                            await FirebaseService.instance
                                .deleteUserDocument(u.uid);
                            if (ctx.mounted) Navigator.pop(ctx);
                            _snack(
                                '${u.displayName} removed from User Management.');
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (!u.isSuspended && !u.isBanned)
                      _buildAdminActionButton(
                        icon: Icons.pause_circle_rounded,
                        label: 'Suspend User (7 days)',
                        color: _amber,
                        onTap: () async {
                          final confirm = await _confirmAction(
                              'Suspend ${u.displayName}?',
                              'The user will be suspended for 7 days.');
                          if (confirm == true) {
                            await FirebaseService.instance
                                .suspendUser(u.uid, reason: 'Admin suspension', days: 7);
                            if (ctx.mounted) Navigator.pop(ctx);
                            _snack('${u.displayName} has been suspended for 7 days.');
                          }
                        },
                      ),
                    if (u.isSuspended)
                      _buildAdminActionButton(
                        icon: Icons.play_circle_rounded,
                        label: 'Unsuspend User',
                        color: _green,
                        onTap: () async {
                          await FirebaseService.instance.unsuspendUser(u.uid);
                          if (ctx.mounted) Navigator.pop(ctx);
                          _snack('${u.displayName} has been unsuspended.');
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildUserStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.nunito(
              fontSize: 14, fontWeight: FontWeight.w900, color: _navy),
        ),
        Text(
          label,
          style: GoogleFonts.nunito(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _navy.withValues(alpha: 0.5)),
        ),
      ],
    );
  }

  Widget _buildAdminActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.nunito(
                  fontSize: 14, fontWeight: FontWeight.w800, color: color),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildAdminProfileTab() {
    final user = FirebaseAuth.instance.currentUser;

    return Column(
      children: [
        _buildAdminAppBar('Admin Profile'),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6C3FC5), Color(0xFF8B5CF6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: _adminPurple.withValues(alpha: 0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.8),
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/images/admin.png',
                            width: 76,
                            height: 76,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: Colors.white.withValues(alpha: 0.2),
                              child: const Icon(
                                Icons.admin_panel_settings_rounded,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        user?.displayName ?? 'PawWatch Admin',
                        style: GoogleFonts.nunito(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        user?.email ?? 'admin@example.com',
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '🛡️ Administrator',
                          style: GoogleFonts.nunito(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),


                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _navy.withValues(alpha: 0.06)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _amber.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.emoji_events_rounded,
                                color: _amber, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Badges & Achievements',
                                  style: GoogleFonts.nunito(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: _navy,
                                  ),
                                ),
                                Text(
                                  'Platform achievements & automated rules',
                                  style: GoogleFonts.nunito(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: _navy.withValues(alpha: 0.45),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _adminPurple.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${_platformBadges.length} Active',
                              style: GoogleFonts.nunito(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: _adminPurple,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ..._platformBadges
                          .map((b) => _buildPlatformBadgeCard(b)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),


                GestureDetector(
                  onTap: () async {
                    final confirm = await _confirmAction(
                        'Sign Out?', 'You will be logged out of the admin panel.');
                    if (confirm == true) {
                      await FirebaseAuth.instance.signOut();
                      if (mounted) {
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const LandingScreen()),
                          (route) => false,
                        );
                      }
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _red.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout_rounded, color: _red, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Sign Out',
                          style: GoogleFonts.nunito(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: _red),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPlatformBadgeCard(_PlatformBadge badge) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bgWhite,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _navy.withValues(alpha: 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: badge.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: badge.assetPath != null
                  ? Image.asset(
                      badge.assetPath!,
                      width: 28,
                      height: 28,
                      fit: BoxFit.contain,
                      errorBuilder: (ctx, err, stack) =>
                          Icon(badge.icon, color: badge.color, size: 22),
                    )
                  : Icon(badge.icon, color: badge.color, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        badge.title,
                        style: GoogleFonts.nunito(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: badge.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'AUTOMATED',
                        style: GoogleFonts.nunito(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: badge.color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  badge.description,
                  style: GoogleFonts.nunito(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _navy.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Icon(Icons.rule_rounded,
                        size: 13, color: _navy.withValues(alpha: 0.45)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Rule: ${badge.requirement}',
                        style: GoogleFonts.nunito(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: _navy.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildAdminAppBar(String title, {List<Widget>? actions}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _bgWhite,
        border: Border(
          bottom: BorderSide(color: _navy.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: _adminPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/admin.png',
                width: 28,
                height: 28,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  Icons.admin_panel_settings_rounded,
                  color: _adminPurple,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.nunito(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: _navy,
              ),
            ),
          ),
          ...?actions,
        ],
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
              _buildNavItem(0, Icons.dashboard_rounded,
                  Icons.dashboard_outlined, 'Dashboard'),
              _buildNavItem(
                  1, Icons.map_rounded, Icons.map_outlined, 'Map'),
              const SizedBox(width: 60),
              _buildNavItem(
                  3, Icons.forum_rounded, Icons.forum_outlined, 'Users'),
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
              color: isActive
                  ? _adminPurple
                  : _navy.withValues(alpha: 0.35),
              size: 24,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                color: isActive
                    ? _adminPurple
                    : _navy.withValues(alpha: 0.35),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildAnnouncementFab() {
    return GestureDetector(
      onTap: _showAnnouncementSheet,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6C3FC5), Color(0xFF9B6FE8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _adminPurple.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Icon(Icons.add_rounded, color: Colors.white, size: 32),
      ),
    );
  }


  void _showAnnouncementSheet() {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: false,
              bottom: true,
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
                const SizedBox(height: 20),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _amber.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.campaign_rounded,
                          color: _amber, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'New Announcement',
                      style: GoogleFonts.nunito(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: _navy,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: titleCtrl,
                  style: GoogleFonts.nunito(
                      fontSize: 14, fontWeight: FontWeight.w700),
                  decoration: InputDecoration(
                    labelText: 'Announcement Title *',
                    labelStyle: GoogleFonts.nunito(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: _adminPurple, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: bodyCtrl,
                  maxLines: 4,
                  style: GoogleFonts.nunito(
                      fontSize: 13, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    labelText: 'Message Body *',
                    labelStyle: GoogleFonts.nunito(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: _adminPurple, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                GestureDetector(
                  onTap: isSubmitting
                      ? null
                      : () async {
                          if (titleCtrl.text.trim().isEmpty ||
                              bodyCtrl.text.trim().isEmpty) {
                            _snack('Please fill in both title and body.');
                            return;
                          }
                          setSheetState(() => isSubmitting = true);
                          try {
                            await FirebaseService.instance
                                .createAnnouncement(
                              title: titleCtrl.text,
                              body: bodyCtrl.text,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            _snack(
                                '📢 Announcement published successfully!');
                          } catch (e) {
                            setSheetState(() => isSubmitting = false);
                            _snack('Failed: $e');
                          }
                        },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF6C3FC5), Color(0xFF9B6FE8)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              '📢 Publish Announcement',
                              style: GoogleFonts.nunito(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }


  Widget _buildFlaggedItemsTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: FirebaseService.instance.streamAllFlags(),
      builder: (context, snapshot) {
        final flags = snapshot.data ?? [];
        if (flags.isEmpty) {
          return _buildEmptyTab(Icons.flag_rounded, 'No flagged items');
        }

        final pendingFlags = flags
            .where((f) => (f['status'] ?? 'pending') == 'pending')
            .toList();

        final allResolvedFlags = flags
            .where((f) => f['status'] == 'resolved' || f['status'] == 'dismissed')
            .toList();

        final resolvedFlags = allResolvedFlags.where((f) {
          final resolvedTs = f['resolvedAt'] ?? f['createdAt'];
          return !_isFlagOlderThan30Days(resolvedTs);
        }).toList();

        final pendingTotal = pendingFlags.length;
        final resolvedTotal = resolvedFlags.length;

        final isViewingPending = _flagStatusTab == 'pending';
        final activePool = isViewingPending ? pendingFlags : resolvedFlags;

        final totalCount = activePool.length;
        final sightingCount =
            activePool.where((f) => _resolveFlagType(f) == 'sighting').length;
        final commentCount =
            activePool.where((f) => _resolveFlagType(f) == 'comment').length;
        final reviewCount =
            activePool.where((f) => _resolveFlagType(f) == 'review').length;
        final chatCount =
            activePool.where((f) => _resolveFlagType(f) == 'chat_message').length;

        final filteredFlags = activePool.where((f) {
          if (_flagFilter == 'all') return true;
          return _resolveFlagType(f) == _flagFilter;
        }).toList();

        return Column(
          children: [

            Container(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _navy.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _flagStatusTab = 'pending'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isViewingPending ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: isViewingPending
                              ? [
                                  BoxShadow(
                                    color: _navy.withValues(alpha: 0.08),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.pending_actions_rounded,
                              size: 15,
                              color: isViewingPending ? _adminPurple : _navy.withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Pending Review',
                              style: GoogleFonts.nunito(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: isViewingPending ? _adminPurple : _navy.withValues(alpha: 0.6),
                              ),
                            ),
                            if (pendingTotal > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: isViewingPending ? _red : _red.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$pendingTotal',
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _flagStatusTab = 'resolved'),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: !isViewingPending ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(9),
                          boxShadow: !isViewingPending
                              ? [
                                  BoxShadow(
                                    color: _navy.withValues(alpha: 0.08),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.task_alt_rounded,
                              size: 15,
                              color: !isViewingPending ? _adminPurple : _navy.withValues(alpha: 0.5),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Resolved History',
                              style: GoogleFonts.nunito(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: !isViewingPending ? _adminPurple : _navy.withValues(alpha: 0.6),
                              ),
                            ),
                            if (resolvedTotal > 0) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: !isViewingPending ? _green : _green.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$resolvedTotal',
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),


            if (!isViewingPending)
              Container(
                margin: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _navy.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _navy.withValues(alpha: 0.08)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.auto_delete_outlined, size: 14, color: _navy.withValues(alpha: 0.5)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Auto-archives after 30 days',
                        style: GoogleFonts.nunito(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _navy.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    if (resolvedFlags.isNotEmpty)
                      GestureDetector(
                        onTap: () => _confirmClearResolvedFlags(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.delete_sweep_rounded, size: 13, color: _red),
                              const SizedBox(width: 4),
                              Text(
                                'Clear History',
                                style: GoogleFonts.nunito(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: _red,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),


            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildFlagFilterChip('all', 'All', totalCount, Icons.grid_view_rounded),
                    const SizedBox(width: 8),
                    _buildFlagFilterChip('sighting', 'Sightings', sightingCount, Icons.pets_rounded),
                    const SizedBox(width: 8),
                    _buildFlagFilterChip('comment', 'Comments', commentCount, Icons.comment_rounded),
                    const SizedBox(width: 8),
                    _buildFlagFilterChip('review', 'Reviews', reviewCount, Icons.rate_review_rounded),
                    const SizedBox(width: 8),
                    _buildFlagFilterChip('chat_message', 'Chats', chatCount, Icons.chat_rounded),
                  ],
                ),
              ),
            ),

            Expanded(
              child: filteredFlags.isEmpty
                  ? _buildEmptyTab(
                      isViewingPending
                          ? Icons.verified_rounded
                          : Icons.history_rounded,
                      isViewingPending
                          ? (_flagFilter == 'all'
                              ? 'All clear! No pending flagged items'
                              : 'No pending $_flagFilter flags found')
                          : (_flagFilter == 'all'
                              ? 'No resolved flags in history'
                              : 'No resolved $_flagFilter flags found'),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                      itemCount: filteredFlags.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final f = filteredFlags[index];
                        final type = _resolveFlagType(f);
                        final reason = f['reason']?.toString() ?? 'No reason provided';
                        final status = f['status']?.toString() ?? 'pending';
                        final isPending = status == 'pending';
                        final timeStr = _formatTimestamp(f['createdAt']);
                        final sightingId = f['sightingId']?.toString().trim() ?? '';
                        final commentId = f['commentId']?.toString().trim() ?? '';


                        final sighting = sightingId.isNotEmpty ? _sightingMap[sightingId] : null;
                        if (sightingId.isNotEmpty && sighting == null) {
                          _ensureSightingLoaded(sightingId);
                        }
                        if (sightingId.isNotEmpty && commentId.isNotEmpty) {
                          _ensureCommentLoaded(sightingId, commentId);
                        }

                        IconData icon;
                        Color color;
                        String typeLabel;
                        String cardTitle;
                        String metaInfo;
                        String? shortDesc;
                        String? literalContent;

                        switch (type) {
                          case 'comment':
                            icon = Icons.comment_rounded;
                            color = _amber;
                            typeLabel = 'COMMENT';

                            final parentTitle = (sighting != null && sighting.displayTitle.isNotEmpty)
                                ? sighting.displayTitle
                                : (f['sightingTitle']?.toString().trim().isNotEmpty == true
                                    ? f['sightingTitle'].toString().trim()
                                    : (sightingId.isNotEmpty
                                        ? 'Report #${sightingId.length > 8 ? sightingId.substring(0, 8) : sightingId}'
                                        : 'Community Report'));
                            cardTitle = 'Comment on: $parentTitle';

                            final author = (f['authorName']?.toString().trim().isNotEmpty == true)
                                ? f['authorName'].toString().trim()
                                : (f['userName']?.toString().trim().isNotEmpty == true
                                    ? f['userName'].toString().trim()
                                    : 'Community Member');
                            final cat = sighting?.category.trim().isNotEmpty == true
                                ? sighting!.category.trim()
                                : 'Sighting';
                            metaInfo = '👤 Author: $author • 🐾 Report Type: $cat';

                            String cText = '';
                            if (f['commentText']?.toString().trim().isNotEmpty == true) {
                              cText = f['commentText'].toString().trim();
                            } else if (f['text']?.toString().trim().isNotEmpty == true) {
                              cText = f['text'].toString().trim();
                            } else if (f['comment']?.toString().trim().isNotEmpty == true) {
                              cText = f['comment'].toString().trim();
                            } else if (f['customNote']?.toString().trim().isNotEmpty == true) {
                              cText = f['customNote'].toString().trim();
                            } else if (f['message']?.toString().trim().isNotEmpty == true) {
                              cText = f['message'].toString().trim();
                            } else {
                              final key = '$sightingId/$commentId';
                              if (_commentTextMap.containsKey(key) && _commentTextMap[key]!.isNotEmpty) {
                                cText = _commentTextMap[key]!;
                              }
                            }
                            literalContent = cText.isNotEmpty
                                ? cText
                                : (f['details']?.toString().trim().isNotEmpty == true
                                    ? f['details'].toString().trim()
                                    : null);
                            shortDesc = null;
                            break;

                          case 'sighting':
                            icon = Icons.pets_rounded;
                            color = _red;
                            typeLabel = 'SIGHTING';

                            final isDeleted = sighting?.isDeleted == true;
                            final reportTitle = (sighting != null && sighting.displayTitle.isNotEmpty)
                                ? sighting.displayTitle
                                : (f['sightingTitle']?.toString().trim().isNotEmpty == true
                                    ? f['sightingTitle'].toString().trim()
                                    : (sightingId.isNotEmpty
                                        ? 'Sighting #${sightingId.length > 8 ? sightingId.substring(0, 8) : sightingId}'
                                        : 'Flagged Sighting Report'));
                            cardTitle = isDeleted ? '$reportTitle [Deleted by Admin]' : reportTitle;

                            final reportType = sighting?.category.trim().isNotEmpty == true
                                ? sighting!.category.trim()
                                : (f['category']?.toString().trim().isNotEmpty == true
                                    ? f['category'].toString().trim()
                                    : 'Stray Pet');
                            final loc = sighting?.locationAddress.trim().isNotEmpty == true
                                ? sighting!.locationAddress.trim()
                                : (f['locationName']?.toString().trim().isNotEmpty == true
                                    ? f['locationName'].toString().trim()
                                    : '');
                            metaInfo = isDeleted
                                ? '🗑️ DELETED BY ADMIN • 🐾 Type: $reportType${loc.isNotEmpty ? " • 📍 $loc" : ""}'
                                : '🐾 Type: $reportType${loc.isNotEmpty ? " • 📍 $loc" : ""}';

                            final desc = sighting?.description.trim().isNotEmpty == true
                                ? sighting!.description.trim()
                                : (f['description']?.toString().trim().isNotEmpty == true
                                    ? f['description'].toString().trim()
                                    : (f['details']?.toString().trim().isNotEmpty == true
                                        ? f['details'].toString().trim()
                                        : ''));
                            shortDesc = desc;
                            literalContent = null;
                            break;

                          case 'review':
                            icon = Icons.rate_review_rounded;
                            color = const Color(0xFF1976D2);
                            typeLabel = 'REVIEW';

                            final target = f['targetUserId']?.toString().trim() ?? '';
                            cardTitle = target.isNotEmpty ? 'User Review for #$target' : 'Flagged Review';

                            final reviewer = f['reviewerName']?.toString().trim().isNotEmpty == true
                                ? f['reviewerName'].toString().trim()
                                : 'User';
                            final rating = f['rating']?.toString() ?? '5';
                            metaInfo = '👤 Reviewer: $reviewer • ⭐ Rating: $rating★';

                            literalContent = (f['comment']?.toString().trim().isNotEmpty == true)
                                ? f['comment'].toString().trim()
                                : (f['details']?.toString().trim().isNotEmpty == true
                                    ? f['details'].toString().trim()
                                    : null);
                            shortDesc = null;
                            break;

                          case 'chat_message':
                            icon = Icons.chat_rounded;
                            color = const Color(0xFF7B1FA2);
                            typeLabel = 'CHAT MESSAGE';

                            final chatId = f['chatId']?.toString().trim() ?? '';
                            cardTitle = chatId.isNotEmpty ? 'Chat Message in #$chatId' : 'Flagged Chat Message';

                            final sender = f['senderName']?.toString().trim().isNotEmpty == true
                                ? f['senderName'].toString().trim()
                                : 'Chat Member';
                            metaInfo = '💬 Sender: $sender • Coordination Thread';

                            literalContent = (f['messageText']?.toString().trim().isNotEmpty == true)
                                ? f['messageText'].toString().trim()
                                : (f['message']?.toString().trim().isNotEmpty == true
                                    ? f['message'].toString().trim()
                                    : null);
                            shortDesc = null;
                            break;

                          default:
                            icon = Icons.flag_rounded;
                            color = _navy;
                            typeLabel = 'FLAG';
                            cardTitle = f['sightingTitle']?.toString().trim().isNotEmpty == true
                                ? f['sightingTitle'].toString().trim()
                                : 'Flagged Content';
                            metaInfo = 'Category: ${f['type'] ?? 'General'}';
                            shortDesc = f['details']?.toString().trim() ?? '';
                            literalContent = null;
                        }

                        return GestureDetector(
                          onTap: () => _handleFlagTap(f),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isPending
                                  ? color.withValues(alpha: 0.04)
                                  : _green.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isPending
                                    ? color.withValues(alpha: 0.18)
                                    : _green.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [

                                Row(
                                  children: [
                                    Icon(
                                      icon,
                                      color: isPending ? color : _green,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        cardTitle,
                                        style: GoogleFonts.nunito(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: _navy,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        typeLabel,
                                        style: GoogleFonts.nunito(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: color,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isPending
                                            ? _amber.withValues(alpha: 0.12)
                                            : _green.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        status.toUpperCase(),
                                        style: GoogleFonts.nunito(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: isPending ? _amber : _green,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),


                                Text(
                                  metaInfo,
                                  style: GoogleFonts.nunito(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _navy.withValues(alpha: 0.65),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),


                                if (shortDesc != null && shortDesc.isNotEmpty) ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    shortDesc,
                                    style: GoogleFonts.nunito(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: _navy.withValues(alpha: 0.8),
                                      height: 1.3,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],


                                if (literalContent != null && literalContent.isNotEmpty) ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.07),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border(
                                        left: BorderSide(color: color, width: 3),
                                      ),
                                    ),
                                    child: Text(
                                      '"$literalContent"',
                                      style: GoogleFonts.nunito(
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                        fontWeight: FontWeight.w700,
                                        color: _navy.withValues(alpha: 0.9),
                                        height: 1.3,
                                      ),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ] else if (type == 'comment') ...[
                                  const SizedBox(height: 6),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.05),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border(
                                        left: BorderSide(
                                            color: color.withValues(alpha: 0.5),
                                            width: 3),
                                      ),
                                    ),
                                    child: Text(
                                      commentId.isNotEmpty
                                          ? '"(Comment #$commentId • Tap Open to view in thread)"'
                                          : '"(Comment text unavailable)"',
                                      style: GoogleFonts.nunito(
                                        fontSize: 11.5,
                                        fontStyle: FontStyle.italic,
                                        fontWeight: FontWeight.w600,
                                        color: _navy.withValues(alpha: 0.6),
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],


                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(Icons.report_problem_rounded,
                                        size: 12, color: color),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'Reason: $reason',
                                        style: GoogleFonts.nunito(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: color,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (timeStr.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        timeStr,
                                        style: GoogleFonts.nunito(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: _navy.withValues(alpha: 0.45),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),


                                if (isPending) ...[
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () async {
                                            await FirebaseService.instance
                                                .resolveFlag(f['docId'],
                                                    action: 'resolved');
                                            _snack('Flag resolved ✓');
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 8),
                                            decoration: BoxDecoration(
                                              color: _green.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Center(
                                              child: Text(
                                                '✅ Resolve Flag',
                                                style: GoogleFonts.nunito(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                  color: _green,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () async {
                                            await FirebaseService.instance
                                                .resolveFlag(f['docId'],
                                                    action: 'dismissed');
                                            _snack('Flag dismissed');
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 8),
                                            decoration: BoxDecoration(
                                              color: _red.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Center(
                                              child: Text(
                                                '❌ Dismiss',
                                                style: GoogleFonts.nunito(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                  color: _red,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () => _handleFlagTap(f),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: _adminPurple.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.open_in_new_rounded,
                                                  size: 12, color: _adminPurple),
                                              const SizedBox(width: 4),
                                              Text(
                                                'Open',
                                                style: GoogleFonts.nunito(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w800,
                                                  color: _adminPurple,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ] else ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(
                                        status == 'resolved'
                                            ? Icons.check_circle_outline_rounded
                                            : Icons.remove_circle_outline_rounded,
                                        size: 13,
                                        color: status == 'resolved'
                                            ? _green
                                            : _navy.withValues(alpha: 0.5),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Flag $status',
                                        style: GoogleFonts.nunito(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: status == 'resolved'
                                              ? _green
                                              : _navy.withValues(alpha: 0.5),
                                        ),
                                      ),
                                      if (f['resolvedAt'] != null) ...[
                                        const SizedBox(width: 6),
                                        Text(
                                          '• ${_formatTimestamp(f['resolvedAt'])}',
                                          style: GoogleFonts.nunito(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: _navy.withValues(alpha: 0.4),
                                          ),
                                        ),
                                      ],
                                      const Spacer(),
                                      GestureDetector(
                                        onTap: () => _handleFlagTap(f),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'Inspect',
                                              style: GoogleFonts.nunito(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w800,
                                                color: _adminPurple,
                                              ),
                                            ),
                                            const SizedBox(width: 2),
                                            Icon(Icons.open_in_new_rounded,
                                                size: 12, color: _adminPurple),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      GestureDetector(
                                        onTap: () async {
                                          if (f['docId'] != null) {
                                            await FirebaseService.instance.deleteFlag(f['docId']);
                                            _snack('Removed from history');
                                          }
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.all(4),
                                          decoration: BoxDecoration(
                                            color: _navy.withValues(alpha: 0.05),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Icon(Icons.delete_outline_rounded,
                                              size: 14, color: _navy.withValues(alpha: 0.45)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFlagFilterChip(
      String key, String label, int count, IconData icon) {
    final isSelected = _flagFilter == key;
    return GestureDetector(
      onTap: () {
        setState(() {
          _flagFilter = key;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? _adminPurple : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? _adminPurple
                : _navy.withValues(alpha: 0.12),
            width: 1.2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _adminPurple.withValues(alpha: 0.25),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : _navy.withValues(alpha: 0.65),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w700,
                color: isSelected ? Colors.white : _navy.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.white.withValues(alpha: 0.25)
                    : _navy.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.nunito(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: isSelected ? Colors.white : _navy.withValues(alpha: 0.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClinicRequestsTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: FirebaseService.instance.streamAllClinicSuggestions(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return _buildEmptyTab(
              Icons.local_hospital_rounded, 'No clinic/shelter suggestions');
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          itemCount: items.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final c = items[index];
            final status = c['status']?.toString() ?? 'pending';
            final isPending = status == 'pending';

            return GestureDetector(
              onTap: () => _showClinicDetailModal(c),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isPending
                      ? _amber.withValues(alpha: 0.04)
                      : _green.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: isPending
                          ? _amber.withValues(alpha: 0.15)
                          : _green.withValues(alpha: 0.15)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Row(
                    children: [
                      Icon(
                        c['type'] == 'shelter'
                            ? Icons.home_rounded
                            : Icons.local_hospital_rounded,
                        color: isPending ? _amber : _green,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          c['name']?.toString() ?? 'Unnamed',
                          style: GoogleFonts.nunito(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: _navy),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isPending
                              ? _amber.withValues(alpha: 0.12)
                              : _green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: GoogleFonts.nunito(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: isPending ? _amber : _green),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c['address']?.toString() ?? '',
                    style: GoogleFonts.nunito(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _navy.withValues(alpha: 0.6)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (c['phone'] != null && (c['phone'] as String).isNotEmpty)
                    Text(
                      '📞 ${c['phone']}',
                      style: GoogleFonts.nunito(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _navy.withValues(alpha: 0.5)),
                    ),
                  if (isPending) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              await FirebaseService.instance
                                  .verifyClinicSuggestion(c['docId']);
                              _snack('✅ ${c['name']} verified!');
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  '✅ Verify',
                                  style: GoogleFonts.nunito(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: _green),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () async {
                              await FirebaseService.instance
                                  .rejectClinicSuggestion(c['docId']);
                              _snack('Suggestion rejected');
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _red.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  '✗ Reject',
                                  style: GoogleFonts.nunito(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: _red),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.touch_app_rounded, size: 12, color: _adminPurple),
                      const SizedBox(width: 4),
                      Text(
                        'Tap card for details & location ↗',
                        style: GoogleFonts.nunito(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: _adminPurple,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

  Future<void> _handleFlagTap(Map<String, dynamic> f) async {
    final type = _resolveFlagType(f);
    final sightingId = f['sightingId']?.toString().trim();
    final commentId = f['commentId']?.toString().trim();
    final targetUserId = f['targetUserId']?.toString() ?? f['userId']?.toString();

    if (type == 'chat_message') {
      _showFlaggedChatDialog(f);
      return;
    }

    if (sightingId != null && sightingId.isNotEmpty) {
      try {
        _sightingCache.remove(sightingId);
        final s = await _getCachedSighting(sightingId);
        if (s != null) {
          if (mounted) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SightingDetailScreen(
                  sighting: s,
                  highlightCommentId: (type == 'comment') ? commentId : null,
                  scrollToComments: (type == 'comment'),
                ),
              ),
            ).then((_) {
              _sightingCache.remove(sightingId);
              _sightingMap.remove(sightingId);
              _ensureSightingLoaded(sightingId);
              if (mounted) setState(() {});
            });
          }
        } else {
          _snack('This report has already been deleted or removed.');
        }
      } catch (e) {
        _snack('Error opening report: $e');
      }
    } else if (targetUserId != null && targetUserId.isNotEmpty) {
      try {
        final profile = await FirebaseService.instance.getUserProfile(targetUserId);
        if (profile != null) {
          if (mounted) {
            setState(() => _currentTab = 3);
            _showUserDetailSheet(profile);
          }
        } else {
          _snack('User profile not found.');
        }
      } catch (e) {
        _snack('Error opening user: $e');
      }
    }
  }

  void _showFlaggedChatDialog(Map<String, dynamic> f) {
    final chatId = f['chatId']?.toString() ?? '';
    final photoUrl = f['photoUrl']?.toString();
    final reason = f['reason']?.toString() ?? 'Inappropriate content';
    final senderName = f['senderName']?.toString();
    final messageText = f['messageText']?.toString();
    final isPending = (f['status']?.toString() ?? 'pending') == 'pending';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.chat_rounded, color: Color(0xFF7B1FA2)),
            const SizedBox(width: 8),
            Text(
              'Flagged Chat Message',
              style: GoogleFonts.nunito(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Reason: $reason',
                        style: GoogleFonts.nunito(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.red.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (senderName != null && senderName.isNotEmpty) ...[
                Text(
                  'Sender: $senderName',
                  style: GoogleFonts.nunito(
                      fontSize: 12, fontWeight: FontWeight.w700, color: _navy),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                'Chat Room: $chatId',
                style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _navy.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 10),
              if (messageText != null && messageText.isNotEmpty) ...[
                Text(
                  'Message Text:',
                  style: GoogleFonts.nunito(
                      fontSize: 11, fontWeight: FontWeight.w800, color: _navy),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(10),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _navy.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    messageText,
                    style: GoogleFonts.nunito(
                        fontSize: 13, fontWeight: FontWeight.w600, color: _navy),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (photoUrl != null && photoUrl.isNotEmpty) ...[
                Text(
                  'Reported Photo:',
                  style: GoogleFonts.nunito(
                      fontSize: 11, fontWeight: FontWeight.w800, color: _navy),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: PawImage(
                    url: photoUrl,
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (isPending) ...[
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await FirebaseService.instance
                    .resolveFlag(f['docId'], action: 'dismissed');
                _snack('Flag dismissed');
              },
              child: Text('Dismiss', style: TextStyle(color: Colors.grey.shade700)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await FirebaseService.instance
                    .resolveFlag(f['docId'], action: 'resolved');
                _snack('Flag resolved ✓');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Resolve'),
            ),
          ] else ...[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ],
      ),
    );
  }

  void _showClinicDetailModal(Map<String, dynamic> c) {
    final name = c['name']?.toString() ?? 'Unnamed';
    final type = c['type']?.toString() ?? 'clinic';
    final address = c['address']?.toString() ?? '';
    final phone = c['phone']?.toString() ?? '';
    final hours = c['operatingHours']?.toString() ?? 'Daily';
    final notes = c['notes']?.toString() ?? '';
    final submittedByName = c['submittedByName']?.toString() ?? 'Volunteer';
    final is24 = c['is24Hours'] == true;
    final services = (c['services'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final status = c['status']?.toString() ?? 'pending';
    final isPending = status == 'pending';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => Container(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          bottom: true,
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: type == 'shelter'
                          ? const Color(0xFF00897B).withValues(alpha: 0.12)
                          : const Color(0xFF1E88E5).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      type == 'shelter' ? Icons.home_rounded : Icons.local_hospital_rounded,
                      color: type == 'shelter' ? const Color(0xFF00897B) : const Color(0xFF1E88E5),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.nunito(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: _navy,
                          ),
                        ),
                        Text(
                          type == 'shelter' ? 'Partner Shelter Suggestion' : 'Veterinary Clinic Suggestion',
                          style: GoogleFonts.nunito(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _navy.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (address.isNotEmpty) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.location_on_rounded, size: 16, color: Color(0xFFE53935)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        address,
                        style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: _navy),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (phone.isNotEmpty) ...[
                Row(
                  children: [
                    const Icon(Icons.phone_rounded, size: 16, color: Color(0xFF43A047)),
                    const SizedBox(width: 6),
                    Text(
                      phone,
                      style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: _navy),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  const Icon(Icons.access_time_rounded, size: 16, color: Color(0xFFFFA000)),
                  const SizedBox(width: 6),
                  Text(
                    is24 ? '24 Hours Emergency Intake' : hours,
                    style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w600, color: _navy),
                  ),
                ],
              ),
              if (services.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Services Offered:',
                  style: GoogleFonts.nunito(fontSize: 12.5, fontWeight: FontWeight.w800, color: _navy),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: services.map((s) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _adminPurpleLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      s,
                      style: GoogleFonts.nunito(fontSize: 11, fontWeight: FontWeight.w700, color: _adminPurple),
                    ),
                  )).toList(),
                ),
              ],
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  'Notes from Submitter ($submittedByName):',
                  style: GoogleFonts.nunito(fontSize: 12.5, fontWeight: FontWeight.w800, color: _navy),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _navy.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    notes,
                    style: GoogleFonts.nunito(fontSize: 12, color: _navy.withValues(alpha: 0.8)),
                  ),
                ),
              ],
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _adminPurple,
                        side: const BorderSide(color: Color(0xFF6C3FC5), width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.pop(bCtx);
                        setState(() => _currentTab = 1);
                      },
                      icon: const Icon(Icons.map_rounded, size: 18),
                      label: Text('View on Map', style: GoogleFonts.nunito(fontWeight: FontWeight.w800, fontSize: 13)),
                    ),
                  ),
                  if (isPending) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () async {
                          Navigator.pop(bCtx);
                          await FirebaseService.instance.verifyClinicSuggestion(c['docId']);
                          _snack('✅ $name verified successfully!');
                        },
                        icon: const Icon(Icons.check_circle_rounded, size: 18),
                        label: Text('Verify', style: GoogleFonts.nunito(fontWeight: FontWeight.w800, fontSize: 13)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.cancel_rounded, color: Color(0xFFE53935), size: 28),
                      tooltip: 'Reject Suggestion',
                      onPressed: () async {
                        Navigator.pop(bCtx);
                        await FirebaseService.instance.rejectClinicSuggestion(c['docId']);
                        _snack('Suggestion rejected');
                      },
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    ),
  );
}

  Widget _buildAnnouncementsTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: FirebaseService.instance.streamAnnouncements(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return _buildEmptyTab(Icons.campaign_rounded, 'No announcements yet');
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          itemCount: items.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final a = items[index];
            final ts = a['createdAt'] as Timestamp?;
            final date = ts != null
                ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}'
                : '';
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _adminPurple.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: _adminPurple.withValues(alpha: 0.1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.campaign_rounded,
                          color: _adminPurple, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          a['title']?.toString() ?? 'Untitled',
                          style: GoogleFonts.nunito(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: _navy),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        date,
                        style: GoogleFonts.nunito(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: _navy.withValues(alpha: 0.4)),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () async {
                          final docId = a['docId']?.toString();
                          if (docId != null) {
                            await FirebaseService.instance.deleteAnnouncement(docId);
                            _snack('Announcement deleted.');
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.delete_outline_rounded,
                              size: 16, color: Color(0xFFE53935)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    a['body']?.toString() ?? '',
                    style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _navy.withValues(alpha: 0.7)),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyTab(IconData icon, String label) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: _navy.withValues(alpha: 0.12)),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _navy.withValues(alpha: 0.3)),
          ),
        ],
      ),
    );
  }


  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: _adminPurple,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Text(
          msg,
          style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Future<bool?> _confirmAction(String title, String subtitle) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: GoogleFonts.nunito(fontWeight: FontWeight.w800, color: _navy),
        ),
        content: Text(
          subtitle,
          style: GoogleFonts.nunito(
              fontWeight: FontWeight.w600,
              color: _navy.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.nunito(
                  fontWeight: FontWeight.w700,
                  color: _navy.withValues(alpha: 0.5)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Confirm',
              style: GoogleFonts.nunito(
                  fontWeight: FontWeight.w800, color: _red),
            ),
          ),
        ],
      ),
    );
  }
}

