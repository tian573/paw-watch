import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/sighting.dart';
import '../../models/user_profile.dart';
import '../../services/firebase_service.dart';
import '../../services/location_service.dart';
import 'report_form.dart';
import 'sighting_detail.dart';
import 'profile_screen.dart';
import 'conversations_screen.dart';
import 'map_screen.dart';
import '../widgets/paw_image.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const Color _navy = Color(0xFF1B2A4A);
  static const Color _lavender = Color(0xFF9B8EC4);
  static const Color _lavLight = Color(0xFFF3F0FA);
  static const Color _green = Color(0xFF7BBF5E);
  static const Color _bgWhite = Color(0xFFFAF9F7);
  static const Color _urgent = Color(0xFFE53935);
  static const Color _needsHelp = Color(0xFFFF7043);
  static const Color _needsHome = Color(0xFF8E24AA);
  static const Color _resolved = Color(0xFF43A047);
  static const Color _cardBg = Color(0xFFFFFFFF);

  int _currentTab = 0;
  String _activeFilter = 'All';
  bool _showNewUserTip = false;
  final Set<String> _dismissedDispatchIds = {};
  final Set<String> _dismissedFosterCareIds = {};
  final Set<String> _dismissedPendingVetIds = {};
  final Set<String> _dismissedAnnouncementIds = {};
  final Set<String> _dismissedDeletedSightingIds = {};
  bool _hideAllDeletedReports = false;
  final Set<String> _readNotificationIds = {};
  bool _hasUnreadNotificationsState = false;
  StreamSubscription<List<Map<String, dynamic>>>? _announcementsSub;
  List<Map<String, dynamic>> _latestAnnouncements = [];
  double? _userLat;
  double? _userLng;
  late AnimationController _arrowAnimController;
  late Animation<double> _arrowBounce;

  late final Stream<List<Sighting>> _sightingsStream;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && FirebaseAuth.instance.currentUser?.email == 'admin@example.com') {
        Navigator.pushReplacementNamed(context, '/admin');
      }
    });
    _sightingsStream = FirebaseService.instance.streamSightings();
    FirebaseService.instance.autoResolveVerifiedShelterSightings();
    _checkFirstTimeUser();
    _loadNotificationPreferences();
    _announcementsSub = FirebaseService.instance.streamAnnouncements().listen((announcements) {
      _latestAnnouncements = announcements;
      _updateUnreadStatus();
    });
    _fetchUserLocation();
    _arrowAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _arrowBounce = Tween<double>(begin: 0, end: 10).animate(
      CurvedAnimation(parent: _arrowAnimController, curve: Curves.easeInOut),
    );
  }

  Future<void> _loadNotificationPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      final dismissedDispatches = prefs.getStringList('dismissed_dispatch_ids_$uid') ?? [];
      final dismissedAnnouncements = prefs.getStringList('dismissed_announcement_ids_$uid') ?? [];
      final readNotifications = prefs.getStringList('read_notification_ids_$uid') ?? [];
      final dismissedFosterCare = prefs.getStringList('dismissed_foster_care_ids_$uid') ?? [];
      final dismissedPendingVet = prefs.getStringList('dismissed_pending_vet_ids_$uid') ?? [];
      final dismissedDeleted = prefs.getStringList('dismissed_deleted_sighting_ids_$uid') ?? [];
      final hideAllDeleted = prefs.getBool('hide_all_deleted_reports_$uid') ?? false;
      if (mounted) {
        setState(() {
          _dismissedDispatchIds.addAll(dismissedDispatches);
          _dismissedAnnouncementIds.addAll(dismissedAnnouncements);
          _readNotificationIds.addAll(readNotifications);
          _dismissedFosterCareIds.addAll(dismissedFosterCare);
          _dismissedPendingVetIds.addAll(dismissedPendingVet);
          _dismissedDeletedSightingIds.addAll(dismissedDeleted);
          _hideAllDeletedReports = hideAllDeleted;
        });
        _updateUnreadStatus();
      }
    } catch (_) {}
  }

  Future<void> _dismissDeletedReport(String sightingId) async {
    setState(() {
      _dismissedDeletedSightingIds.add(sightingId);
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      await prefs.setStringList('dismissed_deleted_sighting_ids_$uid', _dismissedDeletedSightingIds.toList());
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Deleted report removed from your home page.',
            style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
          ),
          action: SnackBarAction(
            label: 'Undo',
            textColor: Colors.amber,
            onPressed: () => _undoDismissDeletedReport(sightingId),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _undoDismissDeletedReport(String sightingId) async {
    setState(() {
      _dismissedDeletedSightingIds.remove(sightingId);
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      await prefs.setStringList('dismissed_deleted_sighting_ids_$uid', _dismissedDeletedSightingIds.toList());
    } catch (_) {}
  }

  Future<void> _toggleHideAllDeletedReports() async {
    final next = !_hideAllDeletedReports;
    setState(() {
      _hideAllDeletedReports = next;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      await prefs.setBool('hide_all_deleted_reports_$uid', next);
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next ? 'Hiding all deleted reports on home page.' : 'Showing deleted reports on home page.',
            style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showAdminQuickDeleteDialog(Sighting sighting) {
    String selectedReason = 'Violated community guidelines';
    final customCtrl = TextEditingController();
    final reasons = [
      'Violated community guidelines',
      'Spam or advertising content',
      'False or misleading sighting',
      'Inappropriate photo or language',
      'Duplicate report',
      'Other',
    ];

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  const Icon(Icons.gavel_rounded, color: Color(0xFFE53935), size: 22),
                  const SizedBox(width: 8),
                  Text(
                    'Admin Delete Report',
                    style: GoogleFonts.nunito(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delete report "${sighting.displayTitle}" by ${sighting.reporterName}?',
                      style: GoogleFonts.nunito(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: _navy.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Select deletion reason:',
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ...reasons.map((r) {
                      final isSelected = selectedReason == r;
                      return InkWell(
                        onTap: () => setDialogState(() => selectedReason = r),
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                size: 18,
                                color: isSelected ? const Color(0xFFE53935) : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  r,
                                  style: GoogleFonts.nunito(
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                    color: isSelected ? const Color(0xFFE53935) : _navy,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    if (selectedReason == 'Other') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: customCtrl,
                        decoration: InputDecoration(
                          hintText: 'Enter reason...',
                          hintStyle: GoogleFonts.nunito(fontSize: 12),
                          filled: true,
                          fillColor: Colors.grey.shade100,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey.shade300),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: GoogleFonts.nunito(fontWeight: FontWeight.w700)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () async {
                    final finalReason = selectedReason == 'Other' && customCtrl.text.trim().isNotEmpty
                        ? customCtrl.text.trim()
                        : selectedReason;
                    Navigator.pop(ctx);
                    try {
                      await FirebaseService.instance.adminDeleteSighting(
                        sighting.id,
                        reason: finalReason,
                      );
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Report deleted by Admin.',
                              style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
                            ),
                            behavior: SnackBarBehavior.floating,
                            backgroundColor: const Color(0xFFE53935),
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Error: $e')),
                        );
                      }
                    }
                  },
                  child: Text('Delete Report', style: GoogleFonts.nunito(fontWeight: FontWeight.w800)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _dismissFosterCare(String sightingId) async {
    setState(() {
      _dismissedFosterCareIds.add(sightingId);
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      final list = prefs.getStringList('dismissed_foster_care_ids_$uid') ?? [];
      if (!list.contains(sightingId)) {
        list.add(sightingId);
        await prefs.setStringList('dismissed_foster_care_ids_$uid', list);
      }
    } catch (_) {}
  }

  Future<void> _dismissPendingVet(String sightingId) async {
    setState(() {
      _dismissedPendingVetIds.add(sightingId);
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      final list = prefs.getStringList('dismissed_pending_vet_ids_$uid') ?? [];
      if (!list.contains(sightingId)) {
        list.add(sightingId);
        await prefs.setStringList('dismissed_pending_vet_ids_$uid', list);
      }
    } catch (_) {}
  }

  void _updateUnreadStatus() {
    final activeAnnouncements = _latestAnnouncements.where((a) {
      final id = a['docId']?.toString();
      return id != null && !_dismissedAnnouncementIds.contains(id);
    }).toList();

    final hasUnread = activeAnnouncements.any((a) {
      final id = a['docId']?.toString();
      return id != null && !_readNotificationIds.contains(id);
    });

    if (mounted && _hasUnreadNotificationsState != hasUnread) {
      setState(() {
        _hasUnreadNotificationsState = hasUnread;
      });
    }
  }

  Future<void> _markAllNotificationsAsRead() async {
    final toAdd = <String>[];
    for (final a in _latestAnnouncements) {
      final id = a['docId']?.toString();
      if (id != null && !_dismissedAnnouncementIds.contains(id)) {
        toAdd.add(id);
      }
    }

    if (toAdd.isNotEmpty) {
      setState(() {
        _readNotificationIds.addAll(toAdd);
        _hasUnreadNotificationsState = false;
      });
      try {
        final prefs = await SharedPreferences.getInstance();
        final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
        await prefs.setStringList('read_notification_ids_$uid', _readNotificationIds.toList());
      } catch (_) {}
    } else {
      if (_hasUnreadNotificationsState) {
        setState(() {
          _hasUnreadNotificationsState = false;
        });
      }
    }
  }

  Future<void> _deleteAnnouncement(String docId) async {
    setState(() {
      _dismissedAnnouncementIds.add(docId);
      _readNotificationIds.add(docId);
    });
    _updateUnreadStatus();
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      final list = prefs.getStringList('dismissed_announcement_ids_$uid') ?? [];
      if (!list.contains(docId)) {
        list.add(docId);
        await prefs.setStringList('dismissed_announcement_ids_$uid', list);
      }
      final readList = prefs.getStringList('read_notification_ids_$uid') ?? [];
      if (!readList.contains(docId)) {
        readList.add(docId);
        await prefs.setStringList('read_notification_ids_$uid', readList);
      }
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Notification deleted',
            style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _dismissDispatch(String sightingId) async {
    setState(() {
      _dismissedDispatchIds.add(sightingId);
      _readNotificationIds.add(sightingId);
    });
    _updateUnreadStatus();
    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      final list = prefs.getStringList('dismissed_dispatch_ids_$uid') ?? [];
      if (!list.contains(sightingId)) {
        list.add(sightingId);
        await prefs.setStringList('dismissed_dispatch_ids_$uid', list);
      }
      final readList = prefs.getStringList('read_notification_ids_$uid') ?? [];
      if (!readList.contains(sightingId)) {
        readList.add(sightingId);
        await prefs.setStringList('read_notification_ids_$uid', readList);
      }
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid != null) {
        await FirebaseService.instance.dismissDispatchForUser(sightingId);
      }
    } catch (_) {}
  }

  Future<void> _deleteDispatchNotification(String sightingId) async {
    await _dismissDispatch(sightingId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Rescue notification removed',
            style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _clearAllNotifications() async {
    final annIds = _latestAnnouncements
        .map((a) => a['docId']?.toString())
        .whereType<String>()
        .toList();

    setState(() {
      _dismissedAnnouncementIds.addAll(annIds);
      _readNotificationIds.addAll(annIds);
      _hasUnreadNotificationsState = false;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final uid = FirebaseAuth.instance.currentUser?.uid ?? 'anon';
      await prefs.setStringList('dismissed_announcement_ids_$uid', _dismissedAnnouncementIds.toList());
      await prefs.setStringList('read_notification_ids_$uid', _readNotificationIds.toList());
    } catch (_) {}

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'All announcements cleared',
            style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
          ),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _confirmDeleteAnnouncement(String docId) {
    final isAdmin = FirebaseAuth.instance.currentUser?.email == 'admin@example.com';
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, color: Color(0xFFE53935)),
            const SizedBox(width: 8),
            Text(
              'Delete Notification',
              style: GoogleFonts.nunito(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _navy,
              ),
            ),
          ],
        ),
        content: Text(
          isAdmin
              ? 'Are you sure you want to delete this announcement? Because you are an admin, it will also be removed for all users.'
              : 'Are you sure you want to remove this notification from your list?',
          style: GoogleFonts.nunito(fontSize: 14, color: _navy.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              'Cancel',
              style: GoogleFonts.nunito(fontWeight: FontWeight.w700, color: _navy.withValues(alpha: 0.6)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              if (isAdmin) {
                try {
                  await FirebaseService.instance.deleteAnnouncement(docId);
                } catch (_) {}
              }
              await _deleteAnnouncement(docId);
            },
            child: Text(
              'Delete',
              style: GoogleFonts.nunito(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteDispatchNotification(String sightingId) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.delete_outline_rounded, color: Color(0xFFE53935)),
            const SizedBox(width: 8),
            Text(
              'Dismiss Dispatch',
              style: GoogleFonts.nunito(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _navy,
              ),
            ),
          ],
        ),
        content: Text(
          'Remove this urgent rescue dispatch notification from your list?',
          style: GoogleFonts.nunito(fontSize: 14, color: _navy.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              'Cancel',
              style: GoogleFonts.nunito(fontWeight: FontWeight.w700, color: _navy.withValues(alpha: 0.6)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await _deleteDispatchNotification(sightingId);
            },
            child: Text(
              'Remove',
              style: GoogleFonts.nunito(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmClearAllNotifications() {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.delete_sweep_outlined, color: Color(0xFFE53935)),
            const SizedBox(width: 8),
            Text(
              'Clear Announcements',
              style: GoogleFonts.nunito(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _navy,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to clear all announcements? They will be removed from your list.',
          style: GoogleFonts.nunito(fontSize: 14, color: _navy.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              'Cancel',
              style: GoogleFonts.nunito(fontWeight: FontWeight.w700, color: _navy.withValues(alpha: 0.6)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFE53935),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(dialogCtx);
              _clearAllNotifications();
            },
            child: Text(
              'Clear All',
              style: GoogleFonts.nunito(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
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
    _announcementsSub?.cancel();
    _arrowAnimController.dispose();
    super.dispose();
  }

  final List<String> _filters = [
    'All',
    'My Cases',
    'Adoption Showcase',
    'Waiting',
    'Trapped',
    'Vulnerable',
    'Injured',
    'Needs Foster',
    'Stray',
    'Resolved',
  ];

  bool _isInvolvedInWaiting(Sighting s, String? uid) {
    if (uid == null || uid.isEmpty) return false;
    if (s.urgency == 'resolved' || s.status == 'resolved' || s.category == 'Resolved' ||
        s.category == 'Sheltered' || s.category == 'Rehomed' ||
        s.resolvedByAction == 'sheltered' || s.resolvedByAction == 'rehomed') {
      return false;
    }
    final isWaiting = s.isPendingVerification ||
        s.isAwaitingPostVetDecision ||
        s.isVetVisitPending ||
        (s.pendingVetRescuerId != null && s.pendingVetRescuerId!.isNotEmpty) ||
        (s.pendingHandoverRescuerId != null && s.pendingHandoverRescuerId!.isNotEmpty) ||
        (s.pendingOutcomeAction != null && s.pendingOutcomeAction!.isNotEmpty) ||
        s.status == 'waiting';
    if (!isWaiting) return false;

    final isReporter = s.reporterId == uid;
    final isRescuer = s.lastVetRescuerId == uid ||
        s.pendingVetRescuerId == uid ||
        s.pendingHandoverRescuerId == uid ||
        s.careTakerId == uid ||
        (s.rescueClaimed && s.rescueClaimedBy == uid);
    final isApplicant = s.pendingAdoptionApplicantId == uid;
    return isReporter || isRescuer || isApplicant;
  }

  int _categoryPriority(Sighting s, [String? currentUid]) {

    if (s.isDeleted) {
      return 99;
    }

    if (s.urgency == 'resolved' || s.status == 'resolved' || s.category == 'Resolved') {
      return 20;
    }


    if (currentUid != null && _isInvolvedInWaiting(s, currentUid)) {
      return 0;
    }

    final isClaimed = s.rescueClaimed ||
        s.isRescueClaimActive ||
        s.rescueClaimedBy.isNotEmpty ||
        s.isPendingVerification ||
        s.isAwaitingPostVetDecision ||
        s.isInCare;
    final int baseOffset = isClaimed ? 5 : 0;

    switch (s.category) {
      case 'Urgent Rescue':
        return 1 + baseOffset;
      case 'Kitten':
        return 2 + baseOffset;
      case 'Injured':
      case 'Needs Vet':
        return 3 + baseOffset;
      case 'Needs Foster':
      case 'Needs Home':
      case 'Rehomed':
        return 4 + baseOffset;
      case 'Stray':
      case 'Feeding Spot':
      case 'Spotted':
      case 'Community Cat':
      case 'Community Care':
      default:
        return 5 + baseOffset;
    }
  }

  List<Sighting> _filterAndSortSightings(List<Sighting> list, [String? currentUid]) {
    final visibleList = list.where((s) {
      if (s.isDeleted) {
        if (_hideAllDeletedReports) return false;
        if (_dismissedDeletedSightingIds.contains(s.id)) return false;
      }
      return true;
    }).toList();
    final activeList = visibleList.where((s) => !s.isDeleted).toList();
    List<Sighting> filtered;
    if (_activeFilter == 'All') {
      filtered = visibleList.where((s) => !s.isAutoArchived).toList();
    } else if (_activeFilter == 'My Cases') {
      filtered = visibleList.where((s) => s.isUserInvolved(currentUid)).toList();
    } else if (_activeFilter == 'Adoption Showcase') {
      filtered = activeList.where((s) => s.isAdoptionShowcase && !s.isAutoArchived).toList();
    } else if (_activeFilter == 'Waiting') {
      filtered = activeList
          .where((s) =>
              (s.isPendingVerification ||
                  s.isAwaitingPostVetDecision ||
                  s.status == 'waiting') &&
              !s.isAutoArchived)
          .toList();
    } else if (_activeFilter == 'Trapped') {
      filtered = activeList.where((s) => s.category == 'Urgent Rescue' && !s.isAutoArchived).toList();
    } else if (_activeFilter == 'Vulnerable') {
      filtered = activeList.where((s) => s.category == 'Kitten' && !s.isAutoArchived).toList();
    } else if (_activeFilter == 'Injured') {
      filtered = activeList
          .where((s) =>
              (s.category == 'Injured' || s.category == 'Needs Vet') &&
              !s.isAutoArchived)
          .toList();
    } else if (_activeFilter == 'Needs Foster') {
      filtered = activeList
          .where((s) =>
              (s.category == 'Needs Foster' ||
                  s.category == 'Needs Home' ||
                  s.category == 'Rehomed') &&
              !s.isAutoArchived)
          .toList();
    } else if (_activeFilter == 'Stray') {
      filtered = activeList
          .where((s) =>
              (s.category == 'Stray' ||
                  s.category == 'Feeding Spot' ||
                  s.category == 'Spotted' ||
                  s.category == 'Community Cat' ||
                  s.category == 'Community Care' ||
                  s.isTnrCommunityCat) &&
              !s.isAutoArchived)
          .toList();
    } else if (_activeFilter == 'Resolved') {
      filtered = activeList
          .where((s) =>
              s.category == 'Resolved' ||
              s.status == 'resolved' ||
              s.urgency == 'resolved' ||
              s.status == 'notUrgent')
          .toList();
    } else {
      filtered = list.where((s) => !s.isAutoArchived).toList();
    }

    filtered.sort((a, b) {

      final pA = _categoryPriority(a, currentUid);
      final pB = _categoryPriority(b, currentUid);
      if (pA != pB) {
        return pA.compareTo(pB);
      }


      final distA = a.calculateDistanceInMeters(_userLat, _userLng);
      final distB = b.calculateDistanceInMeters(_userLat, _userLng);
      final distDiff = (distA - distB).abs();
      if (distDiff > 30) {
        return distA.compareTo(distB);
      }


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
                MapScreen(
                  onNotificationTap: _showNotificationsModal,
                  onProfileTap: () => setState(() => _currentTab = 4),
                  hasUnreadNotifications: _hasUnreadNotificationsState,
                ),
                const SizedBox.shrink(),
                const ConversationsScreen(),
                const ProfileScreen(),
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
            stream: _sightingsStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                debugPrint('⚠️ Firestore streamSightings error: ${snapshot.error}');
              }
              final allSightings = snapshot.data ?? [];
              final currentUid = FirebaseAuth.instance.currentUser?.uid;
              final filtered = _filterAndSortSightings(allSightings, currentUid);
              final myActiveRescueTrip = currentUid == null
                  ? null
                  : allSightings
                      .where((s) =>
                          !s.isDeleted &&
                          s.rescueClaimed &&
                          s.rescueClaimedBy == currentUid &&
                          s.isRescueClaimActive &&
                          s.urgency != 'resolved')
                      .firstOrNull;

              final myPendingVetSighting = currentUid == null
                  ? null
                  : allSightings
                      .where((s) =>
                          !_dismissedPendingVetIds.contains(s.id) &&
                          !s.isDeleted &&
                          !s.isFinishedOrResolved &&
                          !s.isResolved &&
                          s.urgency != 'resolved' &&
                          s.category != 'Resolved' &&
                          s.category != 'Sheltered' &&
                          s.category != 'Rehomed' &&
                          s.careStatus != 'resolved' &&
                          (s.resolvedByAction == null ||
                              s.resolvedByAction!.isEmpty) &&
                          (s.isVetVisitPending || s.isPendingVerification) &&
                          (s.pendingVetRescuerId == currentUid ||
                              s.reporterId == currentUid ||
                              s.pendingHandoverRescuerId == currentUid ||
                              (s.rescueClaimed && s.rescueClaimedBy == currentUid)))
                      .firstOrNull;

              final myActiveFosterCareSighting = currentUid == null
                  ? null
                  : allSightings
                      .where((s) =>
                          !_dismissedFosterCareIds.contains(s.id) &&
                          !s.isDeleted &&
                          !s.isFinishedOrResolved &&
                          !s.isResolved &&
                          s.urgency != 'resolved' &&
                          s.urgency != 'communityCare' &&
                          s.careStatus == 'inCare_foster' &&
                          s.careStatus != 'resolved' &&
                          s.careStatus != 'inCare_shelter' &&
                          s.careStatus != 'onStreet' &&
                          s.category != 'Resolved' &&
                          s.category != 'Sheltered' &&
                          s.category != 'Rehomed' &&
                          (s.resolvedByAction == null ||
                              s.resolvedByAction!.isEmpty) &&
                          (s.pendingOutcomeAction == null ||
                              s.pendingOutcomeAction!.isEmpty) &&
                          !s.isSheltered &&
                          !s.isRehomed &&
                          s.lastSeenStatus != 'helpedOffline' &&
                          s.lastSeenStatus != 'sheltered' &&
                          s.lastSeenStatus != 'rehomed' &&
                          s.careTakerId != null &&
                          s.careTakerId == currentUid)
                      .firstOrNull;

              final postVetDecisionSightings = allSightings
                  .where((s) =>
                      s.isAwaitingPostVetDecision &&
                      currentUid != null &&
                      (s.reporterId == currentUid ||
                          s.lastVetRescuerId == currentUid ||
                          s.pendingVetRescuerId == currentUid ||
                          (s.lastVetRescuerId == null && s.rescueClaimedBy == currentUid)))
                  .toList();

              final isLockedWithCat = myActiveRescueTrip != null ||
                  myPendingVetSighting != null ||
                  myActiveFosterCareSighting != null ||
                  postVetDecisionSightings.isNotEmpty;

              final urgentDispatches = isLockedWithCat
                  ? <Sighting>[]
                  : allSightings
                      .where((s) =>
                          s.isEligibleForRadialDispatch &&
                          (currentUid == null || s.reporterId != currentUid) &&
                          !_dismissedDispatchIds.contains(s.id) &&
                          !s.isDispatchDismissedFor(currentUid))
                      .toList();

              return CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  if (myActiveRescueTrip != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: _buildActiveRescueTripBanner(myActiveRescueTrip),
                      ),
                    ),
                  if (myPendingVetSighting != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: _buildPendingVetVerificationBanner(
                            myPendingVetSighting),
                      ),
                    ),
                  if (myActiveFosterCareSighting != null)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: _buildActiveFosterCareReminderBanner(
                            myActiveFosterCareSighting),
                      ),
                    ),
                  if (postVetDecisionSightings.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: _buildPostVetReminderBanner(
                            postVetDecisionSightings.first),
                      ),
                    ),
                  if (urgentDispatches.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        child: _buildRadialDispatchAlertBanner(
                            urgentDispatches.first),
                      ),
                    ),
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
                                    : (_activeFilter == 'My Cases'
                                        ? 'No Cases Related to You Yet 🐾'
                                        : 'No $_activeFilter Sightings 🐾'),
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
                                      : (_activeFilter == 'My Cases'
                                          ? 'Sightings you report or rescues you take part in will appear here, whether active or resolved.'
                                          : 'No reports under "$_activeFilter" right now. Check other filters or post a new sighting.'),
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
    return GestureDetector(
      onTap: _showNotificationsModal,
      behavior: HitTestBehavior.opaque,
      child: Stack(
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
            child: const Icon(Icons.notifications_outlined, color: _navy, size: 22),
          ),
          if (_hasUnreadNotificationsState)
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
      ),
    );
  }

  void _showNotificationsModal() {
    _markAllNotificationsAsRead();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.sizeOf(ctx).height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: _buildDispatchAndNotificationsTab(),
        ),
      ),
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

        return GestureDetector(
          onTap: () => setState(() => _currentTab = 4),
          behavior: HitTestBehavior.opaque,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: profile.trustTierColor.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(color: profile.trustTierColor, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        profile.initials,
                        style: GoogleFonts.nunito(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: profile.trustTierColor,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -3,
                    right: -3,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: profile.trustTierColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Lv.${profile.level}',
                        style: GoogleFonts.nunito(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_rounded, size: 11, color: const Color(0xFFFFA000)),
                  const SizedBox(width: 1),
                  Text(
                    profile.trustScore.toStringAsFixed(1),
                    style: GoogleFonts.nunito(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: _navy.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${profile.totalXp} XP',
                    style: GoogleFonts.nunito(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: _navy.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: 58,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: profile.levelProgress,
                    minHeight: 4,
                    backgroundColor: _lavLight,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(profile.trustTierColor),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: GestureDetector(
                onTap: _toggleHideAllDeletedReports,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: _hideAllDeletedReports
                        ? const Color(0xFFE53935).withValues(alpha: 0.12)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _hideAllDeletedReports
                          ? const Color(0xFFE53935)
                          : _navy.withValues(alpha: 0.15),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _hideAllDeletedReports
                            ? Icons.visibility_off_rounded
                            : Icons.visibility_outlined,
                        size: 14,
                        color: _hideAllDeletedReports
                            ? const Color(0xFFE53935)
                            : _navy.withValues(alpha: 0.7),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _hideAllDeletedReports ? 'Deleted Hidden' : 'Hide Deleted',
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _hideAllDeletedReports
                              ? const Color(0xFFE53935)
                              : _navy.withValues(alpha: 0.75),
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

  Widget _buildChip(String label) {
    final isActive = _activeFilter == label;
    Color chipColor;
    IconData? chipIcon;

    switch (label) {
      case 'My Cases':
        chipColor = const Color(0xFF1E88E5);
        chipIcon = Icons.person_pin_rounded;
        break;
      case 'Adoption Showcase':
        chipColor = const Color(0xFF673AB7);
        chipIcon = Icons.volunteer_activism_rounded;
        break;
      case 'Waiting':
        chipColor = const Color(0xFFF57C00);
        chipIcon = Icons.hourglass_top_rounded;
        break;
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
      case 'Needs Home':
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
    if (data.isDeleted) {
      return _buildDeletedAdminCard(data);
    }
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
                          if (FirebaseService.instance.isCurrentUserAdmin) ...[
                            InkWell(
                              onTap: () => _showAdminQuickDeleteDialog(data),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE53935).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: const Color(0xFFE53935).withValues(alpha: 0.35),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.delete_forever_rounded, size: 12, color: Color(0xFFE53935)),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Delete',
                                      style: GoogleFonts.nunito(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w900,
                                        color: const Color(0xFFE53935),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
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
                      if (data.isAdoptionShowcase) ...[
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
                              const Icon(Icons.volunteer_activism_rounded,
                                  size: 12, color: Color(0xFF673AB7)),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  data.shelterOrClinicName?.isNotEmpty == true
                                      ? '🏡 Ready for Home • ${data.shelterOrClinicName}'
                                      : (data.isSheltered
                                          ? '🏛️ Sheltered • Ready for Adoption'
                                          : '🏡 Ready for Foster / Adoption'),
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
                        if (data.healthTags.isNotEmpty) ...[
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: data.healthTags.take(3).map((tag) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2E7D32).withValues(alpha: 0.09),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                      color: const Color(0xFF2E7D32).withValues(alpha: 0.25)),
                                ),
                                child: Text(
                                  tag,
                                  style: GoogleFonts.nunito(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF2E7D32),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 6),
                        ],
                      ] else if (data.isInCare) ...[
                        Builder(builder: (context) {
                          final isAdoptionState = data.isOpenForAdoption || data.category == 'Needs Home';
                          final badgeColor = isAdoptionState ? const Color(0xFF9C27B0) : const Color(0xFF673AB7);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3.5),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: badgeColor.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(data.careIcon,
                                    size: 12, color: badgeColor),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    isAdoptionState
                                        ? 'Needs Home • with ${data.careTakerName?.isNotEmpty == true ? data.careTakerName : "Foster"}'
                                        : '${data.careLabel} • with ${data.careTakerName?.isNotEmpty == true ? data.careTakerName : "Rescuer"}',
                                    style: GoogleFonts.nunito(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: badgeColor,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ] else if (data.isPendingVerification || data.isAwaitingPostVetDecision) ...[
                        Builder(
                          builder: (context) {
                            final currentUid = FirebaseAuth.instance.currentUser?.uid;
                            final isReporter = currentUid != null && data.reporterId == currentUid;
                            final isRescuer = currentUid != null &&
                                (data.lastVetRescuerId == currentUid ||
                                    data.pendingVetRescuerId == currentUid ||
                                    data.pendingHandoverRescuerId == currentUid ||
                                    (data.rescueClaimed && data.rescueClaimedBy == currentUid));
                            final String badgeText;
                            if (isReporter) {
                              if (data.isAwaitingPostVetDecision) {
                                badgeText = 'Action Required • Decide Next Step';
                              } else {
                                badgeText = 'Action Required • Awaiting Your Verification';
                              }
                            } else if (isRescuer) {
                              if (data.isAwaitingPostVetDecision) {
                                badgeText = 'Waiting for Reporter Decision';
                              } else {
                                badgeText = 'Waiting for Reporter Verification';
                              }
                            } else {
                              badgeText = data.pendingVerificationDescription;
                            }

                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF57C00).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: const Color(0xFFF57C00).withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.hourglass_top_rounded,
                                      size: 12, color: Color(0xFFF57C00)),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      badgeText,
                                      style: GoogleFonts.nunito(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFFF57C00),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
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

  Widget _buildDeletedCardImage(Sighting data) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(18),
      ),
      child: SizedBox(
        width: 105,
        height: 125,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (data.photoUrls.isNotEmpty)
              ColorFiltered(
                colorFilter: const ColorFilter.matrix(<double>[
                  0.2126, 0.7152, 0.0722, 0, 0,
                  0.2126, 0.7152, 0.0722, 0, 0,
                  0.2126, 0.7152, 0.0722, 0, 0,
                  0,      0,      0,      1, 0,
                ]),
                child: PawImage(
                  url: data.photoUrls.first,
                  fit: BoxFit.cover,
                  placeholder: Container(
                    color: _lavender.withValues(alpha: 0.15),
                    child: Center(
                      child: Icon(Icons.pets,
                          size: 36, color: _lavender.withValues(alpha: 0.4)),
                    ),
                  ),
                ),
              )
            else
              Container(
                color: Colors.grey.shade200,
                child: Center(
                  child: Icon(Icons.pets,
                      size: 36, color: Colors.grey.shade400),
                ),
              ),
            Container(
              color: Colors.black.withValues(alpha: 0.38),
            ),
            Center(
              child: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935).withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeletedAdminCard(Sighting data) {
    return GestureDetector(
      onTap: () => _openSightingDetail(data),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFE53935).withValues(alpha: 0.28),
            width: 1.2,
          ),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDeletedCardImage(data),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 10, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _buildAvatar(data.initials, Colors.grey.shade500),
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
                                      color: _navy.withValues(alpha: 0.8),
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    data.timeAgo,
                                    style: GoogleFonts.nunito(
                                      fontSize: 11,
                                      color: _navy.withValues(alpha: 0.45),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE53935).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: const Color(0xFFE53935).withValues(alpha: 0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.gavel_rounded, size: 10, color: Color(0xFFE53935)),
                                  const SizedBox(width: 3),
                                  Text(
                                    'DELETED',
                                    style: GoogleFonts.nunito(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      color: const Color(0xFFE53935),
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => _dismissDeletedReport(data.id),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close_rounded, size: 14, color: Colors.black54),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          data.displayTitle,
                          style: GoogleFonts.nunito(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            color: _navy.withValues(alpha: 0.6),
                            decoration: TextDecoration.lineThrough,
                            decorationColor: const Color(0xFFE53935).withValues(alpha: 0.6),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE53935).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded, size: 12, color: Color(0xFFD32F2F)),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  'Reason: ${data.deletedReason ?? "Violated community guidelines"}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.nunito(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFFC62828),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFE53935).withValues(alpha: 0.04),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(17)),
              ),
              child: Row(
                children: [
                  Icon(Icons.shield_outlined, size: 12, color: _navy.withValues(alpha: 0.45)),
                  const SizedBox(width: 4),
                  Text(
                    'Deleted',
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _navy.withValues(alpha: 0.55),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'View Reason & Details',
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFFE53935),
                    ),
                  ),
                  const SizedBox(width: 3),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 10, color: Color(0xFFE53935)),
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

    if (data.status == 'resolved' ||
        data.urgency == 'resolved' ||
        data.category == 'Resolved') {
      statusColor = _resolved;
      statusLabel = 'Resolved';
      statusIcon = Icons.check_circle;
    } else if (data.isTnrCommunityCat) {
      statusColor = const Color(0xFF00897B);
      statusLabel = 'Community Cat';
      statusIcon = Icons.pets;
    } else if (data.isOpenForAdoption || data.category == 'Needs Home') {
      statusColor = const Color(0xFF9C27B0);
      statusLabel = 'Needs Home';
      statusIcon = Icons.home_outlined;
    } else if (data.isInCare) {
      statusColor = const Color(0xFF673AB7);
      statusLabel = data.careLabel;
      statusIcon = data.careIcon;
    } else if (data.isPendingVerification ||
        data.isAwaitingPostVetDecision ||
        data.status == 'waiting' ||
        data.isVetVisitPending ||
        (data.pendingVetRescuerId != null &&
            data.pendingVetRescuerId!.isNotEmpty) ||
        (data.pendingHandoverRescuerId != null &&
            data.pendingHandoverRescuerId!.isNotEmpty) ||
        (data.pendingOutcomeAction != null &&
            data.pendingOutcomeAction!.isNotEmpty)) {
      statusColor = const Color(0xFFF57C00);
      statusLabel = 'Waiting';
      statusIcon = Icons.hourglass_top_rounded;
    } else if (data.rescueClaimed ||
        data.isRescueClaimActive ||
        data.rescueClaimedBy.isNotEmpty) {
      statusColor = _lavender;
      statusLabel = 'On The Way';
      statusIcon = Icons.directions_run;
    } else if (data.hasVetVisit) {
      statusColor = const Color(0xFF2E7D32);
      statusLabel = 'Vet Checked';
      statusIcon = Icons.verified_rounded;
    } else if (data.status == 'urgent' || data.urgency == 'urgent') {
      statusColor = _urgent;
      statusLabel = 'Urgent';
      statusIcon = Icons.error;
    } else if (data.isNeedsHome) {
      statusColor = _needsHome;
      statusLabel = 'Needs Home';
      statusIcon = Icons.home_rounded;
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
            Positioned.fill(
              child: data.photoUrls.isNotEmpty
                  ? PawImage(
                      url: data.photoUrls.first,
                      fit: BoxFit.cover,
                      placeholder: Container(
                        color: _lavender.withValues(alpha: 0.15),
                        child: Center(
                          child: Icon(Icons.pets,
                              size: 40, color: _lavender.withValues(alpha: 0.4)),
                        ),
                      ),
                    )
                  : Container(
                      color: _lavender.withValues(alpha: 0.15),
                      child: Center(
                        child: Icon(Icons.pets,
                            size: 40, color: _lavender.withValues(alpha: 0.4)),
                      ),
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
      case 'Needs Home':
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
      case 'Community Cat':
      case 'Community Care':
        icon = Icons.pets;
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
    final Color outlineColor = (data.status == 'resolved' || data.urgency == 'resolved')
        ? _resolved
        : (data.isPendingVerification ||
                data.isAwaitingPostVetDecision ||
                data.status == 'waiting')
            ? const Color(0xFFF57C00)
            : data.isInCare
                ? const Color(0xFF673AB7)
                : (data.rescueClaimed ||
                        data.isRescueClaimActive ||
                        data.rescueClaimedBy.isNotEmpty)
                    ? _lavender
                    : (data.hasVetVisit)
                        ? const Color(0xFF2E7D32)
                        : ((data.status == 'urgent' || data.urgency == 'urgent')
                            ? _urgent
                            : (data.isNeedsHome ? _needsHome : _needsHelp));

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
              _buildNavItemWithBadge(3, Icons.chat_bubble_rounded,
                  Icons.chat_bubble_outline_rounded, 'Chats'),
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
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return GestureDetector(
      onTap: () => setState(() => _currentTab = index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StreamBuilder<List<Map<String, dynamic>>>(
              stream: (currentUid != null && currentUid.isNotEmpty)
                  ? FirebaseService.instance.streamUserChatThreads(currentUid)
                  : const Stream.empty(),
              builder: (context, snapshot) {
                final threads = snapshot.data ?? [];
                final hasUnread = threads.any(
                    (t) => FirebaseService.isChatUnread(t, currentUid));

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      isActive ? activeIcon : inactiveIcon,
                      color:
                          isActive ? _lavender : _navy.withValues(alpha: 0.35),
                      size: 24,
                    ),
                    if (hasUnread)
                      Positioned(
                        top: -2,
                        right: -2,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF673AB7),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                );
              },
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

  Widget _buildPostVetReminderBanner(Sighting s) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isReporter = s.reporterId == currentUid;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFF57C00).withValues(alpha: 0.14),
            const Color(0xFFFFA000).withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFF57C00).withValues(alpha: 0.45),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF57C00).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showPostVetRescuerHomeDialog(s),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE65100),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isReporter
                                ? Icons.checklist_rounded
                                : Icons.celebration_rounded,
                            color: Colors.white,
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            isReporter
                                ? 'DECISION REQUIRED'
                                : 'VET VISIT VERIFIED',
                            style: GoogleFonts.nunito(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFA000).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isReporter ? '24h Window' : '+100 XP',
                        style: GoogleFonts.nunito(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFE65100),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  isReporter
                      ? '${s.title.isNotEmpty ? s.title : "Cat Rescue"} • Decide Next Step'
                      : '${s.title.isNotEmpty ? s.title : "Cat Rescue"} • Next Step On Hold',
                  style: GoogleFonts.nunito(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    color: _navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isReporter
                      ? 'Vet visit verified! Please decide within 24 hours between foster care, shelter, or delegating placement to the rescuer.'
                      : 'Reporter verified the vet visit! You have physical custody of this cat. Tap to open details and decide next action.',
                  style: GoogleFonts.nunito(
                    fontSize: 11.5,
                    color: _navy.withValues(alpha: 0.75),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE65100),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () => _showPostVetRescuerHomeDialog(s),
                        icon: const Icon(Icons.touch_app_rounded, size: 16),
                        label: Text(
                          'Decide Next Step 🐾',
                          style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPostVetRescuerHomeDialog(Sighting s) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SightingDetailScreen(sighting: s),
      ),
    );
  }

  Widget _buildActiveRescueTripBanner(Sighting s) {
    final remMins = s.rescueClaimRemainingMinutes;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF4CAF50).withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4CAF50).withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.directions_run_rounded,
                        color: Colors.white, size: 13),
                    const SizedBox(width: 4),
                    Text(
                      'ON MY WAY',
                      style: GoogleFonts.nunito(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF81C784).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timer_outlined,
                          size: 12, color: Color(0xFF1B5E20)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          '$remMins min left',
                          style: GoogleFonts.nunito(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1B5E20),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (s.photoUrls.isNotEmpty)
                PawImage(
                  url: s.photoUrls.first,
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(12),
                  placeholder: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFF81C784).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.pets, size: 22, color: Color(0xFF2E7D32)),
                  ),
                )
              else
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: const Color(0xFF81C784).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.pets, size: 22, color: Color(0xFF2E7D32)),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.title.isNotEmpty ? s.title : "Active Cat Rescue",
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: _navy,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.locationAddress.isNotEmpty ? s.locationAddress : "En route to spot",
                      style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        color: _navy.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SightingDetailScreen(sighting: s),
                  ),
                );
              },
              icon: const Icon(Icons.directions_walk_rounded, size: 16),
              label: Text(
                'Open Active Rescue Mission 🐾',
                style: GoogleFonts.nunito(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingVetVerificationBanner(Sighting s) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isReporter = s.reporterId == currentUid;

    final isHandover = s.pendingHandoverRescuerId != null &&
        s.pendingHandoverRescuerId!.isNotEmpty;
    final isOutcome = s.pendingOutcomeAction != null &&
        s.pendingOutcomeAction!.isNotEmpty;
    final isAdoption = s.pendingAdoptionApplicantId != null &&
        s.pendingAdoptionApplicantId!.isNotEmpty;

    String bannerTitle = s.title.isNotEmpty
        ? s.title
        : (isHandover
            ? "Foster Care Cat"
            : (isOutcome ? "Placement Outcome" : "Vet Care Cat"));
    String subtitleText;
    String badgeLabel;
    IconData badgeIcon;

    if (isHandover) {
      badgeLabel = isReporter ? 'ACTION REQUIRED' : 'FOSTER HANDOVER SUBMITTED';
      badgeIcon = isReporter ? Icons.checklist_rounded : Icons.home_outlined;
      if (isReporter) {
        final rescuer = (s.pendingHandoverRescuerName != null &&
                s.pendingHandoverRescuerName!.isNotEmpty)
            ? s.pendingHandoverRescuerName!
            : "Volunteer";
        subtitleText =
            'Foster custody requested by $rescuer! Tap to review care plan and confirm handover.';
      } else {
        subtitleText =
            'Foster custody request submitted! Waiting for ${s.reporterName.isNotEmpty ? s.reporterName : "reporter"} to confirm handover.';
      }
    } else if (isOutcome) {
      final isShelter = s.pendingOutcomeAction == 'sheltered';
      badgeLabel = isReporter
          ? 'ACTION REQUIRED'
          : (isShelter ? 'SHELTER TRANSFER SUBMITTED' : 'OUTCOME SUBMITTED');
      badgeIcon = isReporter ? Icons.checklist_rounded : Icons.pets_rounded;
      if (isReporter) {
        subtitleText =
            'Outcome update submitted (${s.pendingOutcomeAction})! Tap to review and confirm.';
      } else {
        subtitleText =
            'Outcome confirmation submitted (${s.pendingOutcomeAction})! Waiting for review.';
      }
    } else if (isAdoption) {
      badgeLabel = isReporter ? 'ACTION REQUIRED' : 'ADOPTION REQUEST';
      badgeIcon = isReporter ? Icons.checklist_rounded : Icons.favorite_rounded;
      if (isReporter) {
        subtitleText =
            'Adoption request from ${s.pendingAdoptionApplicantName ?? "an applicant"}! Tap to review.';
      } else {
        subtitleText =
            'Adoption request submitted! Waiting for ${s.reporterName.isNotEmpty ? s.reporterName : "reporter"} to review.';
      }
    } else {
      badgeLabel = isReporter ? 'ACTION REQUIRED' : 'VET CHECK SUBMITTED';
      badgeIcon = isReporter ? Icons.checklist_rounded : Icons.local_hospital_rounded;
      if (isReporter) {
        final rescuerName = (s.pendingVetRescuerName != null &&
                s.pendingVetRescuerName!.isNotEmpty)
            ? s.pendingVetRescuerName!
            : "Rescuer";
        subtitleText =
            '$rescuerName submitted vet clinic proof! Tap to review receipt and confirm care.';
      } else {
        subtitleText =
            'Proof submitted! Waiting for ${s.reporterName.isNotEmpty ? s.reporterName : "reporter"} to verify clinic receipt.';
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF3E5F5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF9C27B0).withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF9C27B0).withValues(alpha: 0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: isReporter ? const Color(0xFFE65100) : const Color(0xFF7B1FA2),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      badgeIcon,
                      color: Colors.white,
                      size: 13,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      badgeLabel,
                      style: GoogleFonts.nunito(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => _dismissPendingVet(s.id),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: _navy.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (s.photoUrls.isNotEmpty)
                PawImage(
                  url: s.photoUrls.first,
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(12),
                  placeholder: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFFCE93D8).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.pets, size: 22, color: Color(0xFF7B1FA2)),
                  ),
                )
              else
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCE93D8).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.pets, size: 22, color: Color(0xFF7B1FA2)),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bannerTitle,
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: _navy,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        color: _navy.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isReporter
                    ? const Color(0xFF7B1FA2)
                    : const Color(0xFF7B1FA2),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SightingDetailScreen(sighting: s),
                  ),
                );
              },
              icon: Icon(
                isReporter
                    ? Icons.verified_rounded
                    : Icons.chat_bubble_outline_rounded,
                size: 16,
              ),
              label: Text(
                isReporter
                    ? (isHandover
                        ? 'Review & Confirm Handover'
                        : isOutcome
                            ? 'Review & Confirm Outcome'
                            : isAdoption
                                ? 'Review & Confirm Adoption'
                                : 'Review & Verify Receipt')
                    : 'View Report & Coordinate Chat',
                style: GoogleFonts.nunito(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveFosterCareReminderBanner(Sighting s) {
    final bannerTitle =
        s.title.isNotEmpty ? s.title : "Foster Cat in Your Care";
    final isAllDone = s.isAllMilestonesCompleted;
    final activeDay = s.nextPendingMilestoneDay;
    final totalDays = s.effectiveDurationDays;

    final String pillText = isAllDone
        ? 'All $totalDays Days Done'
        : 'Day $activeDay of $totalDays';

    final String subtitleText = isAllDone
        ? 'All $totalDays care milestones completed! Foster goals reached. Ready for placement outcome.'
        : 'Day $activeDay is ready: Log feeding, health check, and upload photos for this cat!';

    final String buttonText = isAllDone
        ? 'Care Plan Complete • Decide Final Outcome'
        : 'Open Care Plan & Log Day $activeDay 🐾';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF2E7D32).withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.home_rounded,
                      color: Colors.white,
                      size: 13,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'CAT IN YOUR CARE',
                      style: GoogleFonts.nunito(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  pillText,
                  style: GoogleFonts.nunito(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1B5E20),
                  ),
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => _dismissFosterCare(s.id),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: _navy.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (s.photoUrls.isNotEmpty)
                PawImage(
                  url: s.photoUrls.first,
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(12),
                  placeholder: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: const Color(0xFF81C784).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.pets,
                        size: 22, color: Color(0xFF2E7D32)),
                  ),
                )
              else
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: const Color(0xFF81C784).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.pets,
                      size: 22, color: Color(0xFF2E7D32)),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bannerTitle,
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: _navy,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleText,
                      style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        color: _navy.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SightingDetailScreen(sighting: s),
                  ),
                );
                if (mounted) setState(() {});
              },
              icon: Icon(
                isAllDone
                    ? Icons.check_circle_rounded
                    : Icons.favorite_rounded,
                size: 16,
              ),
              label: Text(
                buttonText,
                style: GoogleFonts.nunito(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRadialDispatchAlertBanner(Sighting s) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFE53935).withValues(alpha: 0.12),
            const Color(0xFFFF7043).withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE53935).withValues(alpha: 0.4),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE53935).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE53935),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.emergency_rounded,
                        color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'URGENT DISPATCH',
                      style: GoogleFonts.nunito(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '•  ~${s.distance} away',
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFE53935),
                ),
              ),
              const Spacer(),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _confirmDeleteDispatchNotification(s.id),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: const Color(0xFFE53935).withValues(alpha: 0.7),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (s.photoUrls.isNotEmpty)
                PawImage(
                  url: s.photoUrls.first,
                  width: 54,
                  height: 54,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(12),
                  placeholder: Container(
                    width: 54,
                    height: 54,
                    color: _lavender.withValues(alpha: 0.2),
                    child: const Icon(Icons.pets, size: 24, color: _lavender),
                  ),
                )
              else
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: _lavender.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.pets, size: 24, color: _lavender),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.displayTitle,
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.displayLocation,
                      style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _navy.withValues(alpha: 0.6),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _navy.withValues(alpha: 0.7),
                    side: BorderSide(color: _navy.withValues(alpha: 0.2)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _dismissDispatch(s.id),
                  child: Text('Can\'t Help',
                      style: GoogleFonts.nunito(
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 2,
                  ),
                  onPressed: () async {
                    final uid = FirebaseAuth.instance.currentUser?.uid;
                    if (uid != null) {
                      final activeTrip = await FirebaseService.instance
                          .getActiveRescueTrip(uid);
                      if (activeTrip != null && activeTrip.id != s.id) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'You already have an active rescue mission in progress! Please finish that trip first. 🏃🐾',
                                style: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w700),
                              ),
                              backgroundColor: const Color(0xFFE65100),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          );
                        }
                        return;
                      }

                      final activeVet = await FirebaseService.instance
                          .getActiveVetCareSighting(uid);
                      if (activeVet != null && activeVet.id != s.id) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'You have a cat in vet custody awaiting verification or decision! Please finish that first. 🩺🐾',
                                style: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w700),
                              ),
                              backgroundColor: const Color(0xFF7B1FA2),
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          );
                        }
                        return;
                      }
                    }
                    try {
                      await FirebaseService.instance.claimRescue(s.id);
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Could not claim rescue: $e',
                              style: GoogleFonts.nunito(
                                  fontWeight: FontWeight.w700),
                            ),
                            backgroundColor: Colors.red.shade700,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                      }
                      return;
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Dispatch accepted! You have a 45-minute arrival window ⏱️🐾',
                            style: GoogleFonts.nunito(
                                fontWeight: FontWeight.w700),
                          ),
                          backgroundColor: _navy,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      );
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) =>
                                SightingDetailScreen(sighting: s)),
                      );
                    }
                  },
                  icon: const Icon(Icons.directions_run_rounded, size: 16),
                  label: Text(
                    'I\'m on my way (45m)',
                    style: GoogleFonts.nunito(
                        fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDispatchAndNotificationsTab() {
    return Column(
      children: [
        Container(
          color: _bgWhite,
          padding: const EdgeInsets.fromLTRB(12, 14, 16, 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, color: _navy, size: 22),
                tooltip: 'Back',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                onPressed: () => Navigator.pop(context),
              ),
              const SizedBox(width: 8),
              Text(
                'Announcements',
                style: GoogleFonts.nunito(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: _navy,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _confirmClearAllNotifications,
                icon: const Icon(Icons.delete_sweep_outlined,
                    size: 18, color: Color(0xFFE53935)),
                label: Text(
                  'Clear All',
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFFE53935),
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
        Divider(color: _navy.withValues(alpha: 0.08), height: 1),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: FirebaseService.instance.streamAnnouncements(),
            builder: (context, annSnapshot) {
              final rawAnnouncements = annSnapshot.data ?? [];
              final announcements = rawAnnouncements
                  .where((a) =>
                      a['docId'] != null &&
                      !_dismissedAnnouncementIds.contains(a['docId'].toString()))
                  .toList();

              if (announcements.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: _lavender.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.campaign_outlined,
                              size: 44,
                              color: _lavender.withValues(alpha: 0.6)),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No Announcements Yet 🐾',
                          style: GoogleFonts.nunito(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Stay tuned here for community news, clinic dates, adoption drives, and official notices from the team.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            color: _navy.withValues(alpha: 0.6),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  Row(
                    children: [
                      const Icon(Icons.campaign_rounded,
                          color: Color(0xFF6C3FC5), size: 17),
                      const SizedBox(width: 6),
                      Text(
                        'OFFICIAL ANNOUNCEMENTS (${announcements.length})',
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF6C3FC5),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...announcements.map((a) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildAnnouncementNotificationCard(a),
                      )),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAnnouncementNotificationCard(Map<String, dynamic> a) {
    final docId = a['docId']?.toString() ?? '';
    final title = a['title']?.toString() ?? 'Announcement';
    final body = a['body']?.toString() ?? '';
    final category = a['category']?.toString() ?? 'general';
    final ts = a['createdAt'] as Timestamp?;
    final timeStr = ts != null
        ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}'
        : 'Recent';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFF9F6FF), Color(0xFFFFFFFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6C3FC5).withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C3FC5).withValues(alpha: 0.05),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C3FC5).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.campaign_rounded, size: 13, color: Color(0xFF6C3FC5)),
                    const SizedBox(width: 4),
                    Text(
                      category.toUpperCase(),
                      style: GoogleFonts.nunito(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF6C3FC5),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.verified_rounded, size: 12, color: Color(0xFF6C3FC5)),
                  const SizedBox(width: 3),
                  Text(
                    'PawWatch Team',
                    style: GoogleFonts.nunito(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6C3FC5),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '• $timeStr',
                    style: GoogleFonts.nunito(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: _navy.withValues(alpha: 0.45),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _confirmDeleteAnnouncement(docId),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.delete_outline_rounded,
                        size: 16,
                        color: _navy.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.nunito(
              fontSize: 14.5,
              fontWeight: FontWeight.w800,
              color: _navy,
            ),
          ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              body,
              style: GoogleFonts.nunito(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _navy.withValues(alpha: 0.75),
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
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


