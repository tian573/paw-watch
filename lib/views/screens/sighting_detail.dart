import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../../models/sighting.dart';
import '../../models/user_profile.dart';
import '../../services/firebase_service.dart';
import '../../services/ai_service.dart';
import '../../services/location_service.dart';
import '../../services/text_moderation_service.dart';
import 'chat_screen.dart';
import '../widgets/paw_image.dart';
import '../widgets/reel_video_player.dart';
import '../widgets/shelter_picker_view.dart';
import '../../utils/double_tap_guard.dart';

class SightingDetailScreen extends StatefulWidget {
  final Sighting sighting;
  final String? initialAction;
  const SightingDetailScreen({super.key, required this.sighting, this.initialAction});
  @override
  State<SightingDetailScreen> createState() => _SightingDetailScreenState();
}

class _SightingDetailScreenState extends State<SightingDetailScreen> {
  static const Color _navy = Color(0xFF1B2A4A);
  static const Color _lavender = Color(0xFF9B8EC4);
  static const Color _lavLight = Color(0xFFEDE9F7);
  static const Color _bgWhite = Color(0xFFFAF9F7);
  static const Color _urgent = Color(0xFFE53935);
  static const Color _resolved = Color(0xFF2E7D32);
  static const Color _cardBg = Color(0xFFFFFFFF);

  final _aiService = AiValidationService();
  final _picker = ImagePicker();
  final _commentCtrl = TextEditingController();
  final _replyCtrl = TextEditingController();
  final _actionsScrollController = ScrollController();
  int _photoPage = 0;
  String? _replyingToId;
  String? _replyingToName;
  bool _isAnon = false;
  bool _hasActed = false;
  String? _myAction;
  bool _isPostingComment = false;
  static DateTime? _lastGlobalCommentAt;
  static String? _lastGlobalCommentText;
  static const Duration _commentCooldownDuration = Duration(seconds: 15);
  bool _isActionSheetOpen = false;

  String? _validateCommentSpam(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 'Please enter a comment.';
    if (trimmed.length < 2) return 'Comment is too short.';

    // Content moderation: check profanity, emoji-only, and gibberish spam
    final modError = TextModerationService.validateComment(trimmed);
    if (modError != null) return modError;

    // 1. Anti-spam: Rate-limit cooldown
    if (_lastGlobalCommentAt != null) {
      final elapsed = DateTime.now().difference(_lastGlobalCommentAt!);
      if (elapsed < _commentCooldownDuration) {
        final remaining = (_commentCooldownDuration - elapsed).inSeconds + 1;
        return '⏳ Please wait ${remaining}s before posting another comment (spam cooldown).';
      }
    }

    // 2. Anti-spam: Duplicate comment filter within 2 minutes
    if (_lastGlobalCommentText != null &&
        _lastGlobalCommentText!.toLowerCase() == trimmed.toLowerCase()) {
      if (_lastGlobalCommentAt != null &&
          DateTime.now().difference(_lastGlobalCommentAt!) <
              const Duration(minutes: 2)) {
        return '⚠️ Duplicate comment detected. Please avoid posting identical messages.';
      }
    }

    // 3. Anti-spam: Excessive repeated characters (e.g. 5+ identical consecutive chars)
    final repeatedCharRegex = RegExp(r'(.)\1{5,}');
    if (repeatedCharRegex.hasMatch(trimmed)) {
      return '⚠️ Your comment contains repetitive characters. Please write a meaningful message.';
    }

    return null;
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  late final Stream<Sighting?> _sightingStream;

  @override
  void initState() {
    super.initState();
    _sightingStream =
        FirebaseService.instance.streamSightingById(widget.sighting.id);
    if (widget.initialAction != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (widget.initialAction == 'returnedToSpot') {
            _confirmReturnToSpot(widget.sighting);
          } else if (widget.initialAction == 'askCommunity') {
            _showRequestCommunityFosterDialog(widget.sighting);
          } else {
            _showActionProofSheet(widget.initialAction!, widget.sighting);
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    _replyCtrl.dispose();
    _actionsScrollController.dispose();
    super.dispose();
  }

  bool _isOwner(Sighting s) => _uid != null && _uid == s.reporterId;

  bool _isVetRescuer(Sighting s) {
    final uid = _uid;
    if (uid == null) return false;

    // 1. Explicitly designated as the vet rescuer
    if (s.lastVetRescuerId == uid) return true;
    if (s.pendingVetRescuerId == uid) return true;

    // 2. If a specific different rescuer is recorded, current user is not the vet rescuer
    if (s.lastVetRescuerId != null &&
        s.lastVetRescuerId!.isNotEmpty &&
        s.lastVetRescuerId != uid) {
      return false;
    }
    if (s.pendingVetRescuerId != null &&
        s.pendingVetRescuerId!.isNotEmpty &&
        s.pendingVetRescuerId != uid) {
      return false;
    }

    // 3. If someone explicitly claimed the rescue
    if (s.rescueClaimedBy.isNotEmpty) {
      return s.rescueClaimedBy == uid;
    }

    // 4. No separate rescuer is recorded. If current user is the reporter,
    // they provided veterinary care and have physical custody!
    if (_isOwner(s)) {
      return true;
    }

    return false;
  }

  bool _hasWaitingStatus(Sighting s) {
    if (s.urgency == 'resolved') return false;
    return s.isVetVisitPending ||
        (s.pendingHandoverRescuerId != null &&
            s.pendingHandoverRescuerId!.isNotEmpty) ||
        (s.pendingOutcomeAction != null &&
            s.pendingOutcomeAction!.isNotEmpty) ||
        (s.pendingAdoptionApplicantId != null &&
            s.pendingAdoptionApplicantId!.isNotEmpty) ||
        s.isAwaitingPostVetDecision;
  }

  bool _isInvolvedInWaitingStatus(Sighting s) {
    if (_uid == null) return false;
    final isReporter = _isOwner(s);
    final isRescuer = _isVetRescuer(s) ||
        s.pendingVetRescuerId == _uid ||
        s.pendingHandoverRescuerId == _uid ||
        s.pendingAdoptionApplicantId == _uid ||
        s.careTakerId == _uid ||
        (s.rescueClaimed && s.rescueClaimedBy == _uid);
    return isReporter || isRescuer;
  }



  static const _aLabels = {
    'fed': 'Fed',
    'vet': 'Vet Visit',
    'tookIn': 'Took In',
    'sheltered': 'Sheltered',
    'rehomed': 'Rehomed',
    'stillHere': 'Still Here',
    'moved': 'Moved Nearby',
    'notHere': 'Not Here',
    'holding': 'In Holding',
    'roaming': 'Still Here / Move',
  };
  static const _aXp = {
    'fed': 30,
    'vet': 100,
    'tookIn': 150,
    'sheltered': 120,
    'rehomed': 200,
    'stillHere': 15,
    'moved': 25,
    'notHere': 10,
    'holding': 100,
    'roaming': 20,
  };

  Color _aColor(String a) {
    const m = {
      'fed': Color(0xFFE53935),
      'vet': Color(0xFFFF8C00),
      'tookIn': Color(0xFF2E7D32),
      'sheltered': Color(0xFF1565C0),
      'rehomed': Color(0xFF9B8EC4),
      'stillHere': Color(0xFF43A047),
      'moved': Color(0xFFFF9800),
      'notHere': Color(0xFF78909C),
      'holding': Color(0xFF9C27B0),
      'roaming': Color(0xFFFF9800),
    };
    return m[a] ?? Colors.grey;
  }

  IconData _aIcon(String a) {
    const m = {
      'fed': Icons.restaurant,
      'vet': Icons.medical_services,
      'tookIn': Icons.home,
      'sheltered': Icons.house,
      'rehomed': Icons.favorite,
      'stillHere': Icons.check_circle_outline,
      'moved': Icons.edit_location_alt_outlined,
      'notHere': Icons.search_off_outlined,
      'holding': Icons.home_work_outlined,
      'roaming': Icons.edit_location_alt_outlined,
    };
    return m[a] ?? Icons.pets;
  }

  String _fmtTime(dynamic ts) {
    if (ts == null) return 'just now';
    DateTime dt;
    try {
      dt = ts.toDate();
    } catch (_) {
      return 'just now';
    }
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${(d.inDays / 7).floor()}w ago';
  }

  String _fmtFullDateTime(dynamic ts) {
    if (ts == null) return 'Date & time not available';
    DateTime dt;
    try {
      if (ts is DateTime) {
        dt = ts;
      } else {
        dt = (ts as dynamic).toDate();
      }
    } catch (_) {
      return 'Recent';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final weekday = days[dt.weekday - 1];
    final month = months[dt.month - 1];
    final hour = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final min = dt.minute.toString().padLeft(2, '0');
    return '$weekday, ${dt.day} $month ${dt.year} • $hour:$min $period';
  }

  String? _getCustomNote(Map<String, dynamic> u) {
    final note = u['customNote']?.toString().trim();
    if (note != null && note.isNotEmpty) return note;

    final text = (u['text'] ?? '').toString();
    if (u['type'] == 'milestoneCheckIn' && text.contains(' • ')) {
      final parts = text.split(' • ');
      if (parts.length > 1) {
        return parts.sublist(1).join(' • ').replaceAll('🐾', '').trim();
      }
    }
    final quoteMatch = RegExp(r'"([^"]+)"$').firstMatch(text.trim());
    if (quoteMatch != null && u['type'] != 'milestoneCheckIn') {
      return quoteMatch.group(1);
    }
    return null;
  }

  String _getCleanSummaryText(Map<String, dynamic> u) {
    final type = u['type'] ?? 'comment';
    final action = u['action'] as String?;
    final isMilestone = type == 'milestoneCheckIn';
    final isAdoptionOpened = type == 'adoptionOpened';
    final isOutcomeResolved = type == 'outcomeResolved';
    final isOutcomeRequest = type == 'outcomeRequest';
    final isCustodyRequest = type == 'custodyRequest';
    final isHandoverApproved = type == 'handoverApproved';
    final isAct = type == 'action';
    final isWay = type == 'onMyWay';
    final isWayCancelled = type == 'onMyWayCancelled';
    final isTripCancelled = u['isCancelled'] == true;

    if (isTripCancelled) return 'cancelled their rescue trip.';
    if (isWayCancelled) return 'cancelled the rescue.';
    if (isAdoptionOpened) {
      return 'completed foster rehabilitation and officially opened this cat for permanent adoption! 🏡🐾';
    }
    if (isOutcomeResolved || isOutcomeRequest) {
      if (action == 'rehomed') {
        return 'successfully rehomed this cat with a loving forever family! 🏡🎉';
      } else if (action == 'sheltered') {
        return 'safely transferred this cat to an animal shelter partner! 🏛️🐾';
      } else {
        return 'completed recovery care and safely returned this cat to its territory! 🌿🐾';
      }
    }
    if (isCustodyRequest) {
      final days = u['carePlanDurationDays'] ?? 3;
      final goal = u['carePlanGoal'] ?? 'Foster & Welfare Care';
      return 'offered to take this cat into Foster Care for $days days ($goal). 🐾';
    }
    if (isHandoverApproved) {
      return 'approved custody handover! Foster care plan is now active. 🏡🐾';
    }
    if (isMilestone) {
      final day = u['milestoneDay'] ?? 1;
      final cond = (u['conditionStatus'] ?? '').toString().trim();
      if (cond.isNotEmpty) {
        return 'completed Day $day Care Check-In ("$cond") 🐾';
      }
      return 'completed Day $day Care Check-In 🐾';
    }
    if (isAct) {
      final rawText = (u['text'] ?? '').toString();
      final cNote = (u['customNote'] ?? '').toString().trim();
      if (cNote.isNotEmpty && rawText.contains('"$cNote"')) {
        return rawText.replaceAll('"$cNote"', '').trim();
      }
      if (rawText.contains(' • ')) {
        return rawText.split(' • ').first.trim();
      }
      return rawText;
    }
    if (isWay) {
      return 'is on the way to rescue!';
    }
    return (u['text'] ?? '').toString();
  }

  Color _avColor(String n) {
    final c = [
      const Color(0xFF7986CB), const Color(0xFF26A69A), const Color(0xFFEC407A),
      const Color(0xFFFF7043), const Color(0xFF66BB6A), const Color(0xFFAB47BC)
    ];
    return c[n.hashCode.abs() % c.length];
  }

  String _ini(String n) {
    final p = n.trim().split(' ');
    if (p.length >= 2 && p[0].isNotEmpty && p[1].isNotEmpty) {
      return (p[0][0] + p[1][0]).toUpperCase();
    }
    if (n.length >= 2) return n.substring(0, 2).toUpperCase();
    return n.isEmpty ? 'PW' : n[0].toUpperCase();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.nunito(fontWeight: FontWeight.w600)),
      backgroundColor: _navy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _openMaps(Sighting s) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${s.effectiveLatitude},${s.effectiveLongitude}');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _showMore(Sighting s) {
    if (!DoubleTapGuard.allow('show_more_${s.id}', thresholdMs: 800)) return;
    showModalBottomSheet(
        context: context, backgroundColor: Colors.transparent, builder: (_) => _moreMenu(s));
  }

  void _showEdit(Sighting s) {
    if (!DoubleTapGuard.allow('show_edit_${s.id}', thresholdMs: 800)) return;
    final tc = TextEditingController(text: s.title);
    final dc = TextEditingController(text: s.description);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: _editSheet(s, tc, dc),
      ),
    );
  }

  void _confirmDelete(Sighting s) {
    if (!DoubleTapGuard.allow('confirm_delete_${s.id}', thresholdMs: 800)) return;
    Navigator.pop(context);
    final hasActiveInvestment = s.hasVetVisit ||
        s.isVetVisitPending ||
        s.isInCare ||
        s.rescueClaimed ||
        s.isResolved;

    if (hasActiveInvestment) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: [
              const Icon(Icons.lock_rounded, color: Color(0xFFE65100), size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Cannot Delete Report',
                    style: GoogleFonts.nunito(
                        fontWeight: FontWeight.w800,
                        color: _navy,
                        fontSize: 16.5)),
              ),
            ],
          ),
          content: Text(
            'This report cannot be deleted because a rescuer or clinic has already committed time, medical care, or custody to this cat (vet visit logged, foster custody active, or rescue mission underway).\n\nTo protect rescue accountability and medical records, active rescue posts remain permanent. You can coordinate next steps via chat or mark the report as resolved when completed.',
            style: GoogleFonts.nunito(
                fontSize: 12.5,
                color: _navy.withValues(alpha: 0.75),
                height: 1.4),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Navigator.pop(context),
              child: Text('Understood',
                  style: GoogleFonts.nunito(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Delete Report?',
            style: GoogleFonts.nunito(fontWeight: FontWeight.w800, color: _navy)),
        content: Text('This will permanently delete your sighting report.',
            style: GoogleFonts.nunito(color: _navy.withValues(alpha: 0.65))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.nunito(color: _navy))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await FirebaseService.instance.deleteSighting(s.id);
                if (mounted) Navigator.pop(context, true);
              } catch (e) {
                if (mounted) {
                  _snack('$e');
                }
              }
            },
            child: Text('Delete',
                style: GoogleFonts.nunito(color: _urgent, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _showFlag(Sighting s) {
    if (!DoubleTapGuard.allow('show_flag_${s.id}', thresholdMs: 800)) return;
    Navigator.pop(context);
    final reasons = [
      'Fake cat / re-photographed screen',
      'Fake or inaccurate location',
      'Cat not here / already gone',
      'Not a cat / wrong animal',
      'Spam or duplicate',
      'Inappropriate / graphic content',
      'Other'
    ];
    String? sel = reasons[0];
    final customController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (c2, ss) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('Flag this Sighting',
              style: GoogleFonts.nunito(fontWeight: FontWeight.w800, color: _navy)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...reasons.map((r) => RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(r,
                          style: GoogleFonts.nunito(
                              fontSize: 13, fontWeight: FontWeight.w600, color: _navy)),
                      value: r,
                      groupValue: sel,
                      activeColor: _lavender,
                      onChanged: (v) => ss(() => sel = v),
                    )),
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
                  controller: customController,
                  maxLines: 2,
                  maxLength: 250,
                  style: GoogleFonts.nunito(fontSize: 12.5, color: _navy),
                  decoration: InputDecoration(
                    hintText: 'Explain why you are reporting this sighting...',
                    hintStyle: GoogleFonts.nunito(
                      fontSize: 12,
                      color: _navy.withValues(alpha: 0.4),
                    ),
                    filled: true,
                    fillColor: Colors.grey.withValues(alpha: 0.06),
                    contentPadding: const EdgeInsets.all(10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _navy.withValues(alpha: 0.12)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _navy.withValues(alpha: 0.12)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _lavender, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: GoogleFonts.nunito(color: _navy))),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final extra = customController.text.trim();
                final fullReason = extra.isNotEmpty ? '${sel ?? ""}: $extra' : (sel ?? '');
                await FirebaseService.instance.flagSighting(s.id, fullReason);
                if (mounted) _snack('Sighting reported. Thank you!');
              },
              child: Text('Submit',
                  style: GoogleFonts.nunito(color: _urgent, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  void _showCommentMenu(Map<String, dynamic> c, Sighting s) {
    if (!DoubleTapGuard.allow('show_comment_menu', thresholdMs: 800)) return;
    final isOwn = _uid != null && c['authorId'] == _uid;
    final isPostReporter = _isOwner(s);
    final isNormalComment = c['type'] == null || c['type'] == 'comment';
    final canBlock = isPostReporter && isNormalComment;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _navy.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                if (isOwn) ...[
                  ListTile(
                    leading: const Icon(Icons.edit_note_rounded, color: _lavender),
                    title: Text(
                        isNormalComment
                            ? 'Edit Message'
                            : 'Edit Custom Note',
                        style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w700, color: _navy)),
                    subtitle: Text(
                        isNormalComment
                            ? 'Edit your comment message'
                            : 'Update your custom note details',
                        style: GoogleFonts.nunito(
                            fontSize: 12, color: _navy.withValues(alpha: 0.5))),
                    onTap: () {
                      Navigator.pop(context);
                      _showEditCommentSheet(c, s.id);
                    },
                  ),
                  if (isNormalComment) ...[
                    ListTile(
                      leading: const Icon(Icons.delete_outline_rounded, color: _urgent),
                      title: Text('Delete Comment',
                          style: GoogleFonts.nunito(
                              fontWeight: FontWeight.w700, color: _urgent)),
                      subtitle: Text('Permanently remove your comment',
                          style: GoogleFonts.nunito(
                              fontSize: 12, color: _navy.withValues(alpha: 0.5))),
                      onTap: () {
                        Navigator.pop(context);
                        _confirmDeleteComment(c, s);
                      },
                    ),
                  ] else ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _lavLight.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _lavender.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 16, color: _lavender),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Rescue action logs are permanently recorded in the kitten\'s care timeline to preserve verified rescue history and reputation points.',
                                style: GoogleFonts.nunito(
                                  fontSize: 11.5,
                                  color: _navy.withValues(alpha: 0.7),
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ] else ...[
                  if (isPostReporter && isNormalComment) ...[
                    ListTile(
                      leading: const Icon(Icons.delete_outline_rounded, color: _urgent),
                      title: Text('Remove Comment',
                          style: GoogleFonts.nunito(
                              fontWeight: FontWeight.w700, color: _urgent)),
                      subtitle: Text('Remove this comment from your sighting report',
                          style: GoogleFonts.nunito(
                              fontSize: 12, color: _navy.withValues(alpha: 0.5))),
                      onTap: () {
                        Navigator.pop(context);
                        _confirmDeleteComment(c, s);
                      },
                    ),
                  ],
                  ListTile(
                    leading: Icon(
                        canBlock ? Icons.block_rounded : Icons.flag_outlined,
                        color: _urgent),
                    title: Text(
                        canBlock
                            ? 'Report & Block'
                            : (isNormalComment
                                ? 'Report Comment'
                                : 'Report Update'),
                        style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w700, color: _urgent)),
                    subtitle: Text(
                        canBlock
                            ? 'Report inappropriate comment and block user from this report'
                            : (isNormalComment
                                ? 'Report inappropriate comment to admin'
                                : 'Report community post update to admin for review'),
                        style: GoogleFonts.nunito(
                            fontSize: 12, color: _navy.withValues(alpha: 0.5))),
                    onTap: () {
                      Navigator.pop(context);
                      _showReportCommentDialog(c, s);
                    },
                  ),
                ],
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.close, color: _navy.withValues(alpha: 0.4)),
                  title: Text('Cancel',
                      style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w600,
                          color: _navy.withValues(alpha: 0.6))),
                  onTap: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDeleteComment(Map<String, dynamic> c, Sighting s) {
    if (!DoubleTapGuard.allow('delete_comment_${c['id'] ?? ''}', thresholdMs: 800)) return;
    final commentId = c['id']?.toString() ?? '';
    if (commentId.isEmpty) return;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _urgent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded, color: _urgent, size: 22),
            ),
            const SizedBox(width: 12),
            Text(
              'Delete Comment?',
              style: GoogleFonts.nunito(
                fontWeight: FontWeight.w800,
                color: _navy,
                fontSize: 18,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete this comment? This action cannot be undone.',
          style: GoogleFonts.nunito(
            fontSize: 14,
            color: _navy.withValues(alpha: 0.75),
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              'Cancel',
              style: GoogleFonts.nunito(
                fontWeight: FontWeight.w700,
                color: _navy.withValues(alpha: 0.6),
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _urgent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await FirebaseService.instance.deleteComment(
                  sightingId: s.id,
                  commentId: commentId,
                );
                if (mounted) {
                  _snack('Comment deleted.');
                }
              } catch (e) {
                if (mounted) {
                  _snack('Failed to delete comment: $e');
                }
              }
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

  void _showEditCommentSheet(Map<String, dynamic> c, String sightingId) {
    if (!DoubleTapGuard.allow('show_edit_comment', thresholdMs: 800)) return;
    final isActionOrUpdate = c['type'] != null && c['type'] != 'comment';
    final currentNote = _getCustomNote(c) ?? (c['text'] ?? '');
    final editCtrl = TextEditingController(text: currentNote);
    String? validationError;
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (sheetContext, setModalState) {
            final bottomPadding = MediaQuery.paddingOf(ctx).bottom;
            return Padding(
              padding:
                  EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: EdgeInsets.fromLTRB(
                    16, 16, 16, bottomPadding > 0 ? bottomPadding + 16 : 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: _navy.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      isActionOrUpdate ? 'Edit Custom Note' : 'Edit Message',
                      style: GoogleFonts.nunito(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: _navy),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isActionOrUpdate
                          ? 'Update the custom note or details for your community update post.'
                          : 'Update your message for this sighting.',
                      style: GoogleFonts.nunito(
                          fontSize: 12,
                          color: _navy.withValues(alpha: 0.5)),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: editCtrl,
                      maxLines: 4,
                      maxLength: 400,
                      onChanged: (val) {
                        setModalState(() {
                          validationError = TextModerationService.validateDescription(
                            val,
                            fieldName: isActionOrUpdate ? 'Custom note' : 'Message',
                          );
                        });
                      },
                      style: GoogleFonts.nunito(
                          fontSize: 14,
                          color: _navy,
                          fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: isActionOrUpdate
                            ? 'Enter updated custom note...'
                            : 'Edit your comment...',
                        errorText: validationError,
                        errorMaxLines: 2,
                        filled: true,
                        fillColor: _lavLight,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: validationError != null
                                ? const Color(0xFFE53935)
                                : BorderSide.none.color,
                            width: validationError != null ? 1.5 : 0,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: validationError != null
                                ? const Color(0xFFE53935)
                                : Colors.transparent,
                            width: validationError != null ? 1.5 : 0,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: validationError != null
                                ? const Color(0xFFE53935)
                                : _lavender,
                            width: 1.5,
                          ),
                        ),
                        counterStyle: GoogleFonts.nunito(
                            fontSize: 11,
                            color: _navy.withValues(alpha: 0.4)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (validationError != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFEF5350)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFD32F2F)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                validationError!,
                                style: GoogleFonts.nunito(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFB71C1C),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _lavender,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: isSaving
                            ? null
                            : () async {
                                if (!DoubleTapGuard.allow('edit_comment_${c['id']}')) return;
                                setModalState(() => isSaving = true);
                                final err = TextModerationService.validateDescription(
                                  editCtrl.text,
                                  fieldName: isActionOrUpdate ? 'Custom note' : 'Message',
                                );
                                if (err != null) {
                                  setModalState(() {
                                    isSaving = false;
                                    validationError = err;
                                  });
                                  DoubleTapGuard.reset('edit_comment_${c['id']}');
                                  _snack('⚠️ $err');
                                  return;
                                }
                                try {
                                  await FirebaseService.instance.editCommunityUpdateNote(
                                    sightingId: sightingId,
                                    updateId: c['id'] ?? '',
                                    newCustomNote: editCtrl.text,
                                  );
                                  if (sheetContext.mounted) {
                                    Navigator.pop(sheetContext);
                                  }
                                  if (mounted) {
                                    _snack(isActionOrUpdate
                                        ? 'Custom note updated! ✨'
                                        : 'Comment updated! ✨');
                                  }
                                } catch (e) {
                                  setModalState(() => isSaving = false);
                                  _snack('Failed to update: $e');
                                }
                              },
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text('Save Changes',
                                style: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
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

  void _showUpdateDetailsModal(Map<String, dynamic> u, Sighting s) {
    final action = u['action'] as String?;
    final type = u['type'] ?? 'comment';
    final name = u['authorName'] ?? 'Anonymous';
    final isAnon = u['isAnonymous'] == true;
    final dName = isAnon ? 'Anonymous' : name;
    final isOwn = _uid != null && u['authorId'] == _uid;
    final cleanSummary = _getCleanSummaryText(u);
    final customNote = _getCustomNote(u);
    final fullDateTime = _fmtFullDateTime(u['createdAt']);
    final relativeTime = _fmtTime(u['createdAt']);
    final proofPhotoUrl = (u['proofPhotoUrl'] ?? u['photoUrl'])?.toString();
    final proofVideoUrl = (u['proofVideoUrl'] ??
            u['videoUrl'] ??
            u['outcomeVideoUrl'] ??
            (u['type'] == 'outcomeResolved' ? s.outcomeVideoUrl : null))
        ?.toString();
    final hasPhoto = proofPhotoUrl != null && proofPhotoUrl.isNotEmpty;
    final hasVideo = proofVideoUrl != null && proofVideoUrl.isNotEmpty;
    final shelterName = u['shelterOrClinicName']?.toString();
    final locationAddr = (u['updatedLocationAddress'] ??
            u['shelterAddress'] ??
            u['locationAddress'])
        ?.toString();
    final condStatus = u['conditionStatus']?.toString();
    final careGoal = u['carePlanGoal']?.toString();
    final xp = u['xpAwarded'] ?? u['pendingXp'];
    final dayNum = u['milestoneDay'];

    String categoryLabel;
    Color categoryColor;
    IconData categoryIcon;

    if (type == 'milestoneCheckIn') {
      categoryLabel = 'Day ${dayNum ?? 1} Care Check-In';
      categoryColor = const Color(0xFFFFA000);
      categoryIcon = Icons.assignment_turned_in_rounded;
    } else if (type == 'adoptionOpened') {
      categoryLabel = 'Adoption Opened 🏡';
      categoryColor = const Color(0xFFE65100);
      categoryIcon = Icons.volunteer_activism_rounded;
    } else if (type == 'outcomeResolved' || type == 'outcomeRequest') {
      categoryLabel = action == 'rehomed'
          ? 'Permanently Rehomed 🏡'
          : (action == 'sheltered'
              ? 'Shelter Transfer 🏛️'
              : 'Returned (TNR) 🌿');
      categoryColor = const Color(0xFF2E7D32);
      categoryIcon = action == 'rehomed'
          ? Icons.celebration_rounded
          : (action == 'sheltered' ? Icons.house_rounded : Icons.pets_rounded);
    } else if (type == 'custodyRequest') {
      categoryLabel = 'Foster Custody Request';
      categoryColor = const Color(0xFF673AB7);
      categoryIcon = Icons.handshake_rounded;
    } else if (type == 'handoverApproved') {
      categoryLabel = 'Custody Transferred';
      categoryColor = const Color(0xFF2E7D32);
      categoryIcon = Icons.verified_rounded;
    } else if (type == 'onMyWay') {
      categoryLabel = u['isCancelled'] == true ? 'Trip Cancelled' : 'On My Way';
      categoryColor =
          u['isCancelled'] == true ? const Color(0xFF78909C) : _lavender;
      categoryIcon = Icons.directions_run_rounded;
    } else if (type == 'onMyWayCancelled') {
      categoryLabel = 'Rescue Cancelled';
      categoryColor = const Color(0xFF78909C);
      categoryIcon = Icons.person_off_rounded;
    } else if (type == 'action') {
      categoryLabel = _aLabels[action] ?? (action ?? 'Rescue Action');
      categoryColor = _aColor(action ?? '');
      categoryIcon = _aIcon(action ?? '');
    } else {
      categoryLabel = 'Community Comment';
      categoryColor = _lavender;
      categoryIcon = Icons.chat_bubble_outline_rounded;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final maxHeight = MediaQuery.sizeOf(ctx).height * 0.88;
        final bottomInset = MediaQuery.paddingOf(ctx).bottom;
        return Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            bottom: true,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  decoration: BoxDecoration(
                    color: _navy.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: categoryColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(categoryIcon, size: 14, color: categoryColor),
                          const SizedBox(width: 5),
                          Text(
                            categoryLabel,
                            style: GoogleFonts.nunito(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: categoryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      color: _navy.withValues(alpha: 0.6),
                      onPressed: () => Navigator.pop(ctx),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                      16, 12, 16, 32 + (bottomInset > 0 ? bottomInset : 16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: categoryColor,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                _ini(isAnon ? 'AN' : name),
                                style: GoogleFonts.nunito(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      dName,
                                      style: GoogleFonts.nunito(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: _navy,
                                      ),
                                    ),
                                    if (!isAnon) ...[
                                      const SizedBox(width: 4),
                                      Icon(Icons.shield_outlined,
                                          size: 13, color: _lavender),
                                    ],
                                  ],
                                ),
                                Text(
                                  relativeTime,
                                  style: GoogleFonts.nunito(
                                    fontSize: 11,
                                    color: _navy.withValues(alpha: 0.45),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (xp != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF2E7D32)
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '+$xp XP',
                                style: GoogleFonts.nunito(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF2E7D32),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: _bgWhite,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _navy.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today_rounded,
                                size: 16, color: _lavender),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                fullDateTime,
                                style: GoogleFonts.nunito(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: _navy,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Status Summary',
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: _navy.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: categoryColor.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: categoryColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              cleanSummary,
                              style: GoogleFonts.nunito(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _navy,
                                height: 1.4,
                              ),
                            ),
                            if (condStatus != null &&
                                condStatus.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.favorite_rounded,
                                      size: 13, color: categoryColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Condition: $condStatus',
                                    style: GoogleFonts.nunito(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: categoryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (careGoal != null &&
                                careGoal.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.flag_rounded,
                                      size: 13, color: categoryColor),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Foster Goal: $careGoal',
                                    style: GoogleFonts.nunito(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: categoryColor,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (shelterName != null &&
                                shelterName.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.house_rounded,
                                      size: 13, color: categoryColor),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Shelter: $shelterName',
                                      style: GoogleFonts.nunito(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: categoryColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            if (locationAddr != null &&
                                locationAddr.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(Icons.location_on_rounded,
                                      size: 13, color: categoryColor),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'Location: $locationAddr',
                                      style: GoogleFonts.nunito(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: categoryColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Icon(Icons.edit_note_rounded,
                              size: 16, color: _lavender),
                          const SizedBox(width: 4),
                          Text(
                            'Custom Note / Details',
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: _navy.withValues(alpha: 0.6),
                            ),
                          ),
                          const Spacer(),
                          if (isOwn)
                            InkWell(
                              onTap: () {
                                Navigator.pop(ctx);
                                _showEditCommentSheet(u, s.id);
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.edit_outlined,
                                        size: 13, color: _lavender),
                                    const SizedBox(width: 3),
                                    Text(
                                      'Edit Note',
                                      style: GoogleFonts.nunito(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: _lavender,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _lavLight.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _lavender.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          (customNote != null && customNote.isNotEmpty)
                              ? customNote
                              : 'No custom note provided for this update.',
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            color: (customNote != null && customNote.isNotEmpty)
                                ? _navy
                                : _navy.withValues(alpha: 0.4),
                            fontStyle:
                                (customNote != null && customNote.isNotEmpty)
                                    ? FontStyle.normal
                                    : FontStyle.italic,
                            fontWeight: FontWeight.w600,
                            height: 1.45,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (hasPhoto) ...[
                        Text(
                          'Proof Photo',
                          style: GoogleFonts.nunito(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _navy.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  _AllPhotosScreen(photoUrls: [proofPhotoUrl]),
                            ),
                          ),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: PawImage(
                                  url: proofPhotoUrl,
                                  width: double.infinity,
                                  height: 200,
                                  fit: BoxFit.cover,
                                  placeholder: const SizedBox(height: 200),
                                ),
                              ),
                              Positioned(
                                bottom: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.verified,
                                          size: 13, color: Color(0xFF7BBF5E)),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Tap to view full screen',
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
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      if (hasVideo) ...[
                        Text(
                          'Rescue Reel Clip 🎬',
                          style: GoogleFonts.nunito(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _navy.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ReelVideoPlayer(
                          videoUrl: proofVideoUrl,
                          maxHeight: 400,
                          autoPlay: true,
                          isLooping: true,
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (isOwn) ...[
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            icon:
                                const Icon(Icons.edit_note_rounded, size: 18),
                            label: const Text('Edit Custom Note'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _lavender,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              Navigator.pop(ctx);
                              _showEditCommentSheet(u, s.id);
                            },
                          ),
                        ),
                      ],
                      SizedBox(height: bottomInset > 0 ? bottomInset + 8 : 16),
                    ],
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

  void _showReportCommentDialog(Map<String, dynamic> c, Sighting s) {
    if (!DoubleTapGuard.allow('report_comment_${c['id'] ?? c['createdAt']}', thresholdMs: 800)) return;
    final sightingId = s.id;
    final isPostReporter = _isOwner(s);
    final isNormalComment = c['type'] == null || c['type'] == 'comment';
    final canBlock = isPostReporter && isNormalComment;

    final reasons = [
      'Inappropriate or offensive',
      'Spam or advertising',
      'Harassment or hate speech',
      'Misleading / false information',
      'Other',
    ];
    String? selected = reasons[0];
    final customController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(
              canBlock
                  ? 'Report & Block User'
                  : (isNormalComment
                      ? 'Report Comment'
                      : 'Report Community Update'),
              style: GoogleFonts.nunito(
                  fontWeight: FontWeight.w800, color: _navy)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!canBlock && !isNormalComment) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Our moderation team will review this community post update.',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        color: _navy.withValues(alpha: 0.6),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
                ...reasons.map((r) => RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(r,
                          style: GoogleFonts.nunito(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _navy)),
                      value: r,
                      groupValue: selected,
                      activeColor: _lavender,
                      onChanged: (v) => ss(() => selected = v),
                    )),
                const SizedBox(height: 10),
                Text(
                  'Additional explanation (optional):',
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _navy,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: customController,
                  maxLines: 2,
                  maxLength: 250,
                  style: GoogleFonts.nunito(fontSize: 12.5, color: _navy),
                  decoration: InputDecoration(
                    hintText: 'Explain why you are reporting this...',
                    hintStyle: GoogleFonts.nunito(
                      fontSize: 12,
                      color: _navy.withValues(alpha: 0.4),
                    ),
                    filled: true,
                    fillColor: Colors.grey.withValues(alpha: 0.06),
                    contentPadding: const EdgeInsets.all(10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _navy.withValues(alpha: 0.12)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _navy.withValues(alpha: 0.12)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _lavender, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.nunito(color: _navy))),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                final commentId = c['id']?.toString() ?? '';
                final authorUid = c['authorId']?.toString() ?? '';
                final authorName = c['authorName']?.toString() ?? 'User';

                final extra = customController.text.trim();
                final fullReason = extra.isNotEmpty
                    ? '${selected ?? ""}: $extra'
                    : (selected ?? '');

                await FirebaseService.instance.flagComment(
                  sightingId: sightingId,
                  commentId: commentId,
                  reason: fullReason,
                );

                if (!canBlock) {
                  if (mounted) {
                    _snack(isNormalComment
                        ? 'Comment reported to admin for review. Thank you!'
                        : 'Community update reported to admin for review. Thank you!');
                  }
                  return;
                }

                if (authorUid.isNotEmpty && authorUid != _uid) {
                  await FirebaseService.instance.blockUserFromSighting(
                    sightingId: sightingId,
                    blockedUid: authorUid,
                  );
                }

                if (!mounted) return;

                // Follow-up question: auto delete comments between reporter and blocked user
                final shouldDeleteComments = await showDialog<bool>(
                  context: context,
                  builder: (fCtx) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    title: Row(
                      children: [
                        const Icon(Icons.block, color: _urgent, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$authorName Blocked',
                            style: GoogleFonts.nunito(
                              fontWeight: FontWeight.w800,
                              color: _navy,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    content: Text(
                      'This user is now blocked and cannot view this sighting report anymore.\n\nDo you also want to automatically delete all comments from both you and this user on this report?',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        color: _navy.withValues(alpha: 0.75),
                        height: 1.4,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(fCtx, false),
                        child: Text('Keep Comments',
                            style: GoogleFonts.nunito(color: _navy, fontWeight: FontWeight.w600)),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _urgent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => Navigator.pop(fCtx, true),
                        child: Text('Delete Comments',
                            style: GoogleFonts.nunito(fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                );

                if (shouldDeleteComments == true && authorUid.isNotEmpty) {
                  await FirebaseService.instance.deleteCommentsBetweenUsers(
                    sightingId: sightingId,
                    userA: _uid ?? '',
                    userB: authorUid,
                  );
                  if (mounted) {
                    _snack('🚫 $authorName blocked and comments deleted.');
                  }
                } else {
                  if (mounted) {
                    _snack('🚫 $authorName blocked from this sighting report.');
                  }
                }
              },
              child: Text(canBlock ? 'Submit & Block' : 'Submit Report',
                  style: GoogleFonts.nunito(
                      color: _urgent, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  void _showPostVetFollowUpDialog(Sighting s) {
    final isFeralCat = s.isFeral;
    final rescuerName = s.lastVetRescuerName?.isNotEmpty == true
        ? s.lastVetRescuerName!
        : (s.pendingVetRescuerName?.isNotEmpty == true
            ? s.pendingVetRescuerName!
            : (s.careTakerName?.isNotEmpty == true
                ? s.careTakerName!
                : (s.rescueClaimedByName.isNotEmpty
                    ? s.rescueClaimedByName
                    : 'Rescuer')));
    final rescuerId = s.lastVetRescuerId ??
        s.pendingVetRescuerId ??
        s.careTakerId ??
        s.rescueClaimedBy;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomInset = MediaQuery.paddingOf(ctx).bottom;
        final maxH = MediaQuery.sizeOf(ctx).height * 0.85;

        return Container(
          constraints: BoxConstraints(maxHeight: maxH),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SafeArea(
            top: false,
            bottom: true,
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset > 0 ? bottomInset + 16 : 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
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
                          color: isFeralCat
                              ? const Color(0xFF00897B).withValues(alpha: 0.12)
                              : const Color(0xFF673AB7).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isFeralCat
                              ? Icons.nature_people_rounded
                              : Icons.medical_services_rounded,
                          color: isFeralCat
                              ? const Color(0xFF00897B)
                              : const Color(0xFF673AB7),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isFeralCat
                                  ? 'Feral Cat TNR Mandate'
                                  : 'Vet Visit Verified!',
                              style: GoogleFonts.nunito(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: _navy,
                              ),
                            ),
                            Text(
                              isFeralCat
                                  ? 'Mandatory post-clinic outcome for feral cats'
                                  : 'What is the next post-clinic step for this cat?',
                              style: GoogleFonts.nunito(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: _navy.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (isFeralCat) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00897B).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF00897B).withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              size: 18, color: Color(0xFF00897B)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'This cat is an unsocialized feral adult. Domestic foster and shelter adoptions are prohibited under humane TNR guidelines. The mandated path is safe Return to Colony / Spot (TNR).',
                              style: GoogleFonts.nunito(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF00695C),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (rescuerId.isNotEmpty && rescuerId != _uid) ...[
                      _buildPostVetOptionTile(
                        assetPath: 'assets/images/cattalking.png',
                        color: const Color(0xFF1E88E5),
                        title: 'Discuss Release Spot with $rescuerName',
                        subtitle:
                            'Coordinate via chat on where and when to safely release the healed feral cat.',
                        badgeText: 'Coordinate Chat',
                        badgeColor: const Color(0xFF1E88E5),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CoordinationChatScreen(
                                sighting: s,
                                otherUserId: rescuerId,
                                otherUserName: rescuerName,
                                otherUserRole: 'Vet Rescuer',
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_isVetRescuer(s))
                      _buildPostVetOptionTile(
                        assetPath: 'assets/images/location.png',
                        fallbackIcon: Icons.nature_people_rounded,
                        color: const Color(0xFF00897B),
                        title: 'Confirm Return to Colony / Spot',
                        subtitle:
                            'You have custody of this feral cat. Safely release the cat back to its territory.',
                        badgeText: 'Release Cat',
                        badgeColor: const Color(0xFF00897B),
                        onTap: () {
                          Navigator.pop(ctx);
                          _confirmReturnToSpot(s);
                        },
                      ),
                  ] else ...[
                    // 1. Rescuer in Charge (Delegate placement authority to Rescuer)
                    _buildPostVetOptionTile(
                      assetPath: 'assets/images/rescuerincharge.png',
                      color: const Color(0xFF1E88E5),
                      title: 'Delegate to $rescuerName',
                      subtitle:
                          'Grants custody authority to $rescuerName to decide and log next steps (foster, shelter, or adoption).',
                      badgeText: 'Rescuer in Charge',
                      badgeColor: const Color(0xFF1E88E5),
                      onTap: () async {
                        Navigator.pop(ctx);
                        try {
                          await FirebaseService.instance
                              .delegatePostVetCustodyToRescuer(s.id);
                          if (mounted) {
                            _snack(
                                'Custody delegated to $rescuerName! Rescuer now has access to log next placement steps. 🐾');
                          }
                        } catch (e) {
                          if (mounted) {
                            _snack('Failed to delegate custody: $e');
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 16),

                    // 2. Take In for Foster Care (Reporter Takes Cat)
                    _buildPostVetOptionTile(
                      assetPath: 'assets/images/needshome.png',
                      color: const Color(0xFF673AB7),
                      title: 'I Will Take In for Foster Care',
                      subtitle:
                          'Bring cat into your own care for quarantine & recovery. Sets up daily milestone journey.',
                      badgeText: '+150 XP',
                      badgeColor: const Color(0xFF673AB7),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showActionProofSheet('tookIn', s);
                      },
                    ),
                    const SizedBox(height: 16),

                    // 3. Transfer to Shelter
                    _buildPostVetOptionTile(
                      assetPath: 'assets/images/shelter.png',
                      color: const Color(0xFFE65100),
                      title: 'Transfer to Animal Shelter',
                      subtitle:
                          'Direct admission to a verified rescue center or shelter.',
                      badgeText: '+120 XP',
                      badgeColor: const Color(0xFFE65100),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showActionProofSheet('sheltered', s);
                      },
                    ),
                    if (rescuerId.isNotEmpty && rescuerId != _uid) ...[
                      const SizedBox(height: 16),
                      // 4. Discuss Next Steps with Rescuer (Coordinate before deciding)
                      _buildPostVetOptionTile(
                        assetPath: 'assets/images/cattalking.png',
                        color: const Color(0xFF1E88E5),
                        title: 'Discuss Next Steps with $rescuerName',
                        subtitle:
                            'Coordinate via chat before deciding between foster care, shelter, or rescuer custody.',
                        badgeText: 'Coordinate Chat',
                        badgeColor: const Color(0xFF1E88E5),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CoordinationChatScreen(
                                sighting: s,
                                otherUserId: rescuerId,
                                otherUserName: rescuerName,
                                otherUserRole: 'Vet Rescuer',
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmReturnToSpot(Sighting s) async {
    if (!s.canTnrReturn && !s.isFeral) {
      _snack(
          'Kittens and domestic fosters cannot be released to the street. Please choose Foster, Shelter, or Adoption.');
      return;
    }
    if (s.isVetVisitPending) {
      _snack(
          '⏳ Vet visit verification is pending. Actions are currently locked.');
      return;
    }
    if (s.isAwaitingPostVetDecision) {
      if (!_isVetRescuer(s)) {
        _snack(
            '⏳ Only ${s.lastVetRescuerName?.isNotEmpty == true ? s.lastVetRescuerName : "the rescuer"} who has custody can confirm return to spot.');
        return;
      }
    }

    double releaseLat = s.effectiveLatitude;
    double releaseLng = s.effectiveLongitude;
    String releaseAddress = s.effectiveLocationAddress;
    final addressCtrl = TextEditingController(text: releaseAddress);
    final noteCtrl = TextEditingController(
      text:
          'Cat received veterinary care and was safely returned to colony territory (TNR). 🌿',
    );
    bool isCustomLocationMarked = false;
    bool showLocationPicker = false;
    bool isLocating = false;
    File? proofFile;
    bool isSubmitting = false;
    bool isScanningProof = false;
    CatValidationResult? proofScanResult;
    bool hasAttemptedSubmit = false;
    String? formValidationError;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final canSubmit = proofFile != null &&
              proofScanResult?.isCat == true &&
              !isScanningProof &&
              !isSubmitting;
          final bottomPadding = MediaQuery.viewInsetsOf(context).bottom +
              MediaQuery.paddingOf(context).bottom +
              32;

          Future<void> pickProof(ImageSource src) async {
            try {
              final picker = ImagePicker();
              final picked = await picker.pickImage(
                source: src,
                maxWidth: 1200,
                maxHeight: 1200,
                imageQuality: 85,
              );
              if (picked == null) return;
              final file = File(picked.path);
              setSheetState(() {
                proofFile = file;
                isScanningProof = true;
                proofScanResult = null;
              });

              final result = await _aiService.validateCatImage(file);
              setSheetState(() {
                isScanningProof = false;
                proofScanResult = result;
              });
            } catch (e) {
              setSheetState(() => isScanningProof = false);
              _snack('Could not pick photo: $e');
            }
          }

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.90,
            ),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(
              20,
              14,
              20,
              bottomPadding,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Drag Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF00897B).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.nature_people_rounded,
                          color: Color(0xFF00897B),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Confirm TNR Colony Return 🌿',
                              style: GoogleFonts.nunito(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: _navy,
                              ),
                            ),
                            Text(
                              'Return unsocialized adult feral cat to colony territory.',
                              style: GoogleFonts.nunito(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: _navy.withValues(alpha: 0.65),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Feral Welfare Standard Notice
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00897B).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color:
                            const Color(0xFF00897B).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.verified_user_rounded,
                          size: 18,
                          color: Color(0xFF00897B),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'TNR Welfare Protocol: Feral cats thrive in their bonded outdoor colony. By default, release is set to the cat’s original territory coordinates.',
                            style: GoogleFonts.nunito(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF00695C),
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Location Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Release Location',
                        style: GoogleFonts.nunito(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: _navy,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isCustomLocationMarked
                              ? const Color(0xFF1E88E5)
                                  .withValues(alpha: 0.12)
                              : const Color(0xFF00897B)
                                  .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isCustomLocationMarked
                              ? '📍 Specific Pin Updated'
                              : '🌿 Original Colony (Default)',
                          style: GoogleFonts.nunito(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: isCustomLocationMarked
                                ? const Color(0xFF1976D2)
                                : const Color(0xFF00897B),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Location Display Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _lavLight,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _lavender.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isCustomLocationMarked
                                  ? Icons.location_on_rounded
                                  : Icons.nature_people_rounded,
                              size: 16,
                              color: isCustomLocationMarked
                                  ? const Color(0xFF1976D2)
                                  : const Color(0xFF00897B),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                addressCtrl.text.isNotEmpty
                                    ? addressCtrl.text
                                    : 'Colony Territory (${releaseLat.toStringAsFixed(4)}, ${releaseLng.toStringAsFixed(4)})',
                                style: GoogleFonts.nunito(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: _navy,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Coordinates: ${releaseLat.toStringAsFixed(5)}, ${releaseLng.toStringAsFixed(5)}',
                          style: GoogleFonts.nunito(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _navy.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () {
                            setSheetState(
                                () => showLocationPicker = !showLocationPicker);
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: _lavender.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  showLocationPicker
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.edit_location_alt_outlined,
                                  size: 15,
                                  color: const Color(0xFF00897B),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  showLocationPicker
                                      ? 'Hide Location Map'
                                      : 'Mark Specific Release Point (Optional)',
                                  style: GoogleFonts.nunito(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF00897B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Optional Location Map & GPS Picker
                  if (showLocationPicker) ...[
                    const SizedBox(height: 10),
                    Container(
                      height: 180,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: _navy.withValues(alpha: 0.15)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        children: [
                          FlutterMap(
                            options: MapOptions(
                              initialCenter:
                                  ll.LatLng(releaseLat, releaseLng),
                              initialZoom: 16.0,
                              onTap: (tapPos, point) async {
                                releaseLat = point.latitude;
                                releaseLng = point.longitude;
                                isCustomLocationMarked = true;
                                setSheetState(() => isLocating = true);
                                try {
                                  final addr = await LocationService()
                                      .getAddressFromCoordinates(
                                          point.latitude, point.longitude);
                                  releaseAddress = addr;
                                  addressCtrl.text = addr;
                                } catch (_) {}
                                setSheetState(() => isLocating = false);
                              },
                            ),
                            children: [
                              TileLayer(
                                urlTemplate:
                                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.pawwatch.app',
                              ),
                              MarkerLayer(
                                markers: [
                                  Marker(
                                    point:
                                        ll.LatLng(releaseLat, releaseLng),
                                    width: 38,
                                    height: 38,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF00897B),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white, width: 2),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.3),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                      child: const Center(
                                        child: Icon(
                                          Icons.nature_people_rounded,
                                          size: 18,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          if (isLocating)
                            Container(
                              color: Colors.black26,
                              child: const Center(
                                child: CircularProgressIndicator(
                                    color: Color(0xFF00897B)),
                              ),
                            ),
                          Positioned(
                            bottom: 6,
                            left: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Tap map to place release pin',
                                style: GoogleFonts.nunito(
                                  color: Colors.white,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            setSheetState(() => isLocating = true);
                            try {
                              final loc = await LocationService()
                                  .getCurrentUserLocation();
                              releaseLat = loc.latitude;
                              releaseLng = loc.longitude;
                              releaseAddress = loc.formattedAddress;
                              addressCtrl.text = loc.formattedAddress;
                              isCustomLocationMarked = true;
                            } catch (e) {
                              _snack('Could not get GPS: $e');
                            }
                            setSheetState(() => isLocating = false);
                          },
                          icon: const Icon(Icons.my_location_rounded,
                              size: 14, color: Color(0xFF00897B)),
                          label: Text(
                            'Use Current GPS',
                            style: GoogleFonts.nunito(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF00897B),
                            ),
                          ),
                        ),
                        if (isCustomLocationMarked) ...[
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: () {
                              setSheetState(() {
                                releaseLat = s.effectiveLatitude;
                                releaseLng = s.effectiveLongitude;
                                releaseAddress = s.effectiveLocationAddress;
                                addressCtrl.text = releaseAddress;
                                isCustomLocationMarked = false;
                              });
                            },
                            icon: const Icon(Icons.restore_rounded,
                                size: 14, color: Colors.grey),
                            label: Text(
                              'Reset to Default',
                              style: GoogleFonts.nunito(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Photo Proof (Mandatory)
                  Row(
                    children: [
                      Text(
                        'Release Photo Proof',
                        style: GoogleFonts.nunito(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: _navy,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Text(
                          'Required *',
                          style: GoogleFonts.nunito(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Community members want verified photo updates of the cat safely released back to colony territory.',
                    style: GoogleFonts.nunito(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: _navy.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (proofFile != null) ...[
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            proofFile!,
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => setSheetState(() {
                              proofFile = null;
                              proofScanResult = null;
                            }),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.black87,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close_rounded,
                                  size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (isScanningProof)
                      Row(
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF00897B),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'AI verifying cat photo...',
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF00897B),
                            ),
                          ),
                        ],
                      )
                    else if (proofScanResult != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: proofScanResult!.isCat
                              ? const Color(0xFF00897B).withValues(alpha: 0.1)
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: proofScanResult!.isCat
                                ? const Color(0xFF00897B).withValues(alpha: 0.3)
                                : Colors.red.shade300,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              proofScanResult!.isCat
                                  ? Icons.verified_rounded
                                  : Icons.error_outline_rounded,
                              size: 14,
                              color: proofScanResult!.isCat
                                  ? const Color(0xFF00897B)
                                  : Colors.red.shade700,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                proofScanResult!.isCat
                                    ? 'Cat Verified (${(proofScanResult!.confidence * 100).toStringAsFixed(0)}%) 🐾'
                                    : proofScanResult!.message,
                                style: GoogleFonts.nunito(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: proofScanResult!.isCat
                                      ? const Color(0xFF00695C)
                                      : Colors.red.shade800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ]
                  else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => pickProof(ImageSource.camera),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: (hasAttemptedSubmit && (proofFile == null || proofScanResult?.isCat == false))
                                    ? const Color(0xFFE53935)
                                    : const Color(0xFF00897B),
                                width: (hasAttemptedSubmit && (proofFile == null || proofScanResult?.isCat == false)) ? 1.5 : 1,
                              ),
                            ),
                            icon: const Icon(Icons.camera_alt_rounded,
                                size: 16, color: Color(0xFF00897B)),
                            label: Text(
                              'Camera',
                              style: GoogleFonts.nunito(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: _navy,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => pickProof(ImageSource.gallery),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(
                                color: (hasAttemptedSubmit && (proofFile == null || proofScanResult?.isCat == false))
                                    ? const Color(0xFFE53935)
                                    : const Color(0xFF1E88E5),
                                width: (hasAttemptedSubmit && (proofFile == null || proofScanResult?.isCat == false)) ? 1.5 : 1,
                              ),
                            ),
                            icon: const Icon(Icons.photo_library_rounded,
                                size: 16, color: Color(0xFF1E88E5)),
                            label: Text(
                              'Gallery',
                              style: GoogleFonts.nunito(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: _navy,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (hasAttemptedSubmit && proofFile == null) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFEF5350)),
                      ),
                      child: Text(
                        '⚠️ Cat photo proof is required to confirm release back to colony.',
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFD32F2F),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),

                  // Release Notes
                  Text(
                    'Release Notes',
                    style: GoogleFonts.nunito(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: noteCtrl,
                    onChanged: (_) => setSheetState(() {}),
                    maxLines: 2,
                    style: GoogleFonts.nunito(fontSize: 13, color: _navy),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: _lavLight,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: (hasAttemptedSubmit && TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Release note') != null)
                              ? const Color(0xFFE53935)
                              : BorderSide.none.color,
                          width: (hasAttemptedSubmit && TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Release note') != null) ? 1.5 : 0,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: (hasAttemptedSubmit && TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Release note') != null)
                              ? const Color(0xFFE53935)
                              : Colors.transparent,
                          width: (hasAttemptedSubmit && TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Release note') != null) ? 1.5 : 0,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: (hasAttemptedSubmit && TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Release note') != null)
                              ? const Color(0xFFE53935)
                              : const Color(0xFF00897B),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  if (hasAttemptedSubmit && TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Release note') != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '⚠️ ${TextModerationService.validateDescription(noteCtrl.text, fieldName: "Release note")!}',
                      style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFE53935),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Warning Banner
                  if (formValidationError != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFEF5350)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              size: 18, color: Color(0xFFD32F2F)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              formValidationError!,
                              style: GoogleFonts.nunito(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFB71C1C),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Submit Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canSubmit
                            ? const Color(0xFF00897B)
                            : const Color(0xFF00897B).withValues(alpha: 0.7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: canSubmit ? 2 : 0,
                      ),
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              if (isSubmitting || !DoubleTapGuard.allow('action_proof_${s.id}')) return;
                              if (proofFile == null) {
                                setSheetState(() {
                                  hasAttemptedSubmit = true;
                                  isSubmitting = false;
                                  formValidationError =
                                      '⚠️ Cat photo proof is required to confirm release back to colony.';
                                });
                                DoubleTapGuard.reset('action_proof_${s.id}');
                                return;
                              }
                              if (isScanningProof) {
                                setSheetState(() {
                                  isSubmitting = false;
                                  formValidationError =
                                      '⏳ AI is verifying the photo, please wait a moment...';
                                });
                                DoubleTapGuard.reset('action_proof_${s.id}');
                                return;
                              }
                              if (proofScanResult?.isCat != true) {
                                setSheetState(() {
                                  hasAttemptedSubmit = true;
                                  isSubmitting = false;
                                  formValidationError =
                                      '⚠️ Photo verification failed: ${proofScanResult?.message ?? "Please upload a clear photo of the cat."}';
                                });
                                DoubleTapGuard.reset('action_proof_${s.id}');
                                return;
                              }
                              if (isCustomLocationMarked) {
                                final addrErr =
                                    TextModerationService.validateAddress(
                                        addressCtrl.text,
                                        label: 'Release address');
                                if (addrErr != null) {
                                  setSheetState(() {
                                    hasAttemptedSubmit = true;
                                    isSubmitting = false;
                                    formValidationError = '⚠️ $addrErr';
                                  });
                                  DoubleTapGuard.reset('action_proof_${s.id}');
                                  return;
                                }
                              }
                              final noteErr =
                                  TextModerationService.validateDescription(
                                      noteCtrl.text,
                                      fieldName: 'Release note');
                              if (noteErr != null) {
                                setSheetState(() {
                                  hasAttemptedSubmit = true;
                                  isSubmitting = false;
                                  formValidationError = '⚠️ $noteErr';
                                });
                                DoubleTapGuard.reset('action_proof_${s.id}');
                                return;
                              }
                              setSheetState(() {
                                isSubmitting = true;
                                formValidationError = null;
                              });
                              try {
                                await FirebaseService.instance.logRescueAction(
                                  sightingId: s.id,
                                  action: 'returnedToSpot',
                                  customNote: noteCtrl.text.trim(),
                                  proofPhotoFile: proofFile,
                                  updatedLatitude: isCustomLocationMarked
                                      ? releaseLat
                                      : null,
                                  updatedLongitude: isCustomLocationMarked
                                      ? releaseLng
                                      : null,
                                  updatedLocationAddress: isCustomLocationMarked
                                      ? addressCtrl.text.trim()
                                      : null,
                                  markResolved: true,
                                );
                                if (bCtx.mounted) {
                                  Navigator.pop(bCtx);
                                }
                                if (mounted) {
                                  _snack(
                                      '🌿 Feral cat safely returned to colony territory! (+100 XP)');
                                }
                              } catch (e) {
                                if (mounted) {
                                  _snack('Failed to complete return: $e');
                                }
                              } finally {
                                if (mounted) {
                                  setSheetState(() => isSubmitting = false);
                                }
                              }
                            },
                      icon: isSubmitting
                          ? const SizedBox.shrink()
                          : Icon(
                              proofFile != null
                                  ? Icons.nature_people_rounded
                                  : Icons.lock_outline_rounded,
                              size: 18,
                            ),
                      label: isSubmitting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              proofFile != null
                                  ? 'Confirm Release to Colony (+100 XP)'
                                  : 'Attach Photo Proof to Confirm',
                              style: GoogleFonts.nunito(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                  SizedBox(
                    height: MediaQuery.paddingOf(context).bottom > 0
                        ? MediaQuery.paddingOf(context).bottom + 20
                        : 24,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showUpdateCatTemperamentDialog(Sighting s) async {
    if (s.isVetVisitVerified) {
      _snack('Vet visit has already been verified. Diagnosis cannot be modified.');
      return;
    }
    final isNeedsRehomed = s.category == 'Needs Foster' ||
        s.category == 'Needs Home' ||
        s.isNeedsHome ||
        s.isOpenForAdoption;
    String selectedTemp = s.temperament ?? (isNeedsRehomed ? 'friendly' : 'feral');
    if (isNeedsRehomed && selectedTemp == 'feral') {
      selectedTemp = 'friendly';
    }
    final noteCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              const Icon(Icons.psychology_alt_rounded,
                  color: Color(0xFF673AB7)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Update Cat Temperament',
                  style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w900,
                    fontSize: 16.5,
                    color: _navy,
                  ),
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
                  'Did the clinic veterinarian determine that this cat is feral, timid, or friendly during the exam or procedure?',
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _navy.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 12),
                ...[
                  if (!isNeedsRehomed)
                    {
                      'key': 'feral',
                      'title': 'Feral / Colony Adult (Mandatory TNR)',
                      'asset': 'assets/images/feral.png',
                      'desc':
                          'Unsocialized to humans. Cannot be adopted indoors; must be safely returned to colony.',
                      'color': const Color(0xFF00897B),
                    },
                  {
                    'key': 'shy',
                    'title': 'Shy / Timid Stray',
                    'asset': 'assets/images/shycat.png',
                    'desc':
                        'Cautious but socializable indoors through quiet foster care.',
                    'color': const Color(0xFF1E88E5),
                  },
                  {
                    'key': 'friendly',
                    'title': 'Friendly Pet (Adoptable)',
                    'asset': 'assets/images/friendly.png',
                    'desc':
                        'Approachable and gentle. Suitable for indoor home adoption.',
                    'color': const Color(0xFF9C27B0),
                  },
                  {
                    'key': 'kitten',
                    'title': 'Kitten (Under 4 Months)',
                    'asset': 'assets/images/kittenwhisperer.png',
                    'desc':
                        'Young kitten. Highly socializable indoors, requires specialized foster care, nursing, or adoption.',
                    'color': const Color(0xFFE91E63),
                  },
                ].map((opt) {
                  final key = opt['key'] as String;
                  final title = opt['title'] as String;
                  final asset = opt['asset'] as String;
                  final desc = opt['desc'] as String;
                  final color = opt['color'] as Color;
                  final isSelected = selectedTemp == key;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      onTap: () => setDlgState(() => selectedTemp = key),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 12),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color.withValues(alpha: 0.08)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSelected
                                ? color
                                : _navy.withValues(alpha: 0.14),
                            width: isSelected ? 2 : 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (isSelected ? color : _navy)
                                  .withValues(alpha: 0.06),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              title,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.nunito(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: isSelected ? color : _navy,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Image.asset(
                              asset,
                              width: 46,
                              height: 46,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              desc,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.nunito(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _navy.withValues(alpha: 0.65),
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),
                TextField(
                  controller: noteCtrl,
                  maxLines: 2,
                  style: GoogleFonts.nunito(fontSize: 12, color: _navy),
                  decoration: InputDecoration(
                    labelText: 'Clinic / Vet Notes (Optional)',
                    labelStyle: GoogleFonts.nunito(fontSize: 12),
                    hintText:
                        'e.g. Dr. Jane at City Vet verified unsocialized feral; ear-tipped',
                    hintStyle:
                        GoogleFonts.nunito(fontSize: 11, color: Colors.grey),
                    filled: true,
                    fillColor: _lavLight,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: Text('Cancel',
                  style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w700, color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF673AB7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                Navigator.pop(dCtx);
                try {
                  await FirebaseService.instance.updateCatTemperament(
                    sightingId: s.id,
                    temperament: selectedTemp,
                    reason: noteCtrl.text.trim(),
                  );
                  if (mounted) {
                    final label = selectedTemp == 'feral'
                        ? 'Feral / Colony Adult'
                        : (selectedTemp == 'friendly'
                            ? 'Friendly Pet'
                            : (selectedTemp == 'kitten'
                                ? 'Kitten'
                                : 'Shy Stray'));
                    _snack(
                        'Cat temperament updated to $label!${selectedTemp == "feral" ? " Mandatory TNR protocol active." : ""}');
                  }
                } catch (e) {
                  if (mounted) _snack('Failed to update temperament: $e');
                }
              },
              child: Text('Save Diagnosis',
                  style: GoogleFonts.nunito(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRequestCommunityFosterDialog(Sighting s) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.group_rounded, color: Color(0xFF1E88E5)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Request Community Foster?',
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w900, fontSize: 16, color: _navy),
              ),
            ),
          ],
        ),
        content: Text(
          'Since you cannot foster, this cat will be highlighted to nearby foster volunteers on the map and home feed.',
          style: GoogleFonts.nunito(
              fontSize: 13, color: _navy.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text('Cancel',
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w700, color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E88E5),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text('Request Foster',
                style: GoogleFonts.nunito(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await FirebaseService.instance
            .requestCommunityFoster(sightingId: s.id);
        if (mounted) {
          _snack(
              'Marked as looking for foster! Nearby foster volunteers are notified. 🏡🐾');
        }
      } catch (e) {
        if (mounted) _snack('Failed to update: $e');
      }
    }
  }

  Widget _buildPostVetOptionTile({
    String? assetPath,
    IconData? fallbackIcon,
    required Color color,
    required String title,
    required String subtitle,
    String? badgeText,
    Color? badgeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        if (!DoubleTapGuard.allow('post_vet_opt_$title', thresholdMs: 800)) return;
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: color.withValues(alpha: 0.25),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. Action Name (Title on top)
            Text(
              title,
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _navy,
              ),
            ),
            const SizedBox(height: 12),

            // 2. Custom icon in the middle
            Center(
              child: assetPath != null
                  ? Image.asset(
                      assetPath,
                      width: 68,
                      height: 68,
                      fit: BoxFit.contain,
                    )
                  : Icon(
                      fallbackIcon ?? Icons.pets,
                      size: 46,
                      color: color,
                    ),
            ),
            const SizedBox(height: 12),

            // 3. Short desc at bottom
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: _navy.withValues(alpha: 0.65),
                height: 1.3,
              ),
            ),
            if (badgeText != null && badgeText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: (badgeColor ?? color).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  badgeText,
                  style: GoogleFonts.nunito(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: badgeColor ?? color,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showMedicalTriageGuidanceDialog(Sighting s, String intendedAction) {
    final actionName = intendedAction == 'tookIn' ? 'Foster Care' : 'Shelter';
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.medical_services_rounded,
                color: Color(0xFF673AB7)),
            const SizedBox(width: 8),
            Text('Vet Visit First Required',
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w900, color: _navy, fontSize: 16)),
          ],
        ),
        content: Text(
          'For ${s.category} situations, a vet checkup must be logged first before $actionName. Please take the cat to a clinic and log a Vet Visit with proof.',
          style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _navy.withValues(alpha: 0.75)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: Text('Cancel',
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w700, color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF673AB7),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              Navigator.pop(dCtx);
              _showActionProofSheet('vet', s);
            },
            child: Text('Log Vet Visit',
                style: GoogleFonts.nunito(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  Future<bool> _ensureNoConflictingRescueTrip(Sighting targetSighting) async {
    if (_uid == null) return true;
    final activeTrip = await FirebaseService.instance.getActiveRescueTrip(_uid!);
    if (activeTrip != null && activeTrip.id != targetSighting.id) {
      if (!mounted) return false;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE65100).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.directions_run_rounded,
                    color: Color(0xFFE65100), size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Active Rescue in Progress',
                  style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: _navy,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You are currently on your way to another rescue mission (${activeTrip.title.isNotEmpty ? activeTrip.title : "Active Rescue"} • ${activeTrip.locationAddress}).',
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'To maintain community reliability and prioritize the cat in transit, you cannot claim or log actions on other cats until you complete or cancel your active trip.',
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  color: _navy.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Close', style: GoogleFonts.nunito(color: _navy)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE65100),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SightingDetailScreen(sighting: activeTrip),
                  ),
                );
              },
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: Text(
                'Go to Active Rescue',
                style: GoogleFonts.nunito(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
      return false;
    }
    return true;
  }

  Future<bool> _ensureNoConflictingVetCare(Sighting targetSighting) async {
    if (_uid == null) return true;
    final activeVetCare =
        await FirebaseService.instance.getActiveVetCareSighting(_uid!);
    if (activeVetCare != null && activeVetCare.id != targetSighting.id) {
      if (!mounted) return false;
      final isDecidingNextStep = activeVetCare.isAwaitingPostVetDecision;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF673AB7).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.local_hospital_rounded,
                    color: Color(0xFF673AB7), size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isDecidingNextStep
                      ? 'Decide Next Step Required'
                      : 'Vet Care Pending Verification',
                  style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: _navy,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isDecidingNextStep
                    ? 'You currently have physical custody of ${activeVetCare.title.isNotEmpty ? activeVetCare.title : "this cat"} after vet care.'
                    : 'You submitted vet clinic proof for ${activeVetCare.title.isNotEmpty ? activeVetCare.title : "this cat"} and are waiting for reporter verification.',
                style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isDecidingNextStep
                    ? 'You must decide the next step (foster care, shelter transfer, or safe release) for this cat before you can claim or log actions on other cats.'
                    : 'Please wait for the reporter to verify your vet visit before taking on or logging actions on another cat.',
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  color: _navy.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Dismiss', style: GoogleFonts.nunito(color: _navy)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF673AB7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        SightingDetailScreen(sighting: activeVetCare),
                  ),
                );
              },
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: Text(
                isDecidingNextStep ? 'Decide Next Step 🐾' : 'View Vet Care Cat',
                style: GoogleFonts.nunito(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _showActionProofSheet(String action, Sighting s) async {
    if (_isActionSheetOpen) return;
    _isActionSheetOpen = true;
    try {
      if (!await _ensureNoConflictingRescueTrip(s)) return;
      if (!await _ensureNoConflictingVetCare(s)) return;
      if (s.isVetVisitPending) {
        _snack(
            '⏳ A vet visit report has been submitted by ${s.pendingVetRescuerName?.isNotEmpty == true ? s.pendingVetRescuerName : "a rescuer"}. Actions are locked pending verification.');
        return;
      }
    if (s.isAwaitingPostVetDecision) {
      if (!_isVetRescuer(s) && !_isOwner(s) && !s.isRescuerCustodyDelegated) {
        _snack(
            '⏳ ${s.lastVetRescuerName?.isNotEmpty == true ? s.lastVetRescuerName : "The rescuer"} currently has custody of this cat after vet care. Please coordinate via chat.');
        return;
      }
    }
    if (s.isFeral &&
        (action == 'tookIn' || action == 'holding' || action == 'sheltered')) {
      _snack(
          '🌿 This is an unsocialized feral cat. Foster and shelter adoptions are not suitable for feral cats. Mandatory TNR Return to Colony is the only permitted outcome.');
      return;
    }
    if ((action == 'tookIn' || action == 'holding') &&
        s.isFosterDeclinedFor(_uid)) {
      _snack(
          'Your foster custody request for this cat was previously declined by the reporter.');
      return;
    }
    final col = _aColor(action);
    final actionLabel = _aLabels[action] ?? action;
    final xp = _aXp[action] ?? 10;
    File? proofFile;
    RescueActionValidationResult? scanResult;
    bool isScanning = false;
    bool isSubmitting = false;
    final isShelteredAction = action == 'sheltered';
    final isTookInAction = action == 'tookIn' || action == 'holding';
    final isOwner = _isOwner(s);
    bool hasAttemptedSubmit = false;
    String? formValidationError;
    String? selectedDiagnosedTemperament = s.temperament;
    int planDurationDays = 7;
    String selectedCareGoal = '🍼 Kitten Care & Weaning';
    final customGoalCtrl = TextEditingController();
    bool isCustomGoal = false;
    final day1Ctrl =
        TextEditingController(text: 'Intake, Quarantine & Safe Settle');
    final finalOutcomeCtrl =
        TextEditingController(text: 'Final Target Outcome & Review');
    final Map<int, TextEditingController> intermediateDayCtrls = {};

    TextEditingController getDayCtrl(int day, int totalDays) {
      if (day == 1) return day1Ctrl;
      if (day == totalDays) return finalOutcomeCtrl;
      return intermediateDayCtrls.putIfAbsent(
          day, () => TextEditingController(text: ''));
    }
    double shelterLat = s.effectiveLatitude;
    double shelterLng = s.effectiveLongitude;
    final shelterNameCtrl = TextEditingController();
    final shelterAddressCtrl = TextEditingController(text: isShelteredAction ? s.effectiveLocationAddress : '');
    bool isOnRegisterNewTab = false;
    final noteCtrl = TextEditingController();

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> pickPhoto(ImageSource source) async {
            try {
              final picked = await _picker.pickImage(
                source: source,
                maxWidth: 1200,
                maxHeight: 1200,
                imageQuality: 85,
              );
              if (picked == null) return;
              final file = File(picked.path);

              setSheetState(() {
                proofFile = file;
                isScanning = true;
                scanResult = null;
              });

              final result =
                  await _aiService.validateRescueActionProof(file, action);

              setSheetState(() {
                isScanning = false;
                scanResult = result;
              });
            } catch (e) {
              setSheetState(() {
                isScanning = false;
              });
              _snack('Error picking photo: $e');
            }
          }

          bool areAllMilestonesFilled = true;
          String? firstMilestoneError;
          if (isTookInAction) {
            for (int d = 1; d <= planDurationDays; d++) {
              final text = getDayCtrl(d, planDurationDays).text.trim();
              if (text.isEmpty) {
                areAllMilestonesFilled = false;
                firstMilestoneError ??= 'Day $d theme is required.';
                break;
              }
              final err = TextModerationService.validateTitle(text,
                  label: 'Day $d theme', minLength: 4);
              if (err != null) {
                areAllMilestonesFilled = false;
                firstMilestoneError ??= err;
                break;
              }
            }
          }

          final String? customGoalError = isCustomGoal
              ? TextModerationService.validateTitle(customGoalCtrl.text,
                  label: 'Custom goal', minLength: 4)
              : null;
          final bool isCustomGoalValid =
              !isCustomGoal || customGoalError == null;

          final isNoteMandatory = action == 'vet' ||
              isShelteredAction ||
              isTookInAction ||
              action == 'stillHere';
          final String? noteError = isNoteMandatory
              ? TextModerationService.validateDescription(noteCtrl.text,
                  fieldName: isTookInAction
                      ? 'Foster care note'
                      : (isShelteredAction
                          ? 'Shelter transfer note'
                          : (action == 'vet'
                              ? 'Veterinary note'
                              : 'Details note')))
              : null;
          final bool isNoteValid = !isNoteMandatory || noteError == null;

          final String? shelterNameError = isShelteredAction
              ? TextModerationService.validateFacilityName(shelterNameCtrl.text,
                  label: 'Shelter name')
              : null;
          final bool isShelterNameValid =
              !isShelteredAction || shelterNameError == null;

          final String? shelterAddressError = isShelteredAction
              ? TextModerationService.validateAddress(shelterAddressCtrl.text,
                  label: 'Shelter address')
              : null;
          final bool isShelterAddressValid =
              !isShelteredAction || shelterAddressError == null;

          final canSubmit = proofFile != null &&
              scanResult != null &&
              scanResult!.isValid &&
              !isScanning &&
              !isSubmitting &&
              isNoteValid &&
              isShelterNameValid &&
              isShelterAddressValid &&
              (!isTookInAction ||
                  (isCustomGoalValid && areAllMilestonesFilled));

          final bottomPadding = MediaQuery.paddingOf(ctx).bottom;
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, bottomPadding > 0 ? bottomPadding + 20 : 28),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: _navy.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: col.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(_aIcon(action), color: col, size: 22),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isTookInAction
                                    ? (isOwner
                                        ? 'Foster at My Place (Care Plan)'
                                        : 'Request Foster Custody')
                                    : 'Log Rescue: $actionLabel',
                                style: GoogleFonts.nunito(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: _navy,
                                ),
                              ),
                              Text(
                                isShelteredAction
                                    ? 'Marks report as Resolved • Safe in Shelter (+120 XP)'
                                    : (isTookInAction
                                        ? (isOwner
                                            ? 'Set up Care Plan & daily milestones (+150 XP)'
                                            : 'Requires reporter confirmation for animal welfare (+150 XP)')
                                        : '+$xp XP reward upon verification'),
                                style: GoogleFonts.nunito(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: col,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (isTookInAction) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF673AB7).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: const Color(0xFF673AB7).withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            Icon(isOwner ? Icons.volunteer_activism_rounded : Icons.handshake_outlined,
                                color: const Color(0xFF673AB7), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                isOwner
                                    ? 'Foster Custody: Set up your Custom Care Plan and daily milestones for taking this cat into foster care at your place.'
                                    : 'Foster Handshake: Taking this cat into foster care will send your Custom Care Plan and Trust Card to the reporter for approval.',
                                style: GoogleFonts.nunito(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF673AB7),
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Care Plan Target Goal',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          '🍼 Kitten Care & Weaning',
                          '🩺 Medical & Recovery',
                          '✨ Temporary Quarantine',
                          '✏️ Custom Goal',
                        ].map((g) {
                          final isSelected = isCustomGoal
                              ? (g == '✏️ Custom Goal')
                              : (selectedCareGoal == g);
                          return ChoiceChip(
                            label: Text(
                              g,
                              style: GoogleFonts.nunito(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: isSelected ? Colors.white : _navy,
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: const Color(0xFF673AB7),
                            backgroundColor: _lavLight,
                            onSelected: (val) {
                              setSheetState(() {
                                if (g == '✏️ Custom Goal') {
                                  isCustomGoal = true;
                                } else {
                                  isCustomGoal = false;
                                  selectedCareGoal = g;
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      if (isCustomGoal) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: customGoalCtrl,
                          onChanged: (_) => setSheetState(() {}),
                          style: GoogleFonts.nunito(
                              fontSize: 13,
                              color: _navy,
                              fontWeight: FontWeight.w600),
                          decoration: InputDecoration(
                            hintText:
                                'Enter custom goal (e.g. Skin treatment & wound recovery)',
                            hintStyle: GoogleFonts.nunito(
                                fontSize: 12,
                                color: _navy.withValues(alpha: 0.4)),
                            errorText: isCustomGoal &&
                                    customGoalCtrl.text.trim().isNotEmpty
                                ? customGoalError
                                : null,
                            errorMaxLines: 2,
                            filled: true,
                            fillColor: _lavLight,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Text(
                        'Care Plan Duration (Min 3 Days)',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [3, 5, 7, 14].map((d) {
                          final isSelected = planDurationDays == d;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () =>
                                  setSheetState(() => planDurationDays = d),
                              child: Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFF673AB7)
                                      : _lavLight,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Center(
                                  child: Text(
                                    '$d Days',
                                    style: GoogleFonts.nunito(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: isSelected ? Colors.white : _navy,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF673AB7).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_month_rounded,
                                size: 16, color: Color(0xFF673AB7)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '📅 Everyday Updates: Mandatory photo & condition check-in every day (Day 1 ➔ Day $planDurationDays)',
                                style: GoogleFonts.nunito(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF673AB7),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Customize Daily Milestone Themes (Day 1 to $planDurationDays)',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...List.generate(planDurationDays, (i) {
                        final dayNum = i + 1;
                        final ctrl = getDayCtrl(dayNum, planDurationDays);
                        final isFirst = dayNum == 1;
                        final isLast = dayNum == planDurationDays;
                        final dayText = ctrl.text.trim();
                        final dayErr = dayText.isNotEmpty
                            ? TextModerationService.validateTitle(dayText,
                                label: 'Day $dayNum theme', minLength: 4)
                            : null;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: TextField(
                            controller: ctrl,
                            onChanged: (_) => setSheetState(() {}),
                            style: GoogleFonts.nunito(
                                fontSize: 12.5, color: _navy),
                            decoration: InputDecoration(
                              prefixIcon: Icon(
                                isFirst
                                    ? Icons.looks_one_rounded
                                    : (isLast
                                        ? Icons.verified_rounded
                                        : Icons.circle_outlined),
                                size: 18,
                                color: const Color(0xFF673AB7),
                              ),
                              labelText: isFirst
                                  ? 'Day 1: Intake & Quarantine *'
                                  : (isLast
                                      ? 'Day $dayNum: Final Target Outcome *'
                                      : 'Day $dayNum Theme *'),
                              hintText: isFirst
                                  ? 'Intake, Quarantine & Safe Settle'
                                  : (isLast
                                      ? 'Final Target Outcome & Review'
                                      : 'e.g. Vet check, Meds, Appetite & Diet, Socialization...'),
                              hintStyle: GoogleFonts.nunito(
                                  fontSize: 11,
                                  color: _navy.withValues(alpha: 0.35)),
                              labelStyle: GoogleFonts.nunito(
                                  fontSize: 11,
                                  color: _navy.withValues(alpha: 0.6)),
                              errorText: dayErr,
                              errorMaxLines: 2,
                              filled: true,
                              fillColor: _lavLight,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: BorderSide.none),
                            ),
                          ),
                        );
                      }),
                    ],
                    const SizedBox(height: 16),
                    Builder(builder: (_) {
                      String proofTitle;
                      String proofSubtitle;
                      if (isTookInAction) {
                        proofTitle =
                            'Photo of Cat in Carrier / Foster Setup (Required)';
                        proofSubtitle =
                            'Take a clear photo of the cat inside your carrier, crate, or safe foster room to confirm custody.';
                      } else if (action == 'fed') {
                        proofTitle =
                            'Photo of Cat Eating / Food Bowl (Required)';
                        proofSubtitle =
                            'Take a clear photo showing the cat with the food provided.';
                      } else if (action == 'vet') {
                        proofTitle =
                            'Photo of Cat at Vet Clinic (Required)';
                        proofSubtitle =
                            'Take a photo at the veterinary clinic showing the cat or exam room.';
                      } else if (isShelteredAction) {
                        proofTitle =
                            'Photo of Shelter Facility / Kennel (Required)';
                        proofSubtitle =
                            'Take a photo of the cat safely admitted inside the shelter.';
                      } else if (action == 'rehomed') {
                        proofTitle =
                            'Photo of Cat with Adopter / New Home (Required)';
                        proofSubtitle =
                            'Take a photo of the cat settled into its permanent loving home.';
                      } else {
                        proofTitle = 'Photo Proof of Cat (Required)';
                        proofSubtitle =
                            'Take a clear photo confirming the cat at the spot.';
                      }

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            proofTitle,
                            style: GoogleFonts.nunito(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _navy,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            proofSubtitle,
                            style: GoogleFonts.nunito(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: _navy.withValues(alpha: 0.6),
                              height: 1.3,
                            ),
                          ),
                        ],
                      );
                    }),
                    const SizedBox(height: 8),
                    if (proofFile == null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                side: BorderSide(
                                    color: (hasAttemptedSubmit && proofFile == null)
                                        ? const Color(0xFFE53935)
                                        : _navy.withValues(alpha: 0.2),
                                    width: (hasAttemptedSubmit && proofFile == null) ? 1.6 : 1.0),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => pickPhoto(ImageSource.camera),
                              icon: Icon(Icons.camera_alt, color: col, size: 18),
                              label: Text('Take Camera Photo',
                                  style: GoogleFonts.nunito(
                                      fontWeight: FontWeight.w800,
                                      color: _navy,
                                      fontSize: 12)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                side: BorderSide(
                                    color: (hasAttemptedSubmit && proofFile == null)
                                        ? const Color(0xFFE53935)
                                        : _navy.withValues(alpha: 0.2),
                                    width: (hasAttemptedSubmit && proofFile == null) ? 1.6 : 1.0),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => pickPhoto(ImageSource.gallery),
                              icon: Icon(Icons.photo_library,
                                  color: _lavender, size: 18),
                              label: Text('Pick Gallery',
                                  style: GoogleFonts.nunito(
                                      fontWeight: FontWeight.w800,
                                      color: _navy,
                                      fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                      if (hasAttemptedSubmit && proofFile == null) ...[
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded, size: 14, color: Colors.red.shade700),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  isShelteredAction
                                      ? '⚠️ Cat photo proof inside the shelter is required to proceed.'
                                      : (action == 'vet'
                                          ? '⚠️ Photo proof of the cat at the vet clinic is required to proceed.'
                                          : (isTookInAction
                                              ? '⚠️ Photo proof of the cat in your foster setup is required to proceed.'
                                              : (action == 'fed'
                                                  ? '⚠️ Photo proof of the cat eating or with food is required.'
                                                  : '⚠️ Cat photo proof is required to proceed.'))),
                                  style: GoogleFonts.nunito(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.red.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ] else ...[
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.file(
                              proofFile!,
                              width: double.infinity,
                              height: 150,
                              fit: BoxFit.cover,
                            ),
                          ),
                          if (isScanning)
                            Positioned.fill(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                            color: Colors.white, strokeWidth: 2.5),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'AI Validating Cat Proof...',
                                        style: GoogleFonts.nunito(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () => setSheetState(() {
                                proofFile = null;
                                scanResult = null;
                              }),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close,
                                    color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (scanResult != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: scanResult!.isValid
                              ? const Color(0xFF43A047).withValues(alpha: 0.1)
                              : _urgent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: scanResult!.isValid
                                ? const Color(0xFF43A047).withValues(alpha: 0.3)
                                : _urgent.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              scanResult!.isValid
                                  ? Icons.check_circle_rounded
                                  : Icons.error_outline_rounded,
                              color: scanResult!.isValid
                                  ? const Color(0xFF43A047)
                                  : _urgent,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                scanResult!.message,
                                style: GoogleFonts.nunito(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: scanResult!.isValid
                                      ? const Color(0xFF2E7D32)
                                      : _urgent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    if (isShelteredAction) ...[
                      ShelterPickerView(
                        referenceLat: s.effectiveLatitude,
                        referenceLng: s.effectiveLongitude,
                        initialShelterName: shelterNameCtrl.text,
                        initialShelterAddress: shelterAddressCtrl.text,
                        themeColor: const Color(0xFF673AB7),
                        onShelterSelected: (chosenShelter) {
                          setSheetState(() {
                            shelterNameCtrl.text = chosenShelter.name;
                            shelterAddressCtrl.text = chosenShelter.address;
                            shelterLat = chosenShelter.latitude;
                            shelterLng = chosenShelter.longitude;
                          });
                        },
                        onClearSelection: () {
                          setSheetState(() {
                            shelterNameCtrl.clear();
                            shelterAddressCtrl.clear();
                          });
                        },
                        onRegisterTabActiveChanged: (isRegTab) {
                          isOnRegisterNewTab = isRegTab;
                        },
                      ),
                      if (hasAttemptedSubmit && shelterNameCtrl.text.trim().isEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, size: 14, color: Color(0xFFE53935)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  isOnRegisterNewTab
                                      ? 'You have an unregistered shelter draft. Please press "Register your suggested Shelter" first, or switch to Nearby Shelters to pick an existing one.'
                                      : 'Please choose a nearby shelter or register a new one.',
                                  style: GoogleFonts.nunito(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFFE53935),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                    ],
                    if (action == 'vet') ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF673AB7).withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color:
                                const Color(0xFF673AB7).withValues(alpha: 0.2),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.psychology_alt_rounded,
                                    size: 17, color: Color(0xFF673AB7)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Clinic Temperament Diagnosis (Vet Assessment)',
                                    style: GoogleFonts.nunito(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: _navy,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              s.temperament != null && s.temperament!.isNotEmpty
                                  ? 'Current classification: "${s.temperament == "feral" ? "Feral / Colony Adult" : (s.temperament == "friendly" ? "Friendly Pet" : "Shy Stray")}". If the vet determined otherwise (e.g. diagnosed as feral), select the updated diagnosis:'
                                  : 'Did the veterinarian assess whether this cat is friendly, timid, or an unsocialized feral adult?',
                              style: GoogleFonts.nunito(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _navy.withValues(alpha: 0.65),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                {
                                  'key': 'friendly',
                                  'label': '💖 Friendly Pet',
                                  'color': const Color(0xFF9C27B0),
                                },
                                {
                                  'key': 'shy',
                                  'label': '🐾 Shy Stray',
                                  'color': const Color(0xFF1E88E5),
                                },
                                if (!(s.category == 'Needs Foster' ||
                                    s.category == 'Needs Home' ||
                                    s.isNeedsHome ||
                                    s.isOpenForAdoption))
                                  {
                                    'key': 'feral',
                                    'label': '🌿 Feral Adult (TNR)',
                                    'color': const Color(0xFF00897B),
                                  },
                                {
                                  'key': 'kitten',
                                  'label': '🍼 Kitten',
                                  'color': const Color(0xFFE91E63),
                                },
                              ].map((opt) {
                                final optKey = opt['key'] as String;
                                final optLabel = opt['label'] as String;
                                final optColor = opt['color'] as Color;
                                final isSelected =
                                    selectedDiagnosedTemperament == optKey;
                                return InkWell(
                                  onTap: () {
                                    setSheetState(() {
                                      selectedDiagnosedTemperament =
                                          isSelected ? null : optKey;
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? optColor.withValues(alpha: 0.15)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isSelected
                                            ? optColor
                                            : _navy.withValues(alpha: 0.15),
                                        width: isSelected ? 1.5 : 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isSelected) ...[
                                          Icon(Icons.check_circle_rounded,
                                              size: 13, color: optColor),
                                          const SizedBox(width: 4),
                                        ],
                                        Text(
                                          optLabel,
                                          style: GoogleFonts.nunito(
                                            fontSize: 11,
                                            fontWeight: isSelected
                                                ? FontWeight.w800
                                                : FontWeight.w700,
                                            color: isSelected ? optColor : _navy,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Text(
                      isNoteMandatory
                          ? 'Custom Note / Details (Required)'
                          : 'Custom Note / Details (Optional)',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: noteCtrl,
                      onChanged: (_) => setSheetState(() {}),
                      maxLength: 150,
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _navy,
                      ),
                      decoration: InputDecoration(
                        hintText: isShelteredAction
                            ? 'e.g. Admitted safely into intake quarantine kennel #4'
                            : (isTookInAction
                                ? 'e.g. Safe foster room prepared with food, water, and warm blankets'
                                : 'e.g. Fed 2 cans of cat food near the alleyway'),
                        hintStyle: GoogleFonts.nunito(
                            fontSize: 12,
                            color: _navy.withValues(alpha: 0.35)),
                        filled: true,
                        fillColor: _lavLight,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: ((hasAttemptedSubmit && isNoteMandatory && noteCtrl.text.trim().isEmpty) || (noteCtrl.text.isNotEmpty && noteError != null))
                                ? const Color(0xFFE53935)
                                : BorderSide.none.color,
                            width: ((hasAttemptedSubmit && isNoteMandatory && noteCtrl.text.trim().isEmpty) || (noteCtrl.text.isNotEmpty && noteError != null)) ? 1.5 : 0,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: ((hasAttemptedSubmit && isNoteMandatory && noteCtrl.text.trim().isEmpty) || (noteCtrl.text.isNotEmpty && noteError != null))
                                ? const Color(0xFFE53935)
                                : BorderSide.none.color,
                            width: ((hasAttemptedSubmit && isNoteMandatory && noteCtrl.text.trim().isEmpty) || (noteCtrl.text.isNotEmpty && noteError != null)) ? 1.5 : 0,
                          ),
                        ),
                        counterStyle: GoogleFonts.nunito(
                            fontSize: 10,
                            color: _navy.withValues(alpha: 0.4)),
                      ),
                    ),
                    if (hasAttemptedSubmit && isNoteMandatory && noteCtrl.text.trim().isEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '⚠️ Custom note/details are required for this action.',
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE53935),
                        ),
                      ),
                    ] else if (noteCtrl.text.isNotEmpty && noteError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        noteError,
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE53935),
                        ),
                      ),
                    ],
                    if (isTookInAction &&
                        (!areAllMilestonesFilled || !isCustomGoalValid)) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE65100).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFFE65100).withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.edit_note_rounded,
                                size: 16, color: Color(0xFFE65100)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                !isCustomGoalValid
                                    ? customGoalError
                                    : (firstMilestoneError ??
                                        'Please enter a valid title for all $planDurationDays days to submit your Foster Care Plan.'),
                                style: GoogleFonts.nunito(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFFE65100),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    if (formValidationError != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                formValidationError!,
                                style: GoogleFonts.nunito(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.red.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              canSubmit ? col : col.withValues(alpha: 0.7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: canSubmit ? 2 : 0,
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (isSubmitting) return;
                                if (proofFile == null) {
                                  setSheetState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = isShelteredAction
                                        ? 'Cat photo proof inside the shelter is required to proceed.'
                                        : (action == 'vet'
                                            ? 'Photo proof of the cat at the vet clinic is required to proceed.'
                                            : (isTookInAction
                                                ? 'Photo proof of the cat in your foster setup is required to proceed.'
                                                : (action == 'fed'
                                                    ? 'Photo proof of the cat eating or with food is required.'
                                                    : 'Cat photo proof is required to proceed.')));
                                  });
                                  _snack('⚠️ ${formValidationError!}');
                                  return;
                                }
                                if (isScanning) {
                                  setSheetState(() {
                                    formValidationError = 'AI is validating the cat photo, please wait a moment...';
                                  });
                                  _snack('⏳ AI is verifying the photo, please wait a moment...');
                                  return;
                                }
                                if (scanResult == null || !scanResult!.isValid) {
                                  setSheetState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = scanResult?.message ??
                                        'Photo verification failed: please upload a clear cat photo.';
                                  });
                                  _snack('⚠️ ${formValidationError!}');
                                  return;
                                }
                                if (isShelteredAction) {
                                  final sNameErr =
                                      TextModerationService.validateFacilityName(
                                          shelterNameCtrl.text,
                                          label: 'Shelter');
                                  if (sNameErr != null || shelterNameCtrl.text.trim().isEmpty) {
                                    final msg = isOnRegisterNewTab
                                        ? 'You have an unregistered shelter draft. Please press "Register your suggested Shelter" first, or pick from Nearby Shelters.'
                                        : (sNameErr ?? 'Please select a shelter or register a new one first.');
                                    setSheetState(() {
                                      hasAttemptedSubmit = true;
                                      formValidationError = msg;
                                    });
                                    _snack('⚠️ $msg');
                                    return;
                                  }
                                  final sAddrErr =
                                      TextModerationService.validateAddress(
                                          shelterAddressCtrl.text,
                                          label: 'Shelter address');
                                  if (sAddrErr != null || shelterAddressCtrl.text.trim().isEmpty) {
                                    setSheetState(() {
                                      hasAttemptedSubmit = true;
                                      formValidationError = sAddrErr ?? 'Shelter location address is required.';
                                    });
                                    _snack('⚠️ ${formValidationError!}');
                                    return;
                                  }
                                }
                                if (isTookInAction) {
                                  if (isCustomGoal) {
                                    final goalErr =
                                        TextModerationService.validateTitle(
                                            customGoalCtrl.text,
                                            label: 'Custom goal',
                                            minLength: 4);
                                    if (goalErr != null || customGoalCtrl.text.trim().isEmpty) {
                                      setSheetState(() {
                                        hasAttemptedSubmit = true;
                                        formValidationError = goalErr ?? 'Custom goal is required.';
                                      });
                                      _snack('⚠️ ${formValidationError!}');
                                      return;
                                    }
                                  }
                                  for (int d = 1; d <= planDurationDays; d++) {
                                    final t = getDayCtrl(d, planDurationDays)
                                        .text
                                        .trim();
                                    final mErr =
                                        TextModerationService.validateTitle(
                                            t,
                                            label: 'Day $d theme',
                                            minLength: 4);
                                    if (mErr != null || t.isEmpty) {
                                      setSheetState(() {
                                        hasAttemptedSubmit = true;
                                        formValidationError = mErr ?? 'Day $d theme is required.';
                                      });
                                      _snack('⚠️ ${formValidationError!}');
                                      return;
                                    }
                                  }
                                }
                                if (isNoteMandatory) {
                                  final noteErr =
                                      TextModerationService.validateDescription(
                                          noteCtrl.text,
                                          fieldName: 'Note');
                                  if (noteErr != null || noteCtrl.text.trim().isEmpty) {
                                    setSheetState(() {
                                      hasAttemptedSubmit = true;
                                      formValidationError = noteErr ?? 'Details note is required.';
                                    });
                                    _snack('⚠️ ${formValidationError!}');
                                    return;
                                  }
                                }

                                if (!DoubleTapGuard.allow('action_form_${s.id}')) return;
                                setSheetState(() {
                                  formValidationError = null;
                                  isSubmitting = true;
                                });
                                try {
                                  String finalNote = noteCtrl.text.trim();
                                  if (isShelteredAction &&
                                      shelterNameCtrl.text.trim().isNotEmpty) {
                                    final sAddr =
                                        shelterAddressCtrl.text.trim();
                                    finalNote =
                                        'Admitted to ${shelterNameCtrl.text.trim()}${sAddr.isNotEmpty ? " ($sAddr)" : ""}. $finalNote'
                                            .trim();
                                  }

                                  final isVetRescuer = _uid != null &&
                                      (s.lastVetRescuerId == _uid ||
                                          s.pendingVetRescuerId == _uid ||
                                          (s.lastVetRescuerId == null &&
                                              s.rescueClaimedBy == _uid));
                                  final shouldDirectlyActivateFoster =
                                      isOwner || s.hasVetVisit || isVetRescuer;

                                  if (isTookInAction && !shouldDirectlyActivateFoster) {
                                    final finalGoal = isCustomGoal &&
                                            customGoalCtrl.text.trim().isNotEmpty
                                        ? customGoalCtrl.text.trim()
                                        : selectedCareGoal;
                                    final dynamicMilestones =
                                        List.generate(planDurationDays, (i) => i + 1);
                                    final dailyTitles =
                                        List.generate(planDurationDays, (i) {
                                      final dayNum = i + 1;
                                      final ctrl = getDayCtrl(
                                          dayNum, planDurationDays);
                                      final text = ctrl.text.trim();
                                      if (text.isNotEmpty) return text;
                                      if (dayNum == 1) {
                                        return 'Intake, Quarantine & Safe Settle';
                                      }
                                      if (dayNum == planDurationDays) {
                                        return 'Final Target Outcome & Review';
                                      }
                                      return 'Day $dayNum Daily Care Check';
                                    });

                                    await FirebaseService.instance
                                        .requestCustodyHandover(
                                      sightingId: s.id,
                                      customNote: finalNote,
                                      proofPhotoFile: proofFile,
                                      carePlanGoal: finalGoal,
                                      carePlanDurationDays: planDurationDays,
                                      careMilestoneDays: dynamicMilestones,
                                      customMilestoneTitles: dailyTitles,
                                    );
                                    if (ctx.mounted) {
                                      Navigator.pop(ctx);
                                    }
                                    if (mounted) {
                                      setState(() {
                                        _hasActed = true;
                                        _myAction = action;
                                      });
                                      _snack(
                                          'Foster custody request sent to reporter with your Trust Card! 🤝');
                                    }
                                    return;
                                  }

                                  String? careGoal;
                                  int? careDuration;
                                  List<int>? milestones;
                                  List<String>? milestoneTitles;
                                  if (isTookInAction) {
                                    careGoal = isCustomGoal &&
                                            customGoalCtrl.text.trim().isNotEmpty
                                        ? customGoalCtrl.text.trim()
                                        : selectedCareGoal;
                                    careDuration = planDurationDays;
                                    milestones = List.generate(
                                        planDurationDays, (i) => i + 1);
                                    milestoneTitles = List.generate(
                                        planDurationDays, (i) {
                                      final dayNum = i + 1;
                                      final ctrl = getDayCtrl(
                                          dayNum, planDurationDays);
                                      final text = ctrl.text.trim();
                                      if (text.isNotEmpty) return text;
                                      if (dayNum == 1) {
                                        return 'Intake, Quarantine & Safe Settle';
                                      }
                                      if (dayNum == planDurationDays) {
                                        return 'Final Target Outcome & Review';
                                      }
                                      return 'Day $dayNum Daily Care Check';
                                    });
                                  }

                                  final awardedXp = await FirebaseService
                                      .instance
                                      .logRescueAction(
                                    sightingId: s.id,
                                    action: action,
                                    anonymous: false,
                                    proofPhotoFile: proofFile,
                                    customNote: finalNote,
                                    updatedLatitude:
                                        isShelteredAction ? shelterLat : null,
                                    updatedLongitude:
                                        isShelteredAction ? shelterLng : null,
                                    updatedLocationAddress:
                                        isShelteredAction &&
                                                shelterAddressCtrl.text
                                                    .trim()
                                                    .isNotEmpty
                                            ? shelterAddressCtrl.text.trim()
                                            : null,
                                    markResolved: isShelteredAction,
                                    carePlanGoal: careGoal,
                                    carePlanDurationDays: careDuration,
                                    careMilestoneDays: milestones,
                                    customMilestoneTitles: milestoneTitles,
                                    temperament: action == 'vet'
                                        ? selectedDiagnosedTemperament
                                        : null,
                                  );
                                  if (ctx.mounted) {
                                    Navigator.pop(ctx);
                                  }
                                  if (mounted) {
                                    setState(() {
                                      _hasActed = true;
                                      _myAction = action;
                                    });
                                    if (isTookInAction) {
                                      _snack(
                                          'Foster custody activated! Care plan started 🏡🐾');
                                    } else if (action == 'vet') {
                                      _snack(
                                          'Vet Visit report submitted for verification! 🩺');
                                    } else if (isShelteredAction) {
                                      _snack(
                                          'Cat admitted to shelter! Report marked as Resolved 🏠');
                                    } else if (awardedXp > 0) {
                                      _snack(
                                          'Verified & Logged! +$awardedXp XP awarded 🐾');
                                    } else if (_isOwner(s)) {
                                      _snack(
                                          'Action logged! (XP already collected for this spot recently)');
                                    } else {
                                      _snack(
                                          'Action logged & submitted for reporter verification! 🐾');
                                    }
                                  }
                                } catch (e) {
                                  setSheetState(() => isSubmitting = false);
                                  DoubleTapGuard.reset('action_form_${s.id}');
                                  _snack('Failed to submit: $e');
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(_aIcon(action), size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    proofFile == null
                                        ? 'Attach Cat Photo Proof to Submit'
                                        : (scanResult?.isValid == true
                                            ? (isShelteredAction
                                                ? 'Confirm & Mark Sheltered (+120 XP)'
                                                : 'Confirm & Log $actionLabel (+$xp XP)')
                                            : 'Valid Proof Required'),
                                    style: GoogleFonts.nunito(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    } finally {
      _isActionSheetOpen = false;
    }
  }

  Widget _buildFreshnessBanner(Sighting s) {
    final freshnessText = s.lastSeenFreshness;
    final freshnessColor = s.lastSeenFreshnessColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: freshnessColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: freshnessColor.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: freshnessColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  freshnessText,
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: freshnessColor,
                  ),
                ),
              ),
            ],
          ),
          if (s.lastSeenNote != null && s.lastSeenNote!.trim().isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              'Latest note: "${s.lastSeenNote!.trim()}"',
              style: GoogleFonts.nunito(
                fontSize: 12,
                color: _navy.withValues(alpha: 0.7),
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (s.routineHours != null && s.routineHours!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.schedule,
                    size: 13, color: _navy.withValues(alpha: 0.5)),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    'Usual Active Hours: ${s.routineHours!.trim()}',
                    style: GoogleFonts.nunito(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _navy.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildArchivedBanner(Sighting s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF455A64).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF455A64).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.inventory_2_outlined,
              size: 20, color: Color(0xFF455A64)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Archived Case Record',
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF455A64),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'This rescue was successfully completed over 30 days ago and auto-archived from the active feed. All medical notes, treatment records, and rescuer achievements remain permanently preserved.',
                  style: GoogleFonts.nunito(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: _navy.withValues(alpha: 0.7),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showRoamingUpdateSheet(Sighting s) async {
    if (_isActionSheetOpen) return;
    _isActionSheetOpen = true;
    if (s.isVetVisitPending) {
      _isActionSheetOpen = false;
      _snack('⏳ Vet visit verification is pending. Actions are currently locked.');
      return;
    }
    if (s.isAwaitingPostVetDecision) {
      if (!_isVetRescuer(s) && !_isOwner(s) && !s.isRescuerCustodyDelegated) {
        _isActionSheetOpen = false;
        _snack(
            '⏳ ${s.lastVetRescuerName?.isNotEmpty == true ? s.lastVetRescuerName : "The rescuer"} currently has custody of this cat after vet care.');
        return;
      }
    }
    final selectedOption = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomPadding = MediaQuery.paddingOf(ctx).bottom;
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, bottomPadding > 0 ? bottomPadding + 20 : 32),
          child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: _navy.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9800).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.edit_location_alt,
                        color: Color(0xFFFF9800), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Location & Spot Status',
                        style: GoogleFonts.nunito(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                          color: _navy,
                        ),
                      ),
                      Text(
                        'Keep rescuers updated with live cat presence',
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          color: _navy.withValues(alpha: 0.55),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _buildRoamingOptionTile(
                icon: Icons.check_circle_outline,
                color: const Color(0xFF43A047),
                title: '🐾 Still Here at Pinned Spot',
                subtitle: 'Confirm the cat is right at this location (+ photo)',
                xpTag: '+15 XP',
                onTap: () => Navigator.pop(ctx, 'stillHere'),
              ),
              const SizedBox(height: 10),
              _buildRoamingOptionTile(
                icon: Icons.edit_location_alt_outlined,
                color: const Color(0xFFFF9800),
                title: '📍 Moved Nearby (Update Location)',
                subtitle: 'Cat has moved to a nearby street, alley, or building',
                xpTag: '+25 XP',
                onTap: () => Navigator.pop(ctx, 'moved'),
              ),
              const SizedBox(height: 10),
              _buildRoamingOptionTile(
                icon: Icons.search_off_outlined,
                color: const Color(0xFF78909C),
                title: '🔍 Checked: Cat Not Here Right Now',
                subtitle: 'Visited the area but could not find the cat',
                xpTag: '+10 XP',
                onTap: () => Navigator.pop(ctx, 'notHere'),
              ),
            ],
          ),
        ),
      );
    },
    );

    _isActionSheetOpen = false;
    if (!mounted || selectedOption == null) return;

    if (selectedOption == 'stillHere') {
      _showActionProofSheet('stillHere', s);
    } else if (selectedOption == 'moved') {
      _showRelocationSheet(s);
    } else if (selectedOption == 'notHere') {
      _showNotHereDialog(s);
    }
  }

  Widget _buildRoamingOptionTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required String xpTag,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.nunito(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      color: _navy.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                xpTag,
                style: GoogleFonts.nunito(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapPinMarker({Color color = const Color(0xFFFF9800), IconData icon = Icons.pets}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
        Container(
          width: 8,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(50),
          ),
        ),
      ],
    );
  }

  Widget _buildMapButton(IconData icon, {required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: _navy.withValues(alpha: 0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: _navy),
      ),
    );
  }

  Widget _buildLocationSearchBar({
    required TextEditingController controller,
    required bool isSearching,
    required Color themeColor,
    String hintText = 'Search street, landmark, or city...',
    required ValueChanged<String> onSearch,
    required VoidCallback onClear,
  }) {
    return Container(
      height: 42,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _bgWhite,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _navy.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(Icons.search_rounded,
              size: 18, color: _navy.withValues(alpha: 0.45)),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: onSearch,
              style: GoogleFonts.nunito(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: _navy,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _navy.withValues(alpha: 0.4),
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          if (isSearching)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: themeColor),
              ),
            )
          else if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: onClear,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.close_rounded,
                    size: 16, color: _navy.withValues(alpha: 0.4)),
              ),
            )
          else
            GestureDetector(
              onTap: () => onSearch(controller.text),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Search',
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: themeColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLocationAddressDisplay({
    required String addressText,
    required bool isLocating,
    required bool isGpsAutoFilled,
    required Color themeColor,
    String? errorText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.location_on, size: 16, color: themeColor),
            const SizedBox(width: 8),
            Expanded(
              child: isLocating
                  ? Text(
                      'Fetching real-time location...',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        color: _navy.withValues(alpha: 0.5),
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  : Text(
                      addressText.isNotEmpty
                          ? addressText
                          : 'Tap map or search to pin location',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        color: _navy.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            if (isGpsAutoFilled)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, size: 13, color: _resolved),
                  const SizedBox(width: 3),
                  Text(
                    'GPS Auto-filled',
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      color: _resolved,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              )
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.pin_drop_outlined, size: 13, color: themeColor),
                  const SizedBox(width: 3),
                  Text(
                    'Pinned',
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      color: themeColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
          ],
        ),
        if (errorText != null && errorText.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            errorText,
            style: GoogleFonts.nunito(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFE53935),
            ),
          ),
        ],
      ],
    );
  }

  void _showRelocationSheet(Sighting s) async {
    if (_isActionSheetOpen) return;
    _isActionSheetOpen = true;
    try {
      if (!DoubleTapGuard.allow('relocation_${s.id}', thresholdMs: 800)) return;
      if (!await _ensureNoConflictingRescueTrip(s)) return;
      if (!await _ensureNoConflictingVetCare(s)) return;
    File? proofFile;
    bool isScanning = false;
    CatValidationResult? scanResult;
    bool isSubmitting = false;
    bool hasAttemptedSubmit = false;
    String? formValidationError;
    bool isLocating = false;
    bool isGpsAutoFilled = false;
    bool isSearchingLocation = false;
    double newLat = s.effectiveLatitude;
    double newLng = s.effectiveLongitude;
    String newAddress = s.effectiveLocationAddress;
    final noteCtrl = TextEditingController();
    final addressCtrl = TextEditingController(text: newAddress);
    final searchCtrl = TextEditingController();
    final mapCtrl = MapController();

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> pickPhoto(ImageSource source) async {
            try {
              final picked = await _picker.pickImage(
                source: source,
                maxWidth: 1200,
                maxHeight: 1200,
                imageQuality: 85,
              );
              if (picked == null) return;
              final file = File(picked.path);

              setSheetState(() {
                proofFile = file;
                isScanning = true;
                scanResult = null;
              });

              final result = await _aiService.validateCatImage(file);

              setSheetState(() {
                isScanning = false;
                scanResult = result;
              });
            } catch (e) {
              setSheetState(() => isScanning = false);
              _snack('Error picking photo: $e');
            }
          }

          final isNoteValid = TextModerationService.validateDescription(
                  noteCtrl.text,
                  fieldName: 'Roam note') ==
              null;
          final isAddrValid = TextModerationService.validateAddress(
                  addressCtrl.text,
                  label: 'Location address') ==
              null;
          final canSubmit = proofFile != null &&
              scanResult?.isCat == true &&
              !isScanning &&
              !isSubmitting &&
              isNoteValid &&
              isAddrValid;

          final bottomPadding = MediaQuery.paddingOf(ctx).bottom;
          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, bottomPadding > 0 ? bottomPadding + 20 : 28),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: _navy.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.edit_location_alt,
                            color: Color(0xFFFF9800), size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'Update Cat Location (+25 XP)',
                          style: GoogleFonts.nunito(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Location (Required)',
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildLocationSearchBar(
                      controller: searchCtrl,
                      isSearching: isSearchingLocation,
                      themeColor: const Color(0xFFFF9800),
                      hintText: 'Search street, landmark, or city...',
                      onSearch: (query) async {
                        if (query.trim().isEmpty) return;
                        setSheetState(() => isSearchingLocation = true);
                        final locResult = await LocationService()
                            .searchLocation(query.trim());
                        if (locResult != null) {
                          newLat = locResult.latitude;
                          newLng = locResult.longitude;
                          newAddress = locResult.formattedAddress;
                          addressCtrl.text = newAddress;
                          isGpsAutoFilled = false;
                          try {
                            mapCtrl.move(ll.LatLng(newLat, newLng), 16.0);
                          } catch (_) {}
                        } else {
                          _snack('Location not found. Try a different search term.');
                        }
                        setSheetState(() => isSearchingLocation = false);
                      },
                      onClear: () => setSheetState(() => searchCtrl.clear()),
                    ),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        height: 180,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8EAF0),
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: _navy.withValues(alpha: 0.1)),
                        ),
                        child: Stack(
                          children: [
                            FlutterMap(
                              mapController: mapCtrl,
                              options: MapOptions(
                                initialCenter: ll.LatLng(newLat, newLng),
                                initialZoom: 16.0,
                                onTap: (tapPos, point) async {
                                  newLat = point.latitude;
                                  newLng = point.longitude;
                                  isGpsAutoFilled = false;
                                  setSheetState(() => isLocating = true);
                                  final addr = await LocationService()
                                      .getAddressFromCoordinates(
                                          point.latitude, point.longitude);
                                  newAddress = addr;
                                  addressCtrl.text = addr;
                                  setSheetState(() => isLocating = false);
                                },
                              ),
                              children: [
                                TileLayer(
                                  urlTemplate:
                                      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                  userAgentPackageName: 'com.pawwatch.app',
                                ),
                                MarkerLayer(
                                  markers: [
                                    Marker(
                                      point: ll.LatLng(newLat, newLng),
                                      width: 46,
                                      height: 46,
                                      child: _buildMapPinMarker(
                                        color: const Color(0xFFFF9800),
                                        icon: Icons.pets,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Positioned(
                              right: 10,
                              top: 10,
                              child: Column(
                                children: [
                                  _buildMapButton(
                                    Icons.my_location,
                                    onTap: () async {
                                      setSheetState(() => isLocating = true);
                                      final res = await LocationService()
                                          .getCurrentUserLocation();
                                      newLat = res.latitude;
                                      newLng = res.longitude;
                                      newAddress = res.formattedAddress;
                                      addressCtrl.text = newAddress;
                                      isGpsAutoFilled = res.isGpsAutoFilled;
                                      setSheetState(() => isLocating = false);
                                      try {
                                        mapCtrl.move(
                                            ll.LatLng(newLat, newLng), 16.0);
                                      } catch (_) {}
                                    },
                                  ),
                                  const SizedBox(height: 6),
                                  _buildMapButton(
                                    Icons.add,
                                    onTap: () {
                                      try {
                                        final z = mapCtrl.camera.zoom + 1;
                                        mapCtrl.move(
                                            ll.LatLng(newLat, newLng), z);
                                      } catch (_) {}
                                    },
                                  ),
                                  const SizedBox(height: 4),
                                  _buildMapButton(
                                    Icons.remove,
                                    onTap: () {
                                      try {
                                        final z = mapCtrl.camera.zoom - 1;
                                        mapCtrl.move(
                                            ll.LatLng(newLat, newLng), z);
                                      } catch (_) {}
                                    },
                                  ),
                                ],
                              ),
                            ),
                            Positioned(
                              bottom: 8,
                              left: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.1),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.touch_app_outlined,
                                        size: 12, color: Color(0xFFFF9800)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Tap map to drop pin',
                                      style: GoogleFonts.nunito(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: _navy,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildLocationAddressDisplay(
                      addressText: addressCtrl.text,
                      isLocating: isLocating,
                      isGpsAutoFilled: isGpsAutoFilled,
                      themeColor: const Color(0xFFFF9800),
                      errorText: addressCtrl.text.isNotEmpty
                          ? TextModerationService.validateAddress(
                              addressCtrl.text,
                              label: 'Location address',
                            )
                          : (hasAttemptedSubmit && addressCtrl.text.trim().isEmpty
                              ? '⚠️ Location address is required.'
                              : null),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Live Cat Photo at New Spot (Required)',
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (proofFile == null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                side: BorderSide(
                                    color: (hasAttemptedSubmit && proofFile == null)
                                        ? const Color(0xFFE53935)
                                        : _navy.withValues(alpha: 0.2),
                                    width: (hasAttemptedSubmit && proofFile == null) ? 1.5 : 1),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => pickPhoto(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt,
                                  color: Color(0xFFFF9800), size: 18),
                              label: Text('Take Camera Photo',
                                  style: GoogleFonts.nunito(
                                      fontWeight: FontWeight.w800,
                                      color: _navy,
                                      fontSize: 12)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                side: BorderSide(
                                    color: (hasAttemptedSubmit && proofFile == null)
                                        ? const Color(0xFFE53935)
                                        : _navy.withValues(alpha: 0.2),
                                    width: (hasAttemptedSubmit && proofFile == null) ? 1.5 : 1),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: () => pickPhoto(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library,
                                  color: _lavender, size: 18),
                              label: Text('Pick Gallery',
                                  style: GoogleFonts.nunito(
                                      fontWeight: FontWeight.w800,
                                      color: _navy,
                                      fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                      if (hasAttemptedSubmit && proofFile == null) ...[
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded, size: 14, color: Colors.red.shade700),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '⚠️ Live cat photo at the new spot is required to update location.',
                                  style: GoogleFonts.nunito(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.red.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ] else
                      Container(
                        height: 140,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: scanResult?.isCat == true
                                ? _resolved
                                : (isScanning
                                    ? _lavender
                                    : _urgent),
                            width: 2,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Stack(
                            children: [
                              Image.file(proofFile!,
                                  width: double.infinity,
                                  height: 140,
                                  fit: BoxFit.cover),
                              if (isScanning)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    child: const Center(
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2),
                                    ),
                                  ),
                                ),
                              Positioned(
                                top: 6,
                                right: 6,
                                child: GestureDetector(
                                  onTap: () =>
                                      setSheetState(() => proofFile = null),
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.6),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close,
                                        color: Colors.white, size: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      'Roam Note / Details (Required)',
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: noteCtrl,
                      onChanged: (_) => setSheetState(() {}),
                      maxLength: 120,
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _navy,
                      ),
                      decoration: InputDecoration(
                        hintText: 'e.g. Moved 100m down the street near Indomaret',
                        hintStyle: GoogleFonts.nunito(
                            fontSize: 12, color: _navy.withValues(alpha: 0.35)),
                        filled: true,
                        fillColor: _lavLight,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: ((hasAttemptedSubmit && noteCtrl.text.trim().isEmpty) || (noteCtrl.text.isNotEmpty && TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Roam note') != null))
                                ? const Color(0xFFE53935)
                                : BorderSide.none.color,
                            width: ((hasAttemptedSubmit && noteCtrl.text.trim().isEmpty) || (noteCtrl.text.isNotEmpty && TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Roam note') != null)) ? 1.5 : 0,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: ((hasAttemptedSubmit && noteCtrl.text.trim().isEmpty) || (noteCtrl.text.isNotEmpty && TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Roam note') != null))
                                ? const Color(0xFFE53935)
                                : BorderSide.none.color,
                            width: ((hasAttemptedSubmit && noteCtrl.text.trim().isEmpty) || (noteCtrl.text.isNotEmpty && TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Roam note') != null)) ? 1.5 : 0,
                          ),
                        ),
                        counterStyle: GoogleFonts.nunito(
                            fontSize: 10, color: _navy.withValues(alpha: 0.4)),
                      ),
                    ),
                    if (hasAttemptedSubmit && noteCtrl.text.trim().isEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '⚠️ Roam note / details are required.',
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE53935),
                        ),
                      ),
                    ] else if (noteCtrl.text.isNotEmpty &&
                        TextModerationService.validateDescription(
                                noteCtrl.text,
                                fieldName: 'Roam note') !=
                            null) ...[
                      const SizedBox(height: 4),
                      Text(
                        TextModerationService.validateDescription(
                            noteCtrl.text,
                            fieldName: 'Roam note')!,
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE53935),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (formValidationError != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                formValidationError!,
                                style: GoogleFonts.nunito(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.red.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: canSubmit
                              ? const Color(0xFFFF9800)
                              : const Color(0xFFFF9800).withValues(alpha: 0.7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: canSubmit ? 2 : 0,
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (isSubmitting || !DoubleTapGuard.allow('roam_spot_${s.id}')) return;
                                if (proofFile == null) {
                                  setSheetState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = 'Live cat photo at the new spot is required to proceed.';
                                  });
                                  DoubleTapGuard.reset('roam_spot_${s.id}');
                                  _snack('⚠️ ${formValidationError!}');
                                  return;
                                }
                                if (isScanning) {
                                  setSheetState(() {
                                    formValidationError = 'AI is validating the photo, please wait a moment...';
                                  });
                                  DoubleTapGuard.reset('roam_spot_${s.id}');
                                  _snack('⏳ AI is verifying the photo, please wait a moment...');
                                  return;
                                }
                                if (scanResult?.isCat != true) {
                                  setSheetState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = scanResult?.message ?? 'Photo verification failed: please upload a clear cat photo.';
                                  });
                                  DoubleTapGuard.reset('roam_spot_${s.id}');
                                  _snack('⚠️ ${formValidationError!}');
                                  return;
                                }
                                final addrErr =
                                    TextModerationService.validateAddress(
                                        addressCtrl.text,
                                        label: 'Location address');
                                if (addrErr != null || addressCtrl.text.trim().isEmpty) {
                                  setSheetState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = addrErr ?? 'Location address is required.';
                                  });
                                  DoubleTapGuard.reset('roam_spot_${s.id}');
                                  _snack('⚠️ ${formValidationError!}');
                                  return;
                                }
                                final noteErr =
                                    TextModerationService.validateDescription(
                                        noteCtrl.text,
                                        fieldName: 'Roam note');
                                if (noteErr != null || noteCtrl.text.trim().isEmpty) {
                                  setSheetState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = noteErr ?? 'Roam note / details are required.';
                                  });
                                  DoubleTapGuard.reset('roam_spot_${s.id}');
                                  _snack('⚠️ ${formValidationError!}');
                                  return;
                                }
                                setSheetState(() => isSubmitting = true);
                                try {
                                  final awardedXp = await FirebaseService.instance.logRescueAction(
                                    sightingId: s.id,
                                    action: 'moved',
                                    proofPhotoFile: proofFile,
                                    customNote: noteCtrl.text,
                                    updatedLatitude: newLat,
                                    updatedLongitude: newLng,
                                    updatedLocationAddress: addressCtrl.text.trim(),
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (mounted) {
                                    setState(() {
                                      _hasActed = true;
                                      _myAction = 'moved';
                                    });
                                    if (awardedXp > 0) {
                                      _snack('📍 Location updated! +$awardedXp XP awarded 🐾');
                                    } else {
                                      _snack('📍 Location updated! (XP already collected for this spot recently)');
                                    }
                                  }
                                } catch (e) {
                                  setSheetState(() => isSubmitting = false);
                                  DoubleTapGuard.reset('roam_spot_${s.id}');
                                  _snack('Failed to update: $e');
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : Text(
                                proofFile == null
                                    ? 'Attach Photo to Update Spot'
                                    : 'Confirm Moved Spot (+25 XP)',
                                style: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w800, fontSize: 14),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    } finally {
      _isActionSheetOpen = false;
    }
  }

  void _showNotHereDialog(Sighting s) async {
    if (_isActionSheetOpen) return;
    _isActionSheetOpen = true;
    try {
      if (!DoubleTapGuard.allow('not_here_${s.id}', thresholdMs: 800)) return;
      if (!await _ensureNoConflictingRescueTrip(s)) return;
      if (!await _ensureNoConflictingVetCare(s)) return;
    final noteCtrl = TextEditingController();
    String selectedReason = 'roaming'; // 'roaming' or 'helpedOffline'
    final isOwner = _isOwner(s);

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF78909C).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.search_off_outlined,
                    color: Color(0xFF78909C), size: 22),
              ),
              const SizedBox(width: 10),
              Text('Cat Not at Spot?',
                  style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w800, color: _navy, fontSize: 17)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What is the current situation at this spot?',
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    color: _navy.withValues(alpha: 0.65),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  onTap: () => setDialogState(() => selectedReason = 'roaming'),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selectedReason == 'roaming'
                          ? const Color(0xFF78909C).withValues(alpha: 0.1)
                          : _bgWhite,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selectedReason == 'roaming'
                            ? const Color(0xFF78909C)
                            : _navy.withValues(alpha: 0.12),
                        width: selectedReason == 'roaming' ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selectedReason == 'roaming'
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: const Color(0xFF78909C),
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '🐾 Roaming / Hiding Nearby',
                                style: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w800,
                                    color: _navy,
                                    fontSize: 12.5),
                              ),
                              Text(
                                'Not visible right now. Keep post open for others to check.',
                                style: GoogleFonts.nunito(
                                    color: _navy.withValues(alpha: 0.55),
                                    fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => setDialogState(() => selectedReason = 'helpedOffline'),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: selectedReason == 'helpedOffline'
                          ? _lavender.withValues(alpha: 0.1)
                          : _bgWhite,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selectedReason == 'helpedOffline'
                            ? _lavender
                            : _navy.withValues(alpha: 0.12),
                        width: selectedReason == 'helpedOffline' ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selectedReason == 'helpedOffline'
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: _lavender,
                          size: 18,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '🏠 Already Helped by Local Resident',
                                style: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w800,
                                    color: _navy,
                                    fontSize: 12.5),
                              ),
                              Text(
                                isOwner
                                    ? 'A neighbor or clinic helped offline. Marks report as Resolved.'
                                    : 'A local took the cat in. Alerts community that cat is safe.',
                                style: GoogleFonts.nunito(
                                    color: _navy.withValues(alpha: 0.55),
                                    fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Details or Note (Required):',
                  style: GoogleFonts.nunito(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _navy.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: noteCtrl,
                  onChanged: (_) => setDialogState(() {}),
                  maxLength: 120,
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _navy,
                  ),
                  decoration: InputDecoration(
                    hintText: selectedReason == 'helpedOffline'
                        ? 'e.g. Warung owner took the cat inside safely'
                        : 'e.g. Looked around at 4 PM, nowhere in sight',
                    hintStyle: GoogleFonts.nunito(
                        fontSize: 11.5, color: _navy.withValues(alpha: 0.35)),
                    filled: true,
                    fillColor: _lavLight,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    counterStyle: GoogleFonts.nunito(
                        fontSize: 10, color: _navy.withValues(alpha: 0.4)),
                  ),
                ),
                if (noteCtrl.text.isNotEmpty &&
                    TextModerationService.validateDescription(noteCtrl.text,
                            fieldName: 'Note') !=
                        null) ...[
                  const SizedBox(height: 4),
                  Text(
                    TextModerationService.validateDescription(noteCtrl.text,
                        fieldName: 'Note')!,
                    style: GoogleFonts.nunito(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFFE53935),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: GoogleFonts.nunito(color: _navy)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: selectedReason == 'helpedOffline'
                    ? _lavender
                    : const Color(0xFF78909C),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () async {
                if (!DoubleTapGuard.allow('not_here_dialog_${s.id}')) return;
                final noteErr = TextModerationService.validateDescription(
                    noteCtrl.text,
                    fieldName: 'Note');
                if (noteErr != null) {
                  DoubleTapGuard.reset('not_here_dialog_${s.id}');
                  _snack('⚠️ $noteErr');
                  return;
                }
                Navigator.pop(ctx);
                final isHelped = selectedReason == 'helpedOffline';
                final note = noteCtrl.text.trim();

                final awardedXp = await FirebaseService.instance.logRescueAction(
                  sightingId: s.id,
                  action: isHelped ? 'helpedOffline' : 'notHere',
                  customNote: note.isNotEmpty
                      ? note
                      : (isHelped
                          ? 'A local resident / community member took the cat in safely. 🏠'
                          : 'Checked the area, cat is not visible right now.'),
                  markResolved: isHelped && isOwner,
                );

                if (mounted) {
                  setState(() {
                    _hasActed = true;
                    _myAction = isHelped ? 'helpedOffline' : 'notHere';
                  });
                  if (awardedXp > 0) {
                    _snack(isHelped
                        ? (isOwner
                            ? 'Report marked as Resolved! Cat is safe 🏠 +$awardedXp XP'
                            : 'Update posted: Cat was helped by local! 🐾 +$awardedXp XP')
                        : 'Spot status updated! +$awardedXp XP awarded 🐾');
                  } else {
                    _snack('Spot status updated! (XP already collected for this spot recently)');
                  }
                }
              },
              child: Text(
                  selectedReason == 'helpedOffline'
                      ? (isOwner ? 'Mark Resolved (+50 XP)' : 'Confirm (+30 XP)')
                      : 'Confirm (+10 XP)',
                  style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w800, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
    } finally {
      _isActionSheetOpen = false;
    }
  }

  Future<void> _claimRescue(Sighting s) async {
    try {
      if (!await _ensureNoConflictingRescueTrip(s)) return;
      if (!await _ensureNoConflictingVetCare(s)) return;

      // Distance check
      LocationResult? userLoc;
      try {
        userLoc = await LocationService().getCurrentUserLocation();
      } catch (_) {}
      if (userLoc != null && mounted) {
        final dist = s.calculateDistanceInMeters(userLoc.latitude, userLoc.longitude);
        if (dist > 25000) {
          final confirm = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              title: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF9800), size: 24),
                  const SizedBox(width: 8),
                  Text('Long Distance Trip',
                      style: GoogleFonts.nunito(fontWeight: FontWeight.w800, color: _navy, fontSize: 17)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You are ${(dist / 1000).toStringAsFixed(1)} km away from this spot.',
                    style: GoogleFonts.nunito(fontWeight: FontWeight.w700, color: _navy, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Rescuers have a 45-minute arrival window before the spot automatically reopens to prevent stranded cats. Are you sure you can make it in time?',
                    style: GoogleFonts.nunito(fontSize: 12.5, color: _navy.withValues(alpha: 0.7)),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('Cancel', style: GoogleFonts.nunito(color: _navy)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _lavender,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('Yes, I\'m Heading There',
                      style: GoogleFonts.nunito(fontWeight: FontWeight.w800, fontSize: 13)),
                ),
              ],
            ),
          );
          if (confirm != true) return;
        }
      }

      await FirebaseService.instance.claimRescue(s.id);
      _snack('You are on your way! You have 45 minutes to arrive & log proof 🐾');
    } catch (e) {
      _snack('Failed: $e');
    }
  }

  Future<void> _cancelRescue(Sighting s) async {
    final isReporterOverride = _isOwner(s) && s.rescueClaimedBy != _uid;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(isReporterOverride ? 'Release Spot for Others?' : 'Cancel Rescue?',
            style: GoogleFonts.nunito(fontWeight: FontWeight.w800, color: _navy)),
        content: Text(
            isReporterOverride
                ? 'This will release the current claim and reopen the spot for another rescuer to help.'
                : 'This will let others know nobody is currently on their way.',
            style: GoogleFonts.nunito(color: _navy.withValues(alpha: 0.65))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Keep', style: GoogleFonts.nunito(color: _navy))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(isReporterOverride ? 'Release Spot' : 'Cancel Rescue',
                  style: GoogleFonts.nunito(color: _urgent, fontWeight: FontWeight.w800))),
        ],
      ),
    );
    if (ok == true) {
      await FirebaseService.instance.cancelRescueClaim(s.id);
      _snack(isReporterOverride ? 'Spot released! Open for other rescuers.' : 'Rescue trip cancelled.');
    }
  }

  Future<void> _postComment(String sid) async {
    if (_isPostingComment) return;
    final t = _commentCtrl.text;
    final error = _validateCommentSpam(t);
    if (error != null) {
      _snack(error);
      return;
    }

    setState(() => _isPostingComment = true);
    try {
      await FirebaseService.instance
          .addComment(sightingId: sid, text: t.trim(), anonymous: _isAnon);
      _lastGlobalCommentAt = DateTime.now();
      _lastGlobalCommentText = t.trim();
      _commentCtrl.clear();
      if (mounted) FocusScope.of(context).unfocus();
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _isPostingComment = false);
    }
  }

  Future<void> _postReply(String sid) async {
    if (_isPostingComment) return;
    if (_replyingToId == null) return;
    final t = _replyCtrl.text;
    final error = _validateCommentSpam(t);
    if (error != null) {
      _snack(error);
      return;
    }

    setState(() => _isPostingComment = true);
    try {
      await FirebaseService.instance.addComment(
          sightingId: sid,
          text: t.trim(),
          parentId: _replyingToId,
          anonymous: _isAnon);
      _lastGlobalCommentAt = DateTime.now();
      _lastGlobalCommentText = t.trim();
      _replyCtrl.clear();
      if (mounted) {
        FocusScope.of(context).unfocus();
        setState(() {
          _replyingToId = null;
          _replyingToName = null;
        });
      }
    } catch (e) {
      if (mounted) _snack('$e');
    } finally {
      if (mounted) setState(() => _isPostingComment = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Sighting?>(
      stream: _sightingStream,
      builder: (context, snap) {
        final s = snap.data ?? widget.sighting;
        if (_uid != null && s.blockedUserIds.contains(_uid)) {
          return Scaffold(
            backgroundColor: _bgWhite,
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: _navy),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text('Access Restricted',
                  style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w800, color: _navy, fontSize: 16)),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(28.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: _urgent.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.block_rounded, size: 48, color: _urgent),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Access Restricted',
                      style: GoogleFonts.nunito(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You have been restricted from viewing this sighting report details due to a community report.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        color: _navy.withValues(alpha: 0.65),
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _navy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back, size: 16),
                      label: Text('Back to Feed',
                          style: GoogleFonts.nunito(fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
              ),
            ),
          );
        }
        final isCaretaker = _uid != null &&
            (_uid == s.careTakerId ||
                _isOwner(s) ||
                _uid == s.lastVetRescuerId ||
                _uid == s.pendingVetRescuerId ||
                (s.rescueClaimed && s.rescueClaimedBy == _uid));
        final showWaitingOnTop =
            _hasWaitingStatus(s) && _isInvolvedInWaitingStatus(s);
        if (s.isRescueClaimExpired) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            FirebaseService.instance.checkAndExpireRescueClaim(s.id);
          });
        }
        return Scaffold(
          backgroundColor: _bgWhite,
          body: Stack(
            children: [
              CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(child: _buildCarousel(s)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (showWaitingOnTop) ...[
                            _buildTopWaitingBoxes(s),
                            const SizedBox(height: 14),
                          ],
                          Text(s.displayTitle,
                              style: GoogleFonts.nunito(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: _navy,
                                  height: 1.2)),
                          const SizedBox(height: 10),
                          _buildCategoryBadge(s),
                          Builder(builder: (context) {
                            final canEditTemperament = !s.isVetVisitVerified &&
                                s.urgency != 'resolved' &&
                                (_isOwner(s) ||
                                    (_uid != null &&
                                        (s.pendingVetRescuerId == _uid ||
                                            s.careTakerId == _uid)));
                            if (!canEditTemperament &&
                                s.temperament == null &&
                                !s.hasEarTip) {
                              return const SizedBox.shrink();
                            }

                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (s.temperament == 'feral')
                                    _buildCatTypeBox(
                                      title: 'Feral / Colony Adult',
                                      subtitle: 'Wild adult • Outdoor colony care only',
                                      assetPath: 'assets/images/feral.png',
                                      color: const Color(0xFF00897B),
                                      canEdit: canEditTemperament,
                                      onEdit: canEditTemperament
                                          ? () => _showUpdateCatTemperamentDialog(s)
                                          : null,
                                    ),
                                  if (s.temperament == 'friendly')
                                    _buildCatTypeBox(
                                      title: 'Friendly Pet (Adoptable)',
                                      subtitle: 'Socialized & docile • Suitable for adoption',
                                      assetPath: 'assets/images/friendly.png',
                                      color: const Color(0xFF9C27B0),
                                      canEdit: canEditTemperament,
                                      onEdit: canEditTemperament
                                          ? () => _showUpdateCatTemperamentDialog(s)
                                          : null,
                                    ),
                                  if (s.temperament == 'shy')
                                    _buildCatTypeBox(
                                      title: 'Shy / Timid Stray',
                                      subtitle: 'Cautious stray • Needs gentle approach',
                                      assetPath: 'assets/images/shycat.png',
                                      color: const Color(0xFF1E88E5),
                                      canEdit: canEditTemperament,
                                      onEdit: canEditTemperament
                                          ? () => _showUpdateCatTemperamentDialog(s)
                                          : null,
                                    ),
                                  if (s.temperament == 'kitten')
                                    _buildCatTypeBox(
                                      title: 'Kitten (Under 4 Mo)',
                                      subtitle: 'Young kitten • Safe foster care needed',
                                      assetPath: 'assets/images/kittenwhisperer.png',
                                      color: const Color(0xFFE91E63),
                                      canEdit: canEditTemperament,
                                      onEdit: canEditTemperament
                                          ? () => _showUpdateCatTemperamentDialog(s)
                                          : null,
                                    ),
                                  if (s.hasEarTip) ...[
                                    if (s.temperament != null)
                                      const SizedBox(height: 6),
                                    _buildCatTypeBox(
                                      title: 'Ear-Tipped (TNR Fixed)',
                                      subtitle: 'Ear notched indicating sterilized colony cat',
                                      overline: 'TNR STATUS',
                                      assetPath: 'assets/images/location.png',
                                      color: const Color(0xFF2E7D32),
                                    ),
                                  ],
                                  if (s.temperament == null && canEditTemperament)
                                    _buildAddDiagnosisCard(s),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 12),
                          _buildReporter(s),
                          const SizedBox(height: 12),
                          if (s.isAutoArchived) ...[
                            _buildArchivedBanner(s),
                            const SizedBox(height: 12),
                          ] else if (s.shouldShowLastSeenFreshness) ...[
                            _buildFreshnessBanner(s),
                            const SizedBox(height: 12),
                          ],
                          _buildLocation(s),
                          const SizedBox(height: 14),
                          Divider(color: _navy.withValues(alpha: 0.08), height: 1),
                          const SizedBox(height: 14),
                          if (s.description.trim().isNotEmpty) ...[
                            Text(s.description,
                                style: GoogleFonts.nunito(
                                    fontSize: 14,
                                    color: _navy.withValues(alpha: 0.75),
                                    fontWeight: FontWeight.w600,
                                    height: 1.6)),
                            const SizedBox(height: 14),
                          ],
                          _buildStats(s),
                          const SizedBox(height: 20),
                          if (!showWaitingOnTop &&
                              s.isVetVisitPending &&
                              s.urgency != 'resolved') ...[
                            _buildVetVisitRequestBanner(s),
                            const SizedBox(height: 16),
                          ],
                          if (!showWaitingOnTop &&
                              s.pendingHandoverRescuerId != null &&
                              s.pendingHandoverRescuerId!.isNotEmpty &&
                              s.urgency != 'resolved') ...[
                            _buildHandoverRequestBanner(s),
                            const SizedBox(height: 16),
                          ],
                          if (!showWaitingOnTop &&
                              s.pendingOutcomeAction != null &&
                              s.pendingOutcomeAction!.isNotEmpty &&
                              s.urgency != 'resolved') ...[
                            _buildOutcomeRequestBanner(s),
                            const SizedBox(height: 16),
                          ],
                          if (s.isInCare && !s.isOpenForAdoption) ...[
                            _buildCareMilestoneTimeline(s),
                            const SizedBox(height: 16),
                          ],
                          if (s.isAdoptionShowcase && s.urgency != 'resolved') ...[
                            _buildAdoptionShowcaseCard(s, isCaretaker),
                            const SizedBox(height: 16),
                          ],
                          if (s.isTnrCommunityCat && s.urgency != 'resolved') ...[
                            _buildCommunityCatBanner(s),
                            const SizedBox(height: 16),
                          ],
                          if (s.urgency != 'resolved') ...[
                            _buildActions(s, showWaitingOnTop),
                            if (_hasActed) ...[
                              const SizedBox(height: 12),
                              _buildThanks(),
                            ],
                          ] else ...[
                            _buildResolvedBanner(s),
                          ],
                          const SizedBox(height: 20),
                          _buildCommunity(s),
                          SizedBox(
                            height: ((s.urgency != 'resolved') ? 140.0 : 60.0) +
                                MediaQuery.paddingOf(context).bottom,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Positioned(
                  left: 0, right: 0, bottom: 0, child: _buildRescueBtn(s)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCarousel(Sighting s) {
    final photos = s.photoUrls;
    final has = photos.isNotEmpty;
    return SizedBox(
      height: 300,
      child: Stack(
        children: [
          has
              ? PageView.builder(
                  itemCount: photos.length,
                  onPageChanged: (i) => setState(() => _photoPage = i),
                  itemBuilder: (_, i) {
                    final url = photos[i];
                    return PawImage(
                      url: url,
                      fit: BoxFit.cover,
                      placeholder: _placeholder(),
                    );
                  })
              : _placeholder(),
          Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 90,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black54],
                  ),
                ),
              )),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(children: [
                  IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context)),
                  Expanded(
                      child: Text('Sighting Detail',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.nunito(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: Colors.white))),
                  StreamBuilder<Sighting?>(
                    stream: FirebaseService.instance
                        .streamSightingById(widget.sighting.id),
                    builder: (_, snap2) {
                      final live = snap2.data ?? widget.sighting;
                      return IconButton(
                          icon: const Icon(Icons.more_horiz,
                              color: Colors.white),
                          onPressed: () => _showMore(live));
                    },
                  ),
                ]),
              ),
            ),
          ),

          if (has && photos.length > 1)
            Positioned(
              top: kToolbarHeight + MediaQuery.paddingOf(context).top - 8,
              right: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12)),
                child: Text('${_photoPage + 1}/${photos.length}',
                    style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
              ),
            ),
          if (has && photos.length > 1)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                      photos.length,
                      (i) => AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            margin:
                                const EdgeInsets.symmetric(horizontal: 3),
                            width: i == _photoPage ? 18.0 : 6.0,
                            height: 6,
                            decoration: BoxDecoration(
                              color: i == _photoPage
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ))),
            ),
          if (has && photos.length > 1)
            Positioned(
              bottom: 36,
              right: 14,
              child: GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) =>
                            _AllPhotosScreen(photoUrls: photos))),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(10)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.image_outlined,
                        color: Colors.white, size: 14),
                    const SizedBox(width: 5),
                    Text('View All Photos',
                        style: GoogleFonts.nunito(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
      color: _lavender.withValues(alpha: 0.15),
      child: Center(
          child: Icon(Icons.pets,
              size: 60, color: _lavender.withValues(alpha: 0.4))));



  Widget _buildCommunityCatBanner(Sighting s) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF00897B).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF00897B).withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00897B).withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.pets,
                    color: Color(0xFF00897B), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Community Cat • TNR Care 🌿',
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF00897B),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'This cat completed its recovery care and was safely returned to its territory. Neighbors and local feeders are welcome to log daily feeding, share photos, and check in on its well-being below! 🐾',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        color: _navy.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _communityChip('✂️ Spayed / Neutered'),
              _communityChip('🩺 Vet Checked'),
              _communityChip('🍲 Open for Feeding'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _communityChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: const Color(0xFF00897B).withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: GoogleFonts.nunito(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF00897B),
        ),
      ),
    );
  }

  Widget _buildCatTypeBox({
    required String title,
    required String subtitle,
    required String assetPath,
    required Color color,
    String overline = 'CAT TEMPERAMENT',
    VoidCallback? onEdit,
    bool canEdit = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.22), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Custom logo emblem on the left
          Container(
            width: 44,
            height: 44,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
            ),
            child: Image.asset(
              assetPath,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 12),

          // Informative text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  overline,
                  style: GoogleFonts.nunito(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: GoogleFonts.nunito(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: _navy,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _navy.withValues(alpha: 0.65),
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          if (canEdit && onEdit != null) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap: onEdit,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: color.withValues(alpha: 0.28), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_note_rounded, size: 14, color: color),
                    const SizedBox(width: 3),
                    Text(
                      'Edit',
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAddDiagnosisCard(Sighting s) {
    const color = Color(0xFF673AB7);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.20), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
            ),
            child: const Icon(Icons.medical_services_outlined,
                size: 22, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'CAT TEMPERAMENT',
                  style: GoogleFonts.nunito(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Not Yet Diagnosed',
                  style: GoogleFonts.nunito(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: _navy,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Add diagnosis to guide care decisions',
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _navy.withValues(alpha: 0.65),
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () => _showUpdateCatTemperamentDialog(s),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_rounded, size: 14, color: Colors.white),
                  const SizedBox(width: 3),
                  Text(
                    'Add',
                    style: GoogleFonts.nunito(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryBadge(Sighting s) {
    Color col;
    String asset;
    String label;
    String subtitle;

    final isFinished = s.isFinishedOrResolved;
    final cat = s.category;

    if (s.isSheltered) {
      col = const Color(0xFF673AB7);
      asset = 'assets/images/shelter.png';
      label = 'Cat Sheltered';
      subtitle = 'Safe under verified shelter care';
    } else if (s.isRehomed) {
      col = const Color(0xFF2E7D32);
      asset = 'assets/images/needshome.png';
      label = 'Cat Rehomed';
      subtitle = 'Adopted into a forever home';
    } else if (s.isTnrReturned) {
      col = const Color(0xFF00897B);
      asset = 'assets/images/feral.png';
      label = 'Returned to Colony (TNR)';
      subtitle = 'Sterilized & in outdoor colony care';
    } else if (s.isFeral) {
      col = const Color(0xFF00897B);
      asset = 'assets/images/feral.png';
      label = 'Feral / Colony Cat (TNR)';
      subtitle = 'Wild Adult • Outdoor Colony Care';
    } else if (s.isTnrCommunityCat || cat == 'Community Cat' || cat == 'Community Care') {
      col = const Color(0xFF00897B);
      asset = 'assets/images/colonyfeeder.png';
      label = 'Community Cat (TNR)';
      subtitle = 'Sterilized & Under Community Care';
    } else if (cat == 'Urgent Rescue' || cat == 'Trapped') {
      col = const Color(0xFFFF5722);
      asset = 'assets/images/trapped.png';
      label = 'Trapped / In Danger';
      subtitle = 'One-Time Extraction Task';
    } else if (cat == 'Injured') {
      col = _urgent;
      asset = 'assets/images/injuredsick.png';
      label = 'Injured / Sick';
      subtitle = 'Medical & Vet Attention Needed';
    } else if (cat == 'Kitten') {
      col = const Color(0xFFE91E63);
      asset = 'assets/images/kittenwhisperer.png';
      label = 'Vulnerable Kitten(s)';
      subtitle = 'Needs Safe Foster or Care';
    } else if (cat == 'Needs Foster' || cat == 'Needs Home') {
      col = const Color(0xFF9C27B0);
      asset = 'assets/images/needshome.png';
      label = 'Needs Foster / Adopter';
      subtitle = 'Looking for Temporary/Permanent Home';
    } else if (cat == 'Feeding Spot' || cat == 'Stray' || cat == 'Stray Cat') {
      col = _lavender;
      asset = 'assets/images/straycare.png';
      label = 'Stray / Feeding Spot';
      subtitle = 'Ongoing Community Care & Food';
    } else if (cat == 'Needs Vet' || cat == 'Vet Visit') {
      col = _urgent;
      asset = 'assets/images/review.png';
      label = 'Vet Treatment Required';
      subtitle = 'Needs Clinic Visit';
    } else if (cat == 'Resolved' || s.isResolved) {
      col = _resolved;
      asset = 'assets/images/guardianangel.png';
      label = 'Rescue Resolved';
      subtitle = 'Cat is safe and accounted for';
    } else {
      col = _lavender;
      asset = 'assets/images/streetscout.png';
      label = cat.isNotEmpty ? cat : 'Spotted Stray';
      subtitle = 'Community Cat Sighting';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: col.withValues(alpha: 0.22), width: 1.2),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Custom logo emblem on the left
          Container(
            width: 44,
            height: 44,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: col.withValues(alpha: 0.2), width: 1),
            ),
            child: Image.asset(
              asset,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 12),

          // Informative text in the middle
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'REPORT TYPE',
                  style: GoogleFonts.nunito(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: col,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: GoogleFonts.nunito(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                    color: _navy,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _navy.withValues(alpha: 0.65),
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Metadata tag on the right (DONE if finished/resolved, else ONE-TIME or ONGOING)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: isFinished
                  ? const Color(0xFF2E7D32).withValues(alpha: 0.1)
                  : Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isFinished
                    ? const Color(0xFF2E7D32).withValues(alpha: 0.3)
                    : col.withValues(alpha: 0.22),
                width: 0.8,
              ),
            ),
            child: Text(
              isFinished ? 'DONE' : (s.isOneTimeTask ? 'ONE-TIME' : 'ONGOING'),
              style: GoogleFonts.nunito(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: isFinished ? const Color(0xFF2E7D32) : col,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReporter(Sighting s) => Row(children: [
        GestureDetector(
          onTap: () => _showRescuerTrustModal(s.reporterId, s.reporterName),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: _avColor(s.reporterName), shape: BoxShape.circle),
                  child: Center(
                      child: Text(_ini(s.reporterName),
                          style: GoogleFonts.nunito(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Colors.white)))),
              const SizedBox(width: 10),
            ],
          ),
        ),
        Expanded(
            child: GestureDetector(
          onTap: () => _showRescuerTrustModal(s.reporterId, s.reporterName),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(s.reporterName,
                        style: GoogleFonts.nunito(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _navy)),
                    const SizedBox(width: 4),
                    Icon(Icons.shield_outlined, size: 13, color: _lavender),
                  ],
                ),
                Text('${s.timeAgo}  \u2022  ${s.distance}',
                    style: GoogleFonts.nunito(
                        fontSize: 12,
                        color: _navy.withValues(alpha: 0.5),
                        fontWeight: FontWeight.w600)),
              ]),
        )),
      ]);

  Widget _buildHandoverRequestBanner(Sighting s) {
    final rescuerUid = s.pendingHandoverRescuerId ?? '';
    final rescuerName = s.pendingHandoverRescuerName ?? 'Volunteer';
    final isOwner = _isOwner(s);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF673AB7).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF673AB7).withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF673AB7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.handshake_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Foster Custody Handover Request',
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF673AB7),
                      ),
                    ),
                    Text(
                      '$rescuerName volunteered to take this cat into foster care',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _navy.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () => _showRescuerTrustModal(rescuerUid, rescuerName),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF673AB7).withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shield_outlined,
                      size: 16, color: Color(0xFF673AB7)),
                  const SizedBox(width: 6),
                  Text(
                    'Inspect $rescuerName\'s Trust Card & Rating',
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF673AB7),
                    ),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right,
                      size: 16, color: Color(0xFF673AB7)),
                ],
              ),
            ),
          ),
          if (s.carePlanGoal != null && s.carePlanGoal!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF673AB7).withValues(alpha: 0.15)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.assignment_turned_in_outlined,
                          size: 15, color: Color(0xFF673AB7)),
                      const SizedBox(width: 6),
                      Text(
                        'Proposed Care Plan (${s.effectiveDurationDays} Days):',
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF673AB7),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '🎯 Goal: ${s.carePlanGoal}',
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.effectiveMilestoneDays.length <= 5
                        ? '📅 Everyday Updates: ${s.effectiveMilestoneDays.map((d) => "Day $d").join(" ➔ ")}'
                        : '📅 Everyday Updates: Day 1 to Day ${s.effectiveMilestoneDays.last} (${s.effectiveMilestoneDays.length} Daily Check-ins)',
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _navy.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () {
              final otherId = isOwner ? rescuerUid : s.reporterId;
              final otherName = isOwner ? rescuerName : s.reporterName;
              final otherRole = isOwner ? 'Foster Volunteer' : 'Reporter';
              if (otherId.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CoordinationChatScreen(
                      sighting: s,
                      otherUserId: otherId,
                      otherUserName: otherName,
                      otherUserRole: otherRole,
                    ),
                  ),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF673AB7).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF673AB7).withValues(alpha: 0.25)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.chat_bubble_outline_rounded,
                      size: 15, color: Color(0xFF673AB7)),
                  const SizedBox(width: 6),
                  Text(
                    isOwner
                        ? '💬 Chat & Coordinate with $rescuerName'
                        : '💬 Chat with Reporter (${s.reporterName})',
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF673AB7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isOwner) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red.shade400,
                      side: BorderSide(color: Colors.red.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      try {
                        await FirebaseService.instance.declineCustodyHandover(
                          sightingId: s.id,
                          updateId: s.pendingHandoverUpdateId,
                          rescuerId: s.pendingHandoverRescuerId,
                        );
                        _snack('Foster handover request declined.');
                      } catch (e) {
                        _snack('Error declining handover: $e');
                      }
                    },
                    child: Text(
                      'Decline',
                      style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w800, fontSize: 12.5),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 2,
                    ),
                    onPressed: () async {
                      try {
                        await FirebaseService.instance.approveCustodyHandover(
                          sightingId: s.id,
                          updateId: s.pendingHandoverUpdateId,
                          rescuerUid: rescuerUid,
                          rescuerName: rescuerName,
                          carePlanGoal: s.carePlanGoal,
                          carePlanDurationDays: s.carePlanDurationDays,
                          careMilestoneDays: s.careMilestoneDays,
                        );
                        _snack(
                            'Handover approved! Custody transferred to $rescuerName 🐾');
                        _showReporterReviewSheet(rescuerUid, rescuerName, s.id);
                      } catch (e) {
                        _snack('Error approving handover: $e');
                      }
                    },
                    icon: const Icon(Icons.check, size: 16),
                    label: Text(
                      'Approve Handover',
                      style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w800, fontSize: 12.5),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              '⏳ Awaiting reporter review. Custody will be transferred upon reporter approval.',
              style: GoogleFonts.nunito(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: _navy.withValues(alpha: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showReporterReviewSheet(
      String rescuerUid, String rescuerName, String sightingId) {
    double selectedRating = 5.0;
    final commentCtrl = TextEditingController();
    bool isSubmitting = false;
    bool hasAttemptedSubmit = false;
    String? formValidationError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final commentErr = commentCtrl.text.trim().isNotEmpty
              ? TextModerationService.validateComment(commentCtrl.text)
              : null;

          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, 28 + MediaQuery.paddingOf(ctx).bottom),
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
                      const Icon(Icons.star_rounded,
                          color: Color(0xFFFFA000), size: 26),
                      const SizedBox(width: 8),
                      Text(
                        'Rate Rescuer & Endorse',
                        style: GoogleFonts.nunito(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'How was your experience coordinating with $rescuerName? Your review builds trust in the community.',
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      color: _navy.withValues(alpha: 0.65),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(5, (index) {
                        final starValue = (index + 1).toDouble();
                        return GestureDetector(
                          onTap: () => setSheetState(
                              () => selectedRating = starValue),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4),
                            child: Icon(
                              starValue <= selectedRating
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: const Color(0xFFFFA000),
                              size: 38,
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Feedback / Endorsement Note (Optional)',
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: commentCtrl,
                    onChanged: (_) => setSheetState(() {}),
                    maxLines: 2,
                    style:
                        GoogleFonts.nunito(fontSize: 13, color: _navy),
                    decoration: InputDecoration(
                      hintText:
                          'e.g. Very responsive, arrived with clean carrier and gentle with the cat! ⭐',
                      filled: true,
                      fillColor: _lavLight,
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: (hasAttemptedSubmit && commentErr != null)
                              ? const Color(0xFFE53935)
                              : BorderSide.none.color,
                          width: (hasAttemptedSubmit && commentErr != null) ? 1.5 : 0,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: (hasAttemptedSubmit && commentErr != null)
                              ? const Color(0xFFE53935)
                              : Colors.transparent,
                          width: (hasAttemptedSubmit && commentErr != null) ? 1.5 : 0,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: (hasAttemptedSubmit && commentErr != null)
                              ? const Color(0xFFE53935)
                              : _lavender,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                  if (hasAttemptedSubmit && commentErr != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '⚠️ $commentErr',
                      style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFE53935),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (formValidationError != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFEF5350)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFD32F2F)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              formValidationError!,
                              style: GoogleFonts.nunito(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFB71C1C),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _lavender,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              if (commentCtrl.text.trim().isNotEmpty) {
                                final err = TextModerationService.validateComment(commentCtrl.text);
                                if (err != null) {
                                  setSheetState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = '⚠️ $err';
                                  });
                                  return;
                                }
                              }
                              setSheetState(() {
                                isSubmitting = true;
                                formValidationError = null;
                              });
                              try {
                                await FirebaseService.instance
                                    .submitRescuerReview(
                                  rescuerUid: rescuerUid,
                                  rating: selectedRating,
                                  comment: commentCtrl.text
                                          .trim()
                                          .isNotEmpty
                                      ? commentCtrl.text.trim()
                                      : 'Verified and approved custody handover!',
                                  sightingId: sightingId,
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                _snack(
                                    'Thank you! Review & endorsement submitted 🐾');
                              } catch (e) {
                                setSheetState(
                                    () {
                                      isSubmitting = false;
                                      formValidationError = 'Error submitting review: $e';
                                    });
                              }
                            },
                      child: isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2),
                            )
                          : Text('Submit Review & Endorse',
                              style: GoogleFonts.nunito(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800)),
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

  Widget _buildCareMilestoneTimeline(Sighting s) {
    final isCaretaker = _uid == s.careTakerId;
    final mDays = s.effectiveMilestoneDays;
    final titles = s.effectiveMilestoneTitles;
    final planGoal = s.carePlanGoal?.isNotEmpty == true
        ? s.carePlanGoal!
        : 'Foster & Welfare Care';

    final milestones = List.generate(mDays.length, (idx) {
      final day = mDays[idx];
      final titleText = idx < titles.length ? titles[idx] : 'Daily Care Check';
      final isLast = idx == mDays.length - 1;
      final isFirst = idx == 0;
      final xp = isFirst ? 30 : (isLast ? 60 : 25);
      final icon = isFirst
          ? Icons.home_outlined
          : (isLast ? Icons.verified_outlined : Icons.healing_outlined);
      final desc = isFirst
          ? 'Initial intake, health check, quarantine & safe settle'
          : (isLast
              ? 'Target goal outcome assessment & final welfare review ($planGoal)'
              : 'Day $day health, appetite & daily welfare checkpoint');

      return {
        'index': idx + 1,
        'day': day,
        'title': 'Day $day: $titleText',
        'desc': desc,
        'xp': xp,
        'icon': icon,
      };
    });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: _lavender.withValues(alpha: 0.25), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Title on top
          Text(
            'Care Progress Lifecycle',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: _navy,
            ),
          ),
          const SizedBox(height: 10),

          // Custom logo in the middle
          Center(
            child: Image.asset(
              'assets/images/warmhavenfoster.png',
              height: 72,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 10),

          // In care with ... (short desc on the bottom)
          Text(
            'In care with ${s.careTakerName ?? "Caretaker"} • ${s.daysInCare} ${s.daysInCare == 1 ? "day" : "days"} in care',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: _navy.withValues(alpha: 0.65),
            ),
          ),
          const SizedBox(height: 14),
          Divider(color: _lavender.withValues(alpha: 0.18), height: 1),
          const SizedBox(height: 14),
          Column(
            children: milestones.map((m) {
              final day = m['day'] as int;
              final title = m['title'] as String;
              final desc = m['desc'] as String;
              final xp = m['xp'] as int;
              final icon = m['icon'] as IconData;
              final isDone = s.isMilestoneDone(day);
              final isDue = s.isMilestoneDue(day);

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDone
                      ? const Color(0xFF2E7D32).withValues(alpha: 0.06)
                      : isDue
                          ? _lavLight
                          : _navy.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDone
                        ? const Color(0xFF2E7D32).withValues(alpha: 0.25)
                        : isDue
                            ? _lavender.withValues(alpha: 0.4)
                            : _navy.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isDone
                            ? const Color(0xFF2E7D32)
                            : isDue
                                ? _lavender
                                : _navy.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isDone ? Icons.check : icon,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  title,
                                  style: GoogleFonts.nunito(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w800,
                                    color: _navy,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '+$xp XP',
                                style: GoogleFonts.nunito(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: isDone
                                      ? const Color(0xFF2E7D32)
                                      : _lavender,
                                ),
                              ),
                            ],
                          ),
                          Text(
                            desc,
                            style: GoogleFonts.nunito(
                              fontSize: 11,
                              color: _navy.withValues(alpha: 0.6),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isDone)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF2E7D32).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Verified',
                          style: GoogleFonts.nunito(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF2E7D32),
                          ),
                        ),
                      )
                    else if (isCaretaker && isDue)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _lavender,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () => _showCareMilestoneSheet(day, s),
                        child: Text(
                          'Check In',
                          style: GoogleFonts.nunito(
                              fontSize: 11, fontWeight: FontWeight.w800),
                        ),
                      )
                    else if (isDue)
                      Text(
                        'Due Now ⚡',
                        style: GoogleFonts.nunito(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFFFA000),
                        ),
                      )
                    else
                      Text(
                        'Step ${m["index"]}',
                        style: GoogleFonts.nunito(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _navy.withValues(alpha: 0.35),
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _showCareMilestoneSheet(int milestoneDay, Sighting s) {
    File? proofFile;
    File? proofVideoFile;
    bool isSubmitting = false;
    bool hasAttemptedSubmit = false;
    String? formValidationError;
    bool isScanningPhoto = false;
    CatValidationResult? scanResult;
    String selectedCondition = 'Recovering & Eating Well';
    final conditions = [
      'Recovering & Eating Well',
      'Under Vet Treatment',
      'Active & Playful',
      'Ready for Adoption',
      '✏️ Custom Condition',
    ];
    bool isCustomCondition = false;
    final customConditionCtrl = TextEditingController();
    final noteCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> pickPhoto(ImageSource source) async {
            try {
              final picked = await _picker.pickImage(
                source: source,
                maxWidth: 1200,
                maxHeight: 1200,
                imageQuality: 85,
              );
              if (picked == null) return;
              final file = File(picked.path);
              setSheetState(() {
                proofFile = file;
                isScanningPhoto = true;
                scanResult = null;
              });

              final result = await _aiService.validateCatImage(file);
              setSheetState(() {
                isScanningPhoto = false;
                scanResult = result;
              });
            } catch (e) {
              setSheetState(() => isScanningPhoto = false);
              _snack('Error picking photo: $e');
            }
          }

          Future<void> pickVideo(ImageSource source) async {
            try {
              final picked = await _picker.pickVideo(
                source: source,
                maxDuration: const Duration(minutes: 1),
              );
              if (picked == null) return;
              final file = File(picked.path);
              final bytes = await file.length();
              if (bytes > 25 * 1024 * 1024) {
                _snack(
                    'Video is ${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB. Max allowed size is 25 MB.');
                return;
              }
              setSheetState(() => proofVideoFile = file);
            } catch (e) {
              _snack('Error picking video: $e');
            }
          }


          final isCustomFilled = !isCustomCondition ||
              customConditionCtrl.text.trim().isNotEmpty;
          final isNoteValid = TextModerationService.validateDescription(
                  noteCtrl.text,
                  fieldName: 'Care note') ==
              null;
          final canSubmit = !isSubmitting &&
              proofFile != null &&
              scanResult?.isCat == true &&
              !isScanningPhoto &&
              isCustomFilled &&
              isNoteValid;

          final xp = milestoneDay == 1
              ? 30
              : (milestoneDay == s.effectiveMilestoneDays.last ? 60 : 25);

          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, 28 + MediaQuery.paddingOf(ctx).bottom),
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
                            color: _lavender.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.verified_rounded,
                              color: _lavender, size: 22),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Care Milestone Check-In',
                                style: GoogleFonts.nunito(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: _navy,
                                ),
                              ),
                              Text(
                                'Day $milestoneDay Welfare Checkpoint for ${s.displayTitle}',
                                style: GoogleFonts.nunito(
                                  fontSize: 12,
                                  color: _navy.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Current Cat Condition',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: conditions.map((cond) {
                        final sel = (cond == '✏️ Custom Condition' &&
                                isCustomCondition) ||
                            (!isCustomCondition && selectedCondition == cond);
                        return GestureDetector(
                          onTap: () {
                            setSheetState(() {
                              if (cond == '✏️ Custom Condition') {
                                isCustomCondition = true;
                              } else {
                                isCustomCondition = false;
                                selectedCondition = cond;
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: sel ? _lavender : _lavLight,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: sel
                                    ? _lavender
                                    : _lavender.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Text(
                              cond,
                              style: GoogleFonts.nunito(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: sel ? Colors.white : _navy,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (isCustomCondition) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: customConditionCtrl,
                        onChanged: (_) => setSheetState(() {}),
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          color: _navy,
                          fontWeight: FontWeight.w600,
                        ),
                        decoration: InputDecoration(
                          hintText:
                              'Enter condition (e.g. Limping less, resting quietly, wound clean)',
                          hintStyle: GoogleFonts.nunito(
                            fontSize: 12,
                            color: _navy.withValues(alpha: 0.4),
                          ),
                          filled: true,
                          fillColor: _lavLight,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: (hasAttemptedSubmit && isCustomCondition && customConditionCtrl.text.trim().isEmpty)
                                  ? const Color(0xFFE53935)
                                  : BorderSide.none.color,
                              width: (hasAttemptedSubmit && isCustomCondition && customConditionCtrl.text.trim().isEmpty) ? 1.5 : 0,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: (hasAttemptedSubmit && isCustomCondition && customConditionCtrl.text.trim().isEmpty)
                                  ? const Color(0xFFE53935)
                                  : BorderSide.none.color,
                              width: (hasAttemptedSubmit && isCustomCondition && customConditionCtrl.text.trim().isEmpty) ? 1.5 : 0,
                            ),
                          ),
                        ),
                      ),
                      if (hasAttemptedSubmit && isCustomCondition && customConditionCtrl.text.trim().isEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '⚠️ Custom condition description is required.',
                          style: GoogleFonts.nunito(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFE53935),
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Care Notes / Medical Update (Required)',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: noteCtrl,
                      onChanged: (_) => setSheetState(() {}),
                      maxLines: 2,
                      style:
                          GoogleFonts.nunito(fontSize: 13, color: _navy),
                      decoration: InputDecoration(
                        hintText:
                            'e.g. Eating wet food well, clean litter box habits, wound healing.',
                        filled: true,
                        fillColor: _lavLight,
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: ((hasAttemptedSubmit && noteCtrl.text.trim().isEmpty) || (noteCtrl.text.isNotEmpty && TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Care note') != null))
                                ? const Color(0xFFE53935)
                                : BorderSide.none.color,
                            width: ((hasAttemptedSubmit && noteCtrl.text.trim().isEmpty) || (noteCtrl.text.isNotEmpty && TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Care note') != null)) ? 1.5 : 0,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: ((hasAttemptedSubmit && noteCtrl.text.trim().isEmpty) || (noteCtrl.text.isNotEmpty && TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Care note') != null))
                                ? const Color(0xFFE53935)
                                : BorderSide.none.color,
                            width: ((hasAttemptedSubmit && noteCtrl.text.trim().isEmpty) || (noteCtrl.text.isNotEmpty && TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Care note') != null)) ? 1.5 : 0,
                          ),
                        ),
                      ),
                    ),
                    if (hasAttemptedSubmit && noteCtrl.text.trim().isEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '⚠️ Care notes / medical update are required.',
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE53935),
                        ),
                      ),
                    ] else if (noteCtrl.text.isNotEmpty &&
                        TextModerationService.validateDescription(
                                noteCtrl.text,
                                fieldName: 'Care note') !=
                            null) ...[
                      const SizedBox(height: 4),
                      Text(
                        TextModerationService.validateDescription(
                            noteCtrl.text,
                            fieldName: 'Care note')!,
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE53935),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Photo Proof of Cat (Mandatory - AI Checked)',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Please take a photo showing the cat during this check-in to verify care.',
                      style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        color: _navy.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (proofFile != null) ...[
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(proofFile!,
                                width: 120,
                                height: 90,
                                fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => setSheetState(() {
                                proofFile = null;
                                scanResult = null;
                              }),
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (isScanningPhoto)
                        Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: _lavender,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'AI verifying cat photo...',
                              style: GoogleFonts.nunito(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _lavender,
                              ),
                            ),
                          ],
                        )
                      else if (scanResult != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: scanResult!.isCat
                                ? const Color(0xFF2E7D32).withValues(alpha: 0.1)
                                : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: scanResult!.isCat
                                  ? const Color(0xFF2E7D32).withValues(alpha: 0.3)
                                  : Colors.red.shade300,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                scanResult!.isCat
                                    ? Icons.verified_rounded
                                    : Icons.error_outline_rounded,
                                size: 14,
                                color: scanResult!.isCat
                                    ? const Color(0xFF2E7D32)
                                    : Colors.red.shade700,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  scanResult!.isCat
                                      ? 'Cat Verified (${(scanResult!.confidence * 100).toStringAsFixed(0)}%) 🐾'
                                      : scanResult!.message,
                                  style: GoogleFonts.nunito(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: scanResult!.isCat
                                        ? const Color(0xFF1B5E20)
                                        : Colors.red.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ] else ...[
                      Row(
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _lavender,
                              side: BorderSide(
                                  color: (hasAttemptedSubmit && proofFile == null)
                                      ? const Color(0xFFE53935)
                                      : _lavender.withValues(alpha: 0.5),
                                  width: (hasAttemptedSubmit && proofFile == null) ? 1.5 : 1),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(12)),
                            ),
                            onPressed: () =>
                                pickPhoto(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt_outlined,
                                size: 16),
                            label: Text('Camera',
                                style: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _navy,
                              side: BorderSide(
                                  color: (hasAttemptedSubmit && proofFile == null)
                                      ? const Color(0xFFE53935)
                                      : _navy.withValues(alpha: 0.2),
                                  width: (hasAttemptedSubmit && proofFile == null) ? 1.5 : 1),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(12)),
                            ),
                            onPressed: () =>
                                pickPhoto(ImageSource.gallery),
                            icon: const Icon(
                                Icons.photo_library_outlined,
                                size: 16),
                            label: Text('Gallery',
                                style: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                      if (hasAttemptedSubmit && proofFile == null) ...[
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded, size: 14, color: Colors.red.shade700),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '⚠️ Cat photo proof is mandatory for milestone check-in.',
                                  style: GoogleFonts.nunito(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.red.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),

                    // Optional Video Section
                    Row(
                      children: [
                        Text(
                          'Video Clip',
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _lavender.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Optional',
                            style: GoogleFonts.nunito(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: _lavender,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Add a short video (up to 1 min) showing cat recovery, feeding, or playful movement.',
                      style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        color: _navy.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (proofVideoFile != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ReelVideoPlayer(
                            videoFile: proofVideoFile,
                            maxHeight: 280,
                            autoPlay: true,
                            isLooping: true,
                            onRemove: () =>
                                setSheetState(() => proofVideoFile = null),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  size: 14, color: Color(0xFF2E7D32)),
                              const SizedBox(width: 4),
                              Text(
                                'Reel attached • Tap ✕ to remove',
                                style: GoogleFonts.nunito(
                                  fontSize: 11,
                                  color: const Color(0xFF2E7D32),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _lavender,
                              side: BorderSide(
                                  color: _lavender.withValues(alpha: 0.4)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => pickVideo(ImageSource.camera),
                            icon: const Icon(Icons.videocam_outlined, size: 16),
                            label: Text('Record Video',
                                style: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                          const SizedBox(width: 10),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _navy,
                              side: BorderSide(
                                  color: _navy.withValues(alpha: 0.2)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: () => pickVideo(ImageSource.gallery),
                            icon: const Icon(Icons.video_library_outlined, size: 16),
                            label: Text('Pick Video',
                                style: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                        ],
                      ),
                    const SizedBox(height: 20),
                    if (formValidationError != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                formValidationError!,
                                style: GoogleFonts.nunito(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.red.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              canSubmit ? _lavender : _lavender.withValues(alpha: 0.7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: canSubmit ? 2 : 0,
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (isSubmitting || !DoubleTapGuard.allow('milestone_${s.id}_$milestoneDay')) return;
                                if (proofFile == null) {
                                  setSheetState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = 'Cat photo proof is required to verify milestone check-in.';
                                  });
                                  DoubleTapGuard.reset('milestone_${s.id}_$milestoneDay');
                                  _snack('⚠️ ${formValidationError!}');
                                  return;
                                }
                                if (isScanningPhoto) {
                                  setSheetState(() {
                                    formValidationError = 'AI is validating the photo, please wait a moment...';
                                  });
                                  DoubleTapGuard.reset('milestone_${s.id}_$milestoneDay');
                                  _snack('⏳ AI is verifying the photo, please wait a moment...');
                                  return;
                                }
                                if (scanResult?.isCat != true) {
                                  setSheetState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = scanResult?.message ?? 'Photo verification failed: please upload a clear cat photo.';
                                  });
                                  DoubleTapGuard.reset('milestone_${s.id}_$milestoneDay');
                                  _snack('⚠️ ${formValidationError!}');
                                  return;
                                }
                                if (isCustomCondition &&
                                    customConditionCtrl.text.trim().isEmpty) {
                                  setSheetState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = 'Please enter a description for the custom condition.';
                                  });
                                  DoubleTapGuard.reset('milestone_${s.id}_$milestoneDay');
                                  _snack('⚠️ ${formValidationError!}');
                                  return;
                                }
                                final noteErr =
                                    TextModerationService.validateDescription(
                                        noteCtrl.text,
                                        fieldName: 'Care note');
                                if (noteErr != null || noteCtrl.text.trim().isEmpty) {
                                  setSheetState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = noteErr ?? 'Care notes / medical update are required.';
                                  });
                                  DoubleTapGuard.reset('milestone_${s.id}_$milestoneDay');
                                  _snack('⚠️ ${formValidationError!}');
                                  return;
                                }
                                setSheetState(() => isSubmitting = true);
                                try {
                                  final finalCondition = isCustomCondition &&
                                          customConditionCtrl.text
                                              .trim()
                                              .isNotEmpty
                                      ? customConditionCtrl.text.trim()
                                      : selectedCondition;
                                  final earned = await FirebaseService
                                      .instance
                                      .submitCareMilestoneCheckIn(
                                    sightingId: s.id,
                                    milestoneDay: milestoneDay,
                                    conditionStatus: finalCondition,
                                    careNote: noteCtrl.text
                                            .trim()
                                            .isNotEmpty
                                        ? noteCtrl.text.trim()
                                        : finalCondition,
                                    proofPhotoFile: proofFile,
                                    proofVideoFile: proofVideoFile,
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  _snack(
                                      'Day $milestoneDay Check-In verified! +$earned XP awarded 🐾');
                                } catch (e) {
                                  setSheetState(
                                      () => isSubmitting = false);
                                  DoubleTapGuard.reset('milestone_${s.id}_$milestoneDay');
                                  _snack('Failed to submit check-in: $e');
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.check_circle_outline,
                                      size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    proofFile == null
                                        ? 'Attach Photo to Verify Check-In'
                                        : (isCustomCondition &&
                                                customConditionCtrl.text
                                                    .trim()
                                                    .isEmpty
                                            ? 'Enter Custom Condition to Submit'
                                            : 'Verify Check-In (+$xp XP)'),
                                    style: GoogleFonts.nunito(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTopWaitingBoxes(Sighting s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!s.isAwaitingPostVetDecision) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFE65100).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFE65100).withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.priority_high_rounded,
                      size: 14, color: Color(0xFFE65100)),
                  const SizedBox(width: 5),
                  Text(
                    'PRIORITY • AWAITING YOUR RESPONSE',
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFE65100),
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (s.isVetVisitPending) ...[
            _buildVetVisitRequestBanner(s),
          ] else if (s.pendingHandoverRescuerId != null &&
              s.pendingHandoverRescuerId!.isNotEmpty) ...[
            _buildHandoverRequestBanner(s),
          ] else if (s.pendingOutcomeAction != null &&
              s.pendingOutcomeAction!.isNotEmpty) ...[
            _buildOutcomeRequestBanner(s),
          ] else if (s.pendingAdoptionApplicantId != null &&
              s.pendingAdoptionApplicantId!.isNotEmpty) ...[
            _buildPendingAdoptionBanner(s),
          ] else if (s.isAwaitingPostVetDecision) ...[
            _buildPostVetDecisionBanner(s),
          ],
        ],
      ),
    );
  }

  Widget _buildPostVetDecisionBanner(Sighting s) {
    final isVetRescuer = _isVetRescuer(s);

    if (isVetRescuer) {
      if (s.isFeral) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF00897B).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xFF00897B).withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00897B).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.nature_people_rounded,
                        color: Color(0xFF00897B), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🌿 Feral Cat TNR Mandate • Custody with You',
                          style: GoogleFonts.nunito(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF00695C),
                          ),
                        ),
                        Text(
                          _isOwner(s)
                              ? 'You reported and provided veterinary care for this feral cat. Per humane TNR protocol, domestic adoption is restricted. Please safely return the cat to its original colony territory and submit photo proof.'
                              : 'This cat is an unsocialized feral adult. Foster and shelter adoptions are restricted under TNR protocol. Safe return to original colony is the mandated outcome. Coordinate with the reporter to finalize the release spot.',
                          style: GoogleFonts.nunito(
                            fontSize: 11,
                            color: _navy.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  InkWell(
                    onTap: () => _confirmReturnToSpot(s),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00897B),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.nature_people_rounded,
                              size: 14, color: Colors.white),
                          const SizedBox(width: 5),
                          Text(
                            '🌿 Return to Spot / Colony (+100 XP)',
                            style: GoogleFonts.nunito(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (s.reporterId.isNotEmpty && s.reporterId != _uid)
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CoordinationChatScreen(
                              sighting: s,
                              otherUserId: s.reporterId,
                              otherUserName: s.reporterName.isNotEmpty
                                  ? s.reporterName
                                  : 'Reporter',
                              otherUserRole: 'Reporter',
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E88E5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.chat_bubble_rounded,
                                size: 13, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              '💬 Chat with Reporter to Coordinate Spot',
                              style: GoogleFonts.nunito(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      }

      final isDelegatedOrOwner =
          _isOwner(s) || s.isRescuerCustodyDelegated;

      if (!isDelegatedOrOwner) {
        final timeRemaining = s.postVetDecisionTimeRemaining;
        final timeRemainingText = timeRemaining != null &&
                timeRemaining > Duration.zero
            ? (timeRemaining.inHours > 0
                ? '${timeRemaining.inHours}h ${timeRemaining.inMinutes % 60}m left'
                : '${timeRemaining.inMinutes}m left')
            : '24h window expired';

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF673AB7).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xFF673AB7).withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF673AB7)
                          .withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.hourglass_top_rounded,
                        color: Color(0xFF673AB7), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '⏳ Awaiting Reporter Decision',
                                style: GoogleFonts.nunito(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF673AB7),
                                ),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF673AB7)
                                    .withValues(alpha: 0.12),
                                borderRadius:
                                    BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.timer_outlined,
                                      size: 11,
                                      color: Color(0xFF673AB7)),
                                  const SizedBox(width: 3),
                                  Text(
                                    timeRemainingText,
                                    style: GoogleFonts.nunito(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color:
                                          const Color(0xFF673AB7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${s.reporterName.isNotEmpty ? s.reporterName : "The reporter"} has 24h to decide next steps ($timeRemainingText). If inactive, placement authority automatically transfers to you.',
                          style: GoogleFonts.nunito(
                            fontSize: 11,
                            color: _navy.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (s.reporterId.isNotEmpty && s.reporterId != _uid)
                    InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CoordinationChatScreen(
                              sighting: s,
                              otherUserId: s.reporterId,
                              otherUserName: s.reporterName,
                              otherUserRole: 'Reporter',
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: const Color(0xFF673AB7)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.chat_bubble_rounded,
                                size: 13, color: Color(0xFF673AB7)),
                            const SizedBox(width: 6),
                            Text(
                              '💬 Chat with ${s.reporterName.isNotEmpty ? s.reporterName : "Reporter"}',
                              style: GoogleFonts.nunito(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF673AB7),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (s.isPostVetDecisionWindowExpired)
                    InkWell(
                      onTap: () async {
                        try {
                          await FirebaseService.instance
                              .delegatePostVetCustodyToRescuer(s.id);
                          if (mounted) {
                            _snack(
                                '⚡ Custody claimed due to reporter inactivity! You now have full placement authority. 🐾');
                          }
                        } catch (e) {
                          if (mounted) {
                            _snack('Failed to claim custody: $e');
                          }
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE65100),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bolt_rounded,
                                size: 14, color: Colors.white),
                            const SizedBox(width: 4),
                            Text(
                              '⚡ Claim Custody (Inactive)',
                              style: GoogleFonts.nunito(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      }

      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _lavLight.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _lavender.withValues(alpha: 0.25),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: _lavender.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isOwner(s)
                  ? 'Your Vet Visit Was Verified! (+100 XP)'
                  : 'Placement Delegated to You (+100 XP)',
              style: GoogleFonts.nunito(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: _navy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _isOwner(s)
                  ? 'Since you have physical custody of the cat, select your next action:'
                  : '${s.reporterName.isNotEmpty ? s.reporterName : "The reporter"} placed you in charge of placement. Select your next action:',
              style: GoogleFonts.nunito(
                fontSize: 12,
                color: _navy.withValues(alpha: 0.65),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPostVetActionBox(
                  title: 'Foster',
                  asset: 'assets/images/needshome.png',
                  sub: '+150 XP',
                  color: const Color(0xFF673AB7),
                  onTap: () => _showActionProofSheet('tookIn', s),
                ),
                const SizedBox(width: 10),
                _buildPostVetActionBox(
                  title: 'Shelter',
                  asset: 'assets/images/shelter.png',
                  sub: '+120 XP',
                  color: const Color(0xFFE65100),
                  onTap: () => _showActionProofSheet('sheltered', s),
                ),
                const SizedBox(width: 10),
                _buildPostVetActionBox(
                  title: 'Open for Adoption',
                  asset: 'assets/images/review.png',
                  sub: '+100 XP',
                  color: const Color(0xFF2E7D32),
                  onTap: () => _showOpenForAdoptionSheet(s),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      final rescuerName = s.lastVetRescuerName?.isNotEmpty == true
          ? s.lastVetRescuerName!
          : 'The rescuer';
      final rescuerId = s.lastVetRescuerId ?? s.pendingVetRescuerId ?? '';

      if (s.isFeral) {
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF00897B).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: const Color(0xFF00897B).withValues(alpha: 0.25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00897B).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.nature_people_rounded,
                        color: Color(0xFF00897B), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '🌿 Feral Cat • Awaiting TNR Colony Return',
                          style: GoogleFonts.nunito(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF00695C),
                          ),
                        ),
                        Text(
                          '$rescuerName has custody of this feral cat after vet care. Per TNR protocol, the cat will be safely released to its territory. You can coordinate with $rescuerName via chat.',
                          style: GoogleFonts.nunito(
                            fontSize: 11,
                            color: _navy.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (rescuerId.isNotEmpty && rescuerId != _uid) ...[
                const SizedBox(height: 10),
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CoordinationChatScreen(
                          sighting: s,
                          otherUserId: rescuerId,
                          otherUserName: rescuerName,
                          otherUserRole: 'Vet Rescuer',
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E88E5),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.chat_bubble_rounded,
                            size: 13, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          '💬 Chat with $rescuerName to Coordinate Spot',
                          style: GoogleFonts.nunito(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      }

      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF673AB7).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFF673AB7).withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF673AB7).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.hourglass_top_rounded,
                      color: Color(0xFF673AB7), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.isRescuerCustodyDelegated
                                  ? (s.isPostVetDecisionWindowExpired &&
                                          s.postVetCustody !=
                                              'rescuerInCharge'
                                      ? '⏳ Decision Window Expired'
                                      : '⏳ Vet Visit Verified • Rescuer in Charge')
                                  : '⏳ Awaiting Decision',
                              style: GoogleFonts.nunito(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF673AB7),
                              ),
                            ),
                          ),
                          if (!s.isRescuerCustodyDelegated) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF673AB7)
                                    .withValues(alpha: 0.12),
                                borderRadius:
                                    BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.timer_outlined,
                                      size: 11,
                                      color: Color(0xFF673AB7)),
                                  const SizedBox(width: 3),
                                  Text(
                                    s.postVetDecisionTimeRemaining !=
                                                null &&
                                            s.postVetDecisionTimeRemaining! >
                                                Duration.zero
                                        ? (s.postVetDecisionTimeRemaining!
                                                    .inHours >
                                                0
                                            ? '${s.postVetDecisionTimeRemaining!.inHours}h left'
                                            : '${s.postVetDecisionTimeRemaining!.inMinutes}m left')
                                        : 'Expiring',
                                    style: GoogleFonts.nunito(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF673AB7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.isRescuerCustodyDelegated
                            ? (s.isPostVetDecisionWindowExpired &&
                                    s.postVetCustody !=
                                        'rescuerInCharge'
                                ? 'The 24-hour decision window has passed. Placement authority was automatically transferred to $rescuerName so care is not delayed.'
                                : 'You delegated custody authority to $rescuerName to decide and log placement (foster, shelter, or adoption). Coordinate via chat.')
                            : '$rescuerName completed veterinary care. Please decide within 24 hours between foster care, shelter, or delegating placement to $rescuerName. If no decision is made, authority automatically transfers to $rescuerName.',
                        style: GoogleFonts.nunito(
                          fontSize: 11,
                          color: _navy.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (rescuerId.isNotEmpty && rescuerId != _uid)
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CoordinationChatScreen(
                            sighting: s,
                            otherUserId: rescuerId,
                            otherUserName: rescuerName,
                            otherUserRole: 'Vet Rescuer',
                          ),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: const Color(0xFF673AB7)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.chat_bubble_rounded,
                              size: 13, color: Color(0xFF673AB7)),
                          const SizedBox(width: 6),
                          Text(
                            'Chat with $rescuerName',
                            style: GoogleFonts.nunito(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF673AB7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_isOwner(s) && !s.isRescuerCustodyDelegated)
                  InkWell(
                    onTap: () => _showPostVetFollowUpDialog(s),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: const Color(0xFF673AB7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.checklist_rounded,
                              size: 14, color: Colors.white),
                          const SizedBox(width: 6),
                          Text(
                            'Decide Next Step',
                            style: GoogleFonts.nunito(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }
  }

  Widget _buildPostVetActionBox({
    required String title,
    required String asset,
    required String sub,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (!DoubleTapGuard.allow('post_vet_action_$title', thresholdMs: 800)) return;
          onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 1. Action Name (Title on top)
            SizedBox(
              height: 32,
              child: Center(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                    height: 1.15,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            // 2. Center box with custom logo
            Container(
              width: double.infinity,
              height: 84,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _navy.withValues(alpha: 0.12),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Image.asset(
                  asset,
                  width: 52,
                  height: 52,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(height: 6),
            // 3. Short desc at bottom
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                sub,
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVetVisitRequestBanner(Sighting s) {
    final isOwner = _isOwner(s);
    final rescuerId = s.pendingVetRescuerId ?? '';
    final rescuerName = s.pendingVetRescuerName ?? 'Rescuer';
    final isMeWhoSubmitted = _uid != null && _uid == rescuerId;
    final canVerify = isOwner && !isMeWhoSubmitted;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF673AB7).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF673AB7).withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF673AB7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.medical_services_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🩺 Vet Visit Verification Pending',
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF673AB7),
                      ),
                    ),
                    Text(
                      '$rescuerName submitted vet checkup proof & clinic notes.',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _navy.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (s.pendingVetClinicName != null &&
              s.pendingVetClinicName!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF673AB7).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.local_hospital_rounded,
                      size: 13, color: Color(0xFF673AB7)),
                  const SizedBox(width: 4),
                  Text(
                    'Clinic: ${s.pendingVetClinicName}',
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF673AB7),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (s.pendingVetNote != null && s.pendingVetNote!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _navy.withValues(alpha: 0.08)),
              ),
              child: Text(
                'Treatment Note: "${s.pendingVetNote}"',
                style: GoogleFonts.nunito(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.italic,
                  color: _navy,
                ),
              ),
            ),
          ],
          if (s.pendingVetProofUrl != null &&
              s.pendingVetProofUrl!.isNotEmpty) ...[
            const SizedBox(height: 8),
            PawImage(
              url: s.pendingVetProofUrl!,
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(12),
              placeholder: const SizedBox.shrink(),
            ),
          ],
          const SizedBox(height: 12),
          if (canVerify)
            Row(
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF673AB7),
                    side: const BorderSide(color: Color(0xFF673AB7)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 10),
                  ),
                  onPressed: () {
                    if (rescuerId.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CoordinationChatScreen(
                            sighting: s,
                            otherUserId: rescuerId,
                            otherUserName: rescuerName,
                            otherUserRole: 'Vet Rescuer',
                          ),
                        ),
                      );
                    } else {
                      _snack('Rescuer contact info unavailable.');
                    }
                  },
                  icon: const Icon(Icons.chat_bubble_rounded, size: 14),
                  label: Text('Chat',
                      style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w800, fontSize: 11.5)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF673AB7),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () async {
                      await FirebaseService.instance
                          .approveVetVisitConfirmation(
                        sightingId: s.id,
                        rescuerId: rescuerId,
                        updateId: s.pendingVetUpdateId,
                      );
                      if (mounted) {
                        _snack('Vet visit verified! Rescuer awarded +100 XP 🎉');
                        _showPostVetFollowUpDialog(s);
                      }
                    },
                    icon: const Icon(Icons.check_circle_rounded, size: 15),
                    label: Text('Confirm (+100 XP)',
                        style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w800, fontSize: 11.5)),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side:
                        BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                    foregroundColor: Colors.red,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 10),
                  ),
                  onPressed: () async {
                    await FirebaseService.instance
                        .declineVetVisitConfirmation(
                      sightingId: s.id,
                      updateId: s.pendingVetUpdateId,
                    );
                    _snack('Vet visit report declined.');
                  },
                  child: Text('Decline',
                      style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w800, fontSize: 11.5)),
                ),
              ],
            )
          else if (isMeWhoSubmitted)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF673AB7).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.hourglass_top_rounded,
                          size: 13, color: Color(0xFF673AB7)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Your vet report was submitted. Awaiting verification from the reporter (${s.reporterName.isNotEmpty ? s.reporterName : "Reporter"}).',
                          style: GoogleFonts.nunito(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF673AB7),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF673AB7),
                      side: const BorderSide(color: Color(0xFF673AB7)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () {
                      final targetId = s.reporterId;
                      final targetName = s.reporterName;
                      if (targetId.isNotEmpty) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CoordinationChatScreen(
                              sighting: s,
                              otherUserId: targetId,
                              otherUserName: targetName,
                              otherUserRole: 'Reporter',
                            ),
                          ),
                        );
                      } else {
                        _snack('Reporter contact info unavailable.');
                      }
                    },
                    icon: const Icon(Icons.chat_bubble_rounded, size: 15),
                    label: Text(
                        'Chat with Reporter (${s.reporterName.isNotEmpty ? s.reporterName : "Reporter"})',
                        style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w800, fontSize: 12.5)),
                  ),
                ),
              ],
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF673AB7).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.hourglass_top_rounded,
                      size: 13, color: Color(0xFF673AB7)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'A vet visit report was submitted by $rescuerName. Awaiting verification from the reporter (${s.reporterName.isNotEmpty ? s.reporterName : "Reporter"}).',
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF673AB7),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOutcomeRequestBanner(Sighting s) {
    final action = s.pendingOutcomeAction ?? '';
    final isRehome = action == 'rehomed';
    final isSheltered = action == 'sheltered';
    final actionLabel = isRehome
        ? 'Permanent Rehoming'
        : (isSheltered ? 'Shelter Transfer' : 'Return to Spot');
    final isOwner = _isOwner(s);
    final canFinalize = isOwner || (_uid != null && _uid == s.careTakerId);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF2E7D32).withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF2E7D32),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                    isRehome
                        ? Icons.celebration
                        : (isSheltered ? Icons.house : Icons.pets),
                    color: Colors.white,
                    size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Outcome Confirmation: $actionLabel',
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF2E7D32),
                      ),
                    ),
                    Text(
                      '${s.careTakerName ?? "Caretaker"} completed the care plan and submitted: $actionLabel',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _navy.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (s.pendingOutcomeNote != null && s.pendingOutcomeNote!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _navy.withValues(alpha: 0.08)),
              ),
              child: Text(
                'Note: "${s.pendingOutcomeNote}"',
                style: GoogleFonts.nunito(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  fontStyle: FontStyle.italic,
                  color: _navy,
                ),
              ),
            ),
          ],
          if (s.pendingOutcomeProofUrl != null && s.pendingOutcomeProofUrl!.isNotEmpty) ...[
            const SizedBox(height: 8),
            PawImage(
              url: s.pendingOutcomeProofUrl!,
              height: 140,
              width: double.infinity,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(12),
              placeholder: const SizedBox.shrink(),
            ),
          ],
          if (canFinalize) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    onPressed: () async {
                      if (!DoubleTapGuard.allow('finalize_outcome_${s.id}')) return;
                      await FirebaseService.instance.completeCareOutcome(
                        sightingId: s.id,
                        outcomeAction: action,
                        note: s.pendingOutcomeNote ?? '',
                      );
                      _snack('Outcome completed and resolved! 🐾🎉');
                    },
                    icon: const Icon(Icons.celebration, size: 16),
                    label: Text(
                        isRehome
                            ? 'Confirm & Finalize Rehomed 🎉'
                            : (isSheltered
                                ? 'Confirm & Finalize Shelter 🏛️'
                                : 'Confirm & Finalize Return 🌿'),
                        style: GoogleFonts.nunito(fontWeight: FontWeight.w800, fontSize: 12.5)),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.red.withValues(alpha: 0.5)),
                    foregroundColor: Colors.red,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                  ),
                  onPressed: () async {
                    if (!DoubleTapGuard.allow('decline_outcome_${s.id}')) return;
                    await FirebaseService.instance.declineOutcomeConfirmation(
                      sightingId: s.id,
                      updateId: s.pendingOutcomeUpdateId,
                    );
                    _snack('Outcome request cancelled.');
                  },
                  child: Text('Cancel',
                      style: GoogleFonts.nunito(fontWeight: FontWeight.w800, fontSize: 12.5)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showOpenForAdoptionSheet(Sighting s) {
    if (s.isFeral) {
      _snack(
          '🌿 Unsocialized feral cats cannot be adopted into indoor homes. TNR Colony Return is the mandated outcome.');
      return;
    }
    File? showcaseFile;
    bool isSubmitting = false;
    bool hasAttemptedSubmit = false;
    String? formValidationError;
    bool isScanningPhoto = false;
    CatValidationResult? scanResult;

    final facilityCtrl = TextEditingController(
      text: s.shelterOrClinicName?.isNotEmpty == true
          ? s.shelterOrClinicName!
          : (s.isSheltered ? 'Animal Shelter' : '${s.careTakerName ?? "Foster"} Home'),
    );
    final contactCtrl = TextEditingController(
      text: s.adoptionContact?.isNotEmpty == true
          ? s.adoptionContact!
          : '',
    );
    final List<String> currentTags = List.from(s.healthTags);
    if (currentTags.isEmpty && (s.hasVetVisit || s.pendingVetRescuerId != null)) {
      currentTags.add('🩺 Vet Checked');
    }

    final noteCtrl = TextEditingController(
      text: s.adoptionNote?.isNotEmpty == true
          ? s.adoptionNote!
          : 'Ready for a loving forever home! Healthy, friendly, and socialized. Contact to adopt! 🏡🐾',
    );

    final availableTags = [
      '🩺 Vet Checked',
      '💉 Vaccinated',
      '✂️ Spayed / Neutered',
      '🪱 Dewormed',
      '🏷️ Microchipped',
      '🩹 Medical Clear',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> pickPhoto(ImageSource source) async {
            try {
              final picked = await _picker.pickImage(
                source: source,
                maxWidth: 1200,
                maxHeight: 1200,
                imageQuality: 85,
              );
              if (picked == null) return;
              final file = File(picked.path);
              setSheetState(() {
                showcaseFile = file;
                isScanningPhoto = true;
                scanResult = null;
              });

              final result = await _aiService.validateCatImage(file);
              setSheetState(() {
                isScanningPhoto = false;
                scanResult = result;
              });
            } catch (e) {
              setSheetState(() => isScanningPhoto = false);
              _snack('Error picking photo: $e');
            }
          }

          final bottomPadding = MediaQuery.paddingOf(ctx).bottom;

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.88,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPadding > 0 ? bottomPadding + 20 : 28),
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
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
                            color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.volunteer_activism_rounded,
                              color: Color(0xFF2E7D32), size: 22),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Open for Adoption! 🏡🐾',
                                style: GoogleFonts.nunito(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: _navy,
                                ),
                              ),
                              Text(
                                'Fill in the Adoption Showcase Profile. Report status will update to Needs Home.',
                                style: GoogleFonts.nunito(
                                  fontSize: 11.5,
                                  color: _navy.withValues(alpha: 0.65),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Foster Home / Shelter / Facility Name',
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: facilityCtrl,
                      onChanged: (_) => setSheetState(() {}),
                      style: GoogleFonts.nunito(fontSize: 13, color: _navy),
                      decoration: InputDecoration(
                        hintText: 'e.g. Miaw Foster Home, Pejaten Animal Shelter',
                        hintStyle: GoogleFonts.nunito(
                          fontSize: 12.5,
                          color: _navy.withValues(alpha: 0.4),
                        ),
                        prefixIcon: const Icon(Icons.home_work_outlined, size: 18, color: Color(0xFF2E7D32)),
                        filled: true,
                        fillColor: _bgWhite,
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && (facilityCtrl.text.trim().isEmpty || TextModerationService.validateFacilityName(facilityCtrl.text, label: 'Foster home name') != null))
                                ? const Color(0xFFE53935)
                                : _navy.withValues(alpha: 0.15),
                            width: (hasAttemptedSubmit && (facilityCtrl.text.trim().isEmpty || TextModerationService.validateFacilityName(facilityCtrl.text, label: 'Foster home name') != null)) ? 1.5 : 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && (facilityCtrl.text.trim().isEmpty || TextModerationService.validateFacilityName(facilityCtrl.text, label: 'Foster home name') != null))
                                ? const Color(0xFFE53935)
                                : _navy.withValues(alpha: 0.15),
                            width: (hasAttemptedSubmit && (facilityCtrl.text.trim().isEmpty || TextModerationService.validateFacilityName(facilityCtrl.text, label: 'Foster home name') != null)) ? 1.5 : 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF2E7D32)),
                        ),
                      ),
                    ),
                    if (hasAttemptedSubmit && facilityCtrl.text.trim().isEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '⚠️ Facility / foster home name is required.',
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE53935),
                        ),
                      ),
                    ] else if (hasAttemptedSubmit && TextModerationService.validateFacilityName(facilityCtrl.text, label: 'Foster home name') != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        TextModerationService.validateFacilityName(facilityCtrl.text, label: 'Foster home name')!,
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE53935),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      'Adoption Contact Phone Number (Phone only)',
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: contactCtrl,
                      onChanged: (_) => setSheetState(() {}),
                      keyboardType: TextInputType.phone,
                      style: GoogleFonts.nunito(fontSize: 13, color: _navy),
                      decoration: InputDecoration(
                        hintText: 'e.g. +62 812-3456-7890',
                        hintStyle: GoogleFonts.nunito(
                          fontSize: 12.5,
                          color: _navy.withValues(alpha: 0.4),
                        ),
                        prefixIcon: const Icon(Icons.phone_outlined, size: 18, color: Color(0xFF2E7D32)),
                        filled: true,
                        fillColor: _bgWhite,
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && (contactCtrl.text.trim().isEmpty || TextModerationService.validatePhoneNumber(contactCtrl.text, label: 'Adoption contact phone number') != null))
                                ? const Color(0xFFE53935)
                                : _navy.withValues(alpha: 0.15),
                            width: (hasAttemptedSubmit && (contactCtrl.text.trim().isEmpty || TextModerationService.validatePhoneNumber(contactCtrl.text, label: 'Adoption contact phone number') != null)) ? 1.5 : 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && (contactCtrl.text.trim().isEmpty || TextModerationService.validatePhoneNumber(contactCtrl.text, label: 'Adoption contact phone number') != null))
                                ? const Color(0xFFE53935)
                                : _navy.withValues(alpha: 0.15),
                            width: (hasAttemptedSubmit && (contactCtrl.text.trim().isEmpty || TextModerationService.validatePhoneNumber(contactCtrl.text, label: 'Adoption contact phone number') != null)) ? 1.5 : 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF2E7D32)),
                        ),
                      ),
                    ),
                    if (hasAttemptedSubmit && contactCtrl.text.trim().isEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '⚠️ Contact phone number is required.',
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE53935),
                        ),
                      ),
                    ] else if (hasAttemptedSubmit && TextModerationService.validatePhoneNumber(contactCtrl.text, label: 'Adoption contact phone number') != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        TextModerationService.validatePhoneNumber(contactCtrl.text, label: 'Adoption contact phone number')!,
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE53935),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      'Verified Health Clearance Badges',
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableTags.map((tag) {
                        final isSelected = currentTags.contains(tag);
                        return GestureDetector(
                          onTap: () {
                            setSheetState(() {
                              if (isSelected) {
                                currentTags.remove(tag);
                              } else {
                                currentTags.add(tag);
                              }
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF2E7D32) : _bgWhite,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF2E7D32)
                                    : _navy.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.check_circle_rounded
                                      : Icons.add_circle_outline_rounded,
                                  size: 14,
                                  color: isSelected ? Colors.white : _navy,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  tag,
                                  style: GoogleFonts.nunito(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: isSelected ? Colors.white : _navy,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Adoption Story & Personality Notes (Required)',
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: noteCtrl,
                      onChanged: (_) => setSheetState(() {}),
                      maxLines: 3,
                      style: GoogleFonts.nunito(fontSize: 13, color: _navy),
                      decoration: InputDecoration(
                        hintText: 'Share personality, habits, temperament, and ideal adopter preferences...',
                        hintStyle: GoogleFonts.nunito(
                          fontSize: 12.5,
                          color: _navy.withValues(alpha: 0.4),
                        ),
                        filled: true,
                        fillColor: _bgWhite,
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && (noteCtrl.text.trim().isEmpty || TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Adoption story') != null))
                                ? const Color(0xFFE53935)
                                : _navy.withValues(alpha: 0.15),
                            width: (hasAttemptedSubmit && (noteCtrl.text.trim().isEmpty || TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Adoption story') != null)) ? 1.5 : 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && (noteCtrl.text.trim().isEmpty || TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Adoption story') != null))
                                ? const Color(0xFFE53935)
                                : _navy.withValues(alpha: 0.15),
                            width: (hasAttemptedSubmit && (noteCtrl.text.trim().isEmpty || TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Adoption story') != null)) ? 1.5 : 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF2E7D32)),
                        ),
                      ),
                    ),
                    if (hasAttemptedSubmit && noteCtrl.text.trim().isEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '⚠️ Adoption story and personality notes are required.',
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE53935),
                        ),
                      ),
                    ] else if (hasAttemptedSubmit && TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Adoption story') != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Adoption story')!,
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE53935),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          'Showcase Photo',
                          style: GoogleFonts.nunito(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '*',
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFFE53935),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '(Mandatory)',
                          style: GoogleFonts.nunito(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFE53935),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (showcaseFile != null) ...[
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(
                              showcaseFile!,
                              height: 130,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: GestureDetector(
                              onTap: () => setSheetState(() {
                                showcaseFile = null;
                                scanResult = null;
                              }),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close, color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (isScanningPhoto)
                        Row(
                          children: [
                            const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFF2E7D32),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'AI verifying cat photo...',
                              style: GoogleFonts.nunito(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF2E7D32),
                              ),
                            ),
                          ],
                        )
                      else if (scanResult != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: scanResult!.isCat
                                ? const Color(0xFF2E7D32).withValues(alpha: 0.1)
                                : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: scanResult!.isCat
                                  ? const Color(0xFF2E7D32).withValues(alpha: 0.3)
                                  : Colors.red.shade300,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                scanResult!.isCat
                                    ? Icons.verified_rounded
                                    : Icons.error_outline_rounded,
                                size: 14,
                                color: scanResult!.isCat
                                    ? const Color(0xFF2E7D32)
                                    : Colors.red.shade700,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  scanResult!.isCat
                                      ? 'Cat Verified (${(scanResult!.confidence * 100).toStringAsFixed(0)}%) 🐾'
                                      : scanResult!.message,
                                  style: GoogleFonts.nunito(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: scanResult!.isCat
                                        ? const Color(0xFF1B5E20)
                                        : Colors.red.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: (hasAttemptedSubmit && showcaseFile == null)
                                      ? const Color(0xFFE53935)
                                      : const Color(0xFF2E7D32).withValues(alpha: 0.5),
                                  width: (hasAttemptedSubmit && showcaseFile == null) ? 1.5 : 1.2,
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () => pickPhoto(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt_outlined, size: 16, color: Color(0xFF2E7D32)),
                              label: Text('Take Photo',
                                  style: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    color: (hasAttemptedSubmit && showcaseFile == null)
                                        ? const Color(0xFFE53935)
                                        : const Color(0xFF2E7D32),
                                  )),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: (hasAttemptedSubmit && showcaseFile == null)
                                      ? const Color(0xFFE53935)
                                      : const Color(0xFF2E7D32).withValues(alpha: 0.5),
                                  width: (hasAttemptedSubmit && showcaseFile == null) ? 1.5 : 1.2,
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              onPressed: () => pickPhoto(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library_outlined, size: 16, color: Color(0xFF2E7D32)),
                              label: Text('From Gallery',
                                  style: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    color: (hasAttemptedSubmit && showcaseFile == null)
                                        ? const Color(0xFFE53935)
                                        : const Color(0xFF2E7D32),
                                  )),
                            ),
                          ),
                        ],
                      ),
                      if (hasAttemptedSubmit && showcaseFile == null) ...[
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded, size: 14, color: Colors.red.shade700),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '⚠️ Showcase cat photo is mandatory for the Adoption Showcase profile.',
                                  style: GoogleFonts.nunito(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.red.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 20),
                    if (formValidationError != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                formValidationError!,
                                style: GoogleFonts.nunito(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.red.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (isSubmitting || !DoubleTapGuard.allow('open_adoption_${s.id}')) return;
                                final facilityErr =
                                    TextModerationService.validateFacilityName(
                                        facilityCtrl.text,
                                        label: 'Foster home name');
                                if (facilityErr != null || facilityCtrl.text.trim().isEmpty) {
                                  setSheetState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = facilityErr ?? 'Facility or foster home name is required.';
                                  });
                                  DoubleTapGuard.reset('open_adoption_${s.id}');
                                  _snack('⚠️ ${formValidationError!}');
                                  return;
                                }
                                final contactErr =
                                    TextModerationService.validatePhoneNumber(
                                        contactCtrl.text,
                                        label: 'Adoption contact phone number');
                                if (contactErr != null || contactCtrl.text.trim().isEmpty) {
                                  setSheetState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = contactErr ?? 'Adoption contact phone number is required.';
                                  });
                                  DoubleTapGuard.reset('open_adoption_${s.id}');
                                  _snack('⚠️ ${formValidationError!}');
                                  return;
                                }
                                final storyErr =
                                    TextModerationService.validateDescription(
                                        noteCtrl.text,
                                        fieldName: 'Adoption story');
                                if (storyErr != null || noteCtrl.text.trim().isEmpty) {
                                  setSheetState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = storyErr ?? 'Adoption story and personality notes are required.';
                                  });
                                  DoubleTapGuard.reset('open_adoption_${s.id}');
                                  _snack('⚠️ ${formValidationError!}');
                                  return;
                                }
                                if (showcaseFile == null) {
                                  setSheetState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = 'Showcase cat photo is mandatory for the Adoption Showcase profile.';
                                  });
                                  DoubleTapGuard.reset('open_adoption_${s.id}');
                                  _snack('⚠️ ${formValidationError!}');
                                  return;
                                }
                                if (isScanningPhoto) {
                                  setSheetState(() {
                                    formValidationError = 'AI is still scanning the cat photo. Please wait a moment.';
                                  });
                                  DoubleTapGuard.reset('open_adoption_${s.id}');
                                  _snack('⏳ AI is verifying the photo, please wait a moment...');
                                  return;
                                }
                                if (scanResult?.isCat != true) {
                                  setSheetState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = scanResult?.message ?? 'Please upload a photo of a real cat.';
                                  });
                                  DoubleTapGuard.reset('open_adoption_${s.id}');
                                  _snack('⚠️ ${formValidationError!}');
                                  return;
                                }
                                setSheetState(() => isSubmitting = true);
                                try {
                                  final earnedXp = await FirebaseService.instance.openCatForAdoption(
                                    sightingId: s.id,
                                    note: noteCtrl.text.trim(),
                                    showcasePhotoFile: showcaseFile!,
                                    healthTags: currentTags,
                                    shelterOrClinicName: facilityCtrl.text.trim(),
                                    adoptionContact: contactCtrl.text.trim(),
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (mounted) {
                                    setState(() {
                                      _hasActed = true;
                                    });
                                    _snack('🏡 Adoption Showcase Profile published! Report updated to Needs Home (+$earnedXp XP)');
                                  }
                                } catch (e) {
                                  DoubleTapGuard.reset('open_adoption_${s.id}');
                                  setSheetState(() => isSubmitting = false);
                                  _snack('Failed to list for adoption: $e');
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : Text(
                                'Publish Adoption Showcase (+100 XP)',
                                style: GoogleFonts.nunito(fontWeight: FontWeight.w900, fontSize: 13.5),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showOutcomeConfirmationRequestSheet(String outcomeAction, Sighting s) {
    if (s.isFeral && outcomeAction != 'returnedToSpot') {
      _snack(
          '🌿 Feral cats cannot be rehomed or sheltered. TNR colony return is the only permitted outcome.');
      return;
    }
    if (outcomeAction == 'returnedToSpot' && !s.canTnrReturn && !s.isFeral) {
      _snack(
          'Kittens and domestic fosters cannot be released to the street. Please choose Foster, Shelter, or Adoption.');
      return;
    }
    File? proofFile;
    File? proofVideoFile;
    bool isSubmitting = false;
    bool isScanningPhoto = false;
    CatValidationResult? scanResult;
    final isRehome = outcomeAction == 'rehomed';
    final isSheltered = outcomeAction == 'sheltered';
    final noteCtrl = TextEditingController(
      text: isRehome
          ? 'Completed foster care and successfully rehomed with loving adopter! 🐾'
          : (isSheltered
              ? 'Completed foster care and transferred safely to registered animal shelter partner. 🏛️'
              : 'Healthy, recovered, and returned to community spot. 🐾'),
    );
    final shelterNameCtrl = TextEditingController(
      text: isSheltered && s.shelterOrClinicName?.isNotEmpty == true
          ? s.shelterOrClinicName!
          : '',
    );
    final shelterAddressCtrl = TextEditingController(
      text: (isSheltered || outcomeAction == 'returnedToSpot')
          ? s.effectiveLocationAddress
          : '',
    );
    double shelterLat = s.effectiveLatitude;
    double shelterLng = s.effectiveLongitude;
    bool isLocatingShelter = false;
    bool isGpsAutoFilledShelter = false;
    bool isSearchingShelter = false;
    final shelterSearchCtrl = TextEditingController();
    final shelterMapCtrl = MapController();
    bool isOnRegisterNewTab = false;
    bool hasAttemptedSubmit = false;
    String? formValidationError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> pickPhoto(ImageSource source) async {
            try {
              final picked = await _picker.pickImage(
                source: source,
                maxWidth: 1200,
                maxHeight: 1200,
                imageQuality: 85,
              );
              if (picked == null) return;
              final file = File(picked.path);
              setSheetState(() {
                proofFile = file;
                isScanningPhoto = true;
                scanResult = null;
              });

              final result = await _aiService.validateCatImage(file);
              setSheetState(() {
                isScanningPhoto = false;
                scanResult = result;
              });
            } catch (e) {
              setSheetState(() => isScanningPhoto = false);
              _snack('Error picking photo: $e');
            }
          }

          Future<void> pickVideo(ImageSource source) async {
            try {
              final picked = await _picker.pickVideo(
                source: source,
                maxDuration: const Duration(minutes: 1),
              );
              if (picked == null) return;
              final file = File(picked.path);
              final bytes = await file.length();
              if (bytes > 25 * 1024 * 1024) {
                _snack(
                    'Video is ${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB. Max allowed size is 25 MB.');
                return;
              }
              setSheetState(() => proofVideoFile = file);
            } catch (e) {
              _snack('Error picking video: $e');
            }
          }

          final bottomPadding = MediaQuery.paddingOf(ctx).bottom;
          final sheetTitle = isRehome
              ? 'Celebrate Rehomed Cat! 🏡🎉'
              : (isSheltered
                  ? 'Confirm Shelter Transfer 🏛️'
                  : 'Confirm Return to Spot (Community Cat) 🌿');
          final sheetSubtitle = isRehome
              ? 'Marks this rescue as resolved and celebrates the forever home with the community!'
              : (isSheltered
                  ? 'Marks this rescue as resolved and safely admitted to a verified shelter partner.'
                  : 'Returns this cat to its territory as a protected Community Cat for ongoing feeding & care.');
          final sheetIcon = isRehome
              ? Icons.celebration
              : (isSheltered ? Icons.house : Icons.pets);
          final primaryCol = isSheltered
              ? const Color(0xFF673AB7)
              : (outcomeAction == 'returnedToSpot'
                  ? const Color(0xFF00897B)
                  : const Color(0xFF2E7D32));
          final isOutcomeNoteValid = !isRehome ||
              TextModerationService.validateDescription(noteCtrl.text,
                      fieldName: 'Outcome note') ==
                  null;
          final shelterAddressError = shelterAddressCtrl.text.isNotEmpty
              ? TextModerationService.validateAddress(
                  shelterAddressCtrl.text,
                  label: outcomeAction == 'returnedToSpot'
                      ? 'Release colony address'
                      : 'Facility address',
                )
              : null;
          final canSubmit = !isSubmitting &&
              proofFile != null &&
              scanResult?.isCat == true &&
              !isScanningPhoto &&
              (!isSheltered || shelterNameCtrl.text.trim().isNotEmpty) &&
              isOutcomeNoteValid;

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(20, 16, 20, bottomPadding > 0 ? bottomPadding + 20 : 28),
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
                            color: primaryCol.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(sheetIcon,
                              color: primaryCol, size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                sheetTitle,
                                style: GoogleFonts.nunito(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: _navy,
                                ),
                              ),
                              Text(
                                sheetSubtitle,
                                style: GoogleFonts.nunito(
                                  fontSize: 12,
                                  color: _navy.withValues(alpha: 0.6),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (outcomeAction == 'returnedToSpot') ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00897B).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: const Color(0xFF00897B)
                                  .withValues(alpha: 0.25)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline,
                                size: 16, color: Color(0xFF00897B)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Feral / Colony Cats Only: This outcome is strictly for unsocialized adult cats returning to their territory with community caretakers.',
                                style: GoogleFonts.nunito(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF00897B),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (isSheltered || outcomeAction == 'returnedToSpot') ...[
                      if (isSheltered) ...[
                        ShelterPickerView(
                          referenceLat: s.effectiveLatitude,
                          referenceLng: s.effectiveLongitude,
                          initialShelterName: shelterNameCtrl.text,
                          initialShelterAddress: shelterAddressCtrl.text,
                          themeColor: const Color(0xFF673AB7),
                          onShelterSelected: (chosenShelter) {
                            setSheetState(() {
                              shelterNameCtrl.text = chosenShelter.name;
                              shelterAddressCtrl.text = chosenShelter.address;
                              shelterLat = chosenShelter.latitude;
                              shelterLng = chosenShelter.longitude;
                              isGpsAutoFilledShelter = false;
                              try {
                                shelterMapCtrl.move(ll.LatLng(shelterLat, shelterLng), 16.0);
                              } catch (_) {}
                            });
                          },
                          onClearSelection: () {
                            setSheetState(() {
                              shelterNameCtrl.clear();
                              shelterAddressCtrl.clear();
                            });
                          },
                          onRegisterTabActiveChanged: (isRegTab) {
                            isOnRegisterNewTab = isRegTab;
                          },
                        ),
                        if (hasAttemptedSubmit && shelterNameCtrl.text.trim().isEmpty) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade300),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, size: 14, color: Color(0xFFE53935)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    isOnRegisterNewTab
                                        ? 'You have an unregistered shelter draft. Please press "Register your suggested Shelter" first, or switch to Nearby Shelters to pick an existing one.'
                                        : 'Please choose a nearby shelter or register a new one.',
                                    style: GoogleFonts.nunito(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFFE53935),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                      ],
                      if (outcomeAction == 'returnedToSpot') ...[
                        Text(
                          'Colony Release Spot / Feeding Station Address *',
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildLocationSearchBar(
                          controller: shelterSearchCtrl,
                          isSearching: isSearchingShelter,
                          themeColor: const Color(0xFF00897B),
                          hintText: 'Search release spot, landmark, or street...',
                          onSearch: (query) async {
                            if (query.trim().isEmpty) return;
                            setSheetState(() => isSearchingShelter = true);
                            final locResult = await LocationService()
                                .searchLocation(query.trim());
                            if (locResult != null) {
                              shelterLat = locResult.latitude;
                              shelterLng = locResult.longitude;
                              shelterAddressCtrl.text = locResult.formattedAddress;
                              isGpsAutoFilledShelter = false;
                              try {
                                shelterMapCtrl.move(
                                    ll.LatLng(shelterLat, shelterLng), 16.0);
                              } catch (_) {}
                            } else {
                              _snack(
                                  'Location not found. Try a different search term.');
                            }
                            setSheetState(() => isSearchingShelter = false);
                          },
                          onClear: () =>
                              setSheetState(() => shelterSearchCtrl.clear()),
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            height: 180,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8EAF0),
                              borderRadius: BorderRadius.circular(14),
                              border:
                                  Border.all(color: _navy.withValues(alpha: 0.1)),
                            ),
                            child: Stack(
                              children: [
                                FlutterMap(
                                  mapController: shelterMapCtrl,
                                  options: MapOptions(
                                    initialCenter:
                                        ll.LatLng(shelterLat, shelterLng),
                                    initialZoom: 16.0,
                                    onTap: (tapPos, point) async {
                                      shelterLat = point.latitude;
                                      shelterLng = point.longitude;
                                      isGpsAutoFilledShelter = false;
                                      setSheetState(
                                          () => isLocatingShelter = true);
                                      final addr = await LocationService()
                                          .getAddressFromCoordinates(
                                              point.latitude, point.longitude);
                                      shelterAddressCtrl.text = addr;
                                      setSheetState(
                                          () => isLocatingShelter = false);
                                    },
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate:
                                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName:
                                          'com.pawwatch.app',
                                    ),
                                    MarkerLayer(
                                      markers: [
                                        Marker(
                                          point:
                                              ll.LatLng(shelterLat, shelterLng),
                                          width: 46,
                                          height: 46,
                                          child: _buildMapPinMarker(
                                            color: const Color(0xFF00897B),
                                            icon: Icons.park_rounded,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Positioned(
                                  right: 10,
                                  top: 10,
                                  child: Column(
                                    children: [
                                      _buildMapButton(
                                        Icons.my_location,
                                        onTap: () async {
                                          setSheetState(
                                              () => isLocatingShelter = true);
                                          final res = await LocationService()
                                              .getCurrentUserLocation();
                                          shelterLat = res.latitude;
                                          shelterLng = res.longitude;
                                          shelterAddressCtrl.text =
                                              res.formattedAddress;
                                          isGpsAutoFilledShelter =
                                              res.isGpsAutoFilled;
                                          setSheetState(
                                              () => isLocatingShelter = false);
                                          try {
                                            shelterMapCtrl.move(
                                                ll.LatLng(
                                                    shelterLat, shelterLng),
                                                16.0);
                                          } catch (_) {}
                                        },
                                      ),
                                      const SizedBox(height: 6),
                                      _buildMapButton(
                                        Icons.add,
                                        onTap: () {
                                          try {
                                            final z =
                                                shelterMapCtrl.camera.zoom + 1;
                                            shelterMapCtrl.move(
                                                ll.LatLng(
                                                    shelterLat, shelterLng),
                                                z);
                                          } catch (_) {}
                                        },
                                      ),
                                      const SizedBox(height: 4),
                                      _buildMapButton(
                                        Icons.remove,
                                        onTap: () {
                                          try {
                                            final z =
                                                shelterMapCtrl.camera.zoom - 1;
                                            shelterMapCtrl.move(
                                                ll.LatLng(
                                                    shelterLat, shelterLng),
                                                z);
                                          } catch (_) {}
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  bottom: 8,
                                  left: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.92),
                                      borderRadius: BorderRadius.circular(8),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.1),
                                          blurRadius: 4,
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.touch_app_outlined,
                                            size: 12,
                                            color: Color(0xFF00897B)),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Tap map to place colony release pin',
                                          style: GoogleFonts.nunito(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: _navy,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildLocationAddressDisplay(
                          addressText: shelterAddressCtrl.text,
                          isLocating: isLocatingShelter,
                          isGpsAutoFilled: isGpsAutoFilledShelter,
                          themeColor: const Color(0xFF00897B),
                          errorText: shelterAddressCtrl.text.isNotEmpty
                              ? shelterAddressError
                              : (hasAttemptedSubmit && shelterAddressCtrl.text.trim().isEmpty
                                  ? '⚠️ Release colony location address is required.'
                                  : null),
                        ),
                        const SizedBox(height: 14),
                      ],
                    ],
                    Text(
                      isRehome
                          ? 'Outcome Note / Details (Required)'
                          : 'Outcome Note / Details',
                      style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _navy),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: noteCtrl,
                      onChanged: (_) => setSheetState(() {}),
                      maxLines: 2,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: _lavLight,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (isRehome && ((hasAttemptedSubmit && noteCtrl.text.trim().isEmpty) || (noteCtrl.text.isNotEmpty && TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Outcome note') != null)))
                                ? const Color(0xFFE53935)
                                : BorderSide.none.color,
                            width: (isRehome && ((hasAttemptedSubmit && noteCtrl.text.trim().isEmpty) || (noteCtrl.text.isNotEmpty && TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Outcome note') != null))) ? 1.5 : 0,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (isRehome && ((hasAttemptedSubmit && noteCtrl.text.trim().isEmpty) || (noteCtrl.text.isNotEmpty && TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Outcome note') != null)))
                                ? const Color(0xFFE53935)
                                : BorderSide.none.color,
                            width: (isRehome && ((hasAttemptedSubmit && noteCtrl.text.trim().isEmpty) || (noteCtrl.text.isNotEmpty && TextModerationService.validateDescription(noteCtrl.text, fieldName: 'Outcome note') != null))) ? 1.5 : 0,
                          ),
                        ),
                      ),
                    ),
                    if (isRehome && hasAttemptedSubmit && noteCtrl.text.trim().isEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '⚠️ Outcome note / adoption story is required to confirm adoption.',
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE53935),
                        ),
                      ),
                    ] else if (isRehome &&
                        noteCtrl.text.isNotEmpty &&
                        TextModerationService.validateDescription(noteCtrl.text,
                                fieldName: 'Outcome note') !=
                            null) ...[
                      const SizedBox(height: 4),
                      Text(
                        TextModerationService.validateDescription(
                            noteCtrl.text,
                            fieldName: 'Outcome note')!,
                        style: GoogleFonts.nunito(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFE53935),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      'Outcome Photo Proof (Required - AI Checked)',
                      style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w800, color: _navy),
                    ),
                    const SizedBox(height: 8),
                    if (proofFile != null) ...[
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(proofFile!, width: 120, height: 120, fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: 4,
                            right: 4,
                            child: GestureDetector(
                              onTap: () => setSheetState(() {
                                proofFile = null;
                                scanResult = null;
                              }),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                child: const Icon(Icons.close, size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (isScanningPhoto)
                        Row(
                          children: [
                            SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: primaryCol,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'AI verifying cat photo...',
                              style: GoogleFonts.nunito(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: primaryCol,
                              ),
                            ),
                          ],
                        )
                      else if (scanResult != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: scanResult!.isCat
                                ? const Color(0xFF2E7D32).withValues(alpha: 0.1)
                                : Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: scanResult!.isCat
                                  ? const Color(0xFF2E7D32).withValues(alpha: 0.3)
                                  : Colors.red.shade300,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                scanResult!.isCat
                                    ? Icons.verified_rounded
                                    : Icons.error_outline_rounded,
                                size: 14,
                                color: scanResult!.isCat
                                    ? const Color(0xFF2E7D32)
                                    : Colors.red.shade700,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  scanResult!.isCat
                                      ? 'Cat Verified (${(scanResult!.confidence * 100).toStringAsFixed(0)}%) 🐾'
                                      : scanResult!.message,
                                  style: GoogleFonts.nunito(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: scanResult!.isCat
                                        ? const Color(0xFF1B5E20)
                                        : Colors.red.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => pickPhoto(ImageSource.camera),
                              icon: Icon(Icons.camera_alt, size: 16, color: primaryCol),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: (hasAttemptedSubmit && proofFile == null)
                                      ? const Color(0xFFE53935)
                                      : _navy.withValues(alpha: 0.2),
                                  width: (hasAttemptedSubmit && proofFile == null) ? 1.6 : 1.0,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              label: Text('Camera', style: GoogleFonts.nunito(fontWeight: FontWeight.w800, color: _navy, fontSize: 12)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => pickPhoto(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library, size: 16, color: _lavender),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: (hasAttemptedSubmit && proofFile == null)
                                      ? const Color(0xFFE53935)
                                      : _navy.withValues(alpha: 0.2),
                                  width: (hasAttemptedSubmit && proofFile == null) ? 1.6 : 1.0,
                                ),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              label: Text('Gallery', style: GoogleFonts.nunito(fontWeight: FontWeight.w800, color: _navy, fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                      if (hasAttemptedSubmit && proofFile == null) ...[
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.red.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline_rounded, size: 14, color: Colors.red.shade700),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  isSheltered
                                      ? '⚠️ Cat photo proof is required to confirm shelter admission.'
                                      : (isRehome
                                          ? '⚠️ Celebration photo with the cat is required to confirm adoption.'
                                          : '⚠️ Cat photo proof at the release spot is required.'),
                                  style: GoogleFonts.nunito(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.red.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 16),

                    // Optional Video Section
                    Row(
                      children: [
                        Text(
                          'Celebration / Release Video Clip',
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: primaryCol.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Optional',
                            style: GoogleFonts.nunito(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: primaryCol,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Share an optional short video (up to 1 min) celebrating the cat\'s forever home or colony release.',
                      style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        color: _navy.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (proofVideoFile != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ReelVideoPlayer(
                            videoFile: proofVideoFile,
                            maxHeight: 280,
                            autoPlay: true,
                            isLooping: true,
                            onRemove: () =>
                                setSheetState(() => proofVideoFile = null),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  size: 14, color: Color(0xFF2E7D32)),
                              const SizedBox(width: 4),
                              Text(
                                'Reel attached • Tap ✕ to remove',
                                style: GoogleFonts.nunito(
                                  fontSize: 11,
                                  color: const Color(0xFF2E7D32),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => pickVideo(ImageSource.camera),
                              icon: Icon(Icons.videocam_outlined, size: 16, color: primaryCol),
                              label: Text('Record Video',
                                  style: GoogleFonts.nunito(
                                      fontWeight: FontWeight.w800,
                                      color: _navy,
                                      fontSize: 12)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => pickVideo(ImageSource.gallery),
                              icon: const Icon(Icons.video_library_outlined, size: 16, color: _lavender),
                              label: Text('Pick Video',
                                  style: GoogleFonts.nunito(
                                      fontWeight: FontWeight.w800,
                                      color: _navy,
                                      fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 18),
                    if (formValidationError != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                formValidationError!,
                                style: GoogleFonts.nunito(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.red.shade900,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: canSubmit
                              ? primaryCol
                              : primaryCol.withValues(alpha: 0.7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          elevation: canSubmit ? 2 : 0,
                        ),
                        onPressed: isSubmitting
                            ? null
                            : () async {
                                if (isSubmitting) return;
                                if (proofFile == null) {
                                  setSheetState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = isSheltered
                                        ? 'Cat photo proof is required to confirm shelter transfer.'
                                        : (isRehome
                                            ? 'Celebration photo of the cat with adopter is required.'
                                            : 'Photo proof of the cat at the release spot is required.');
                                  });
                                  _snack('⚠️ ${formValidationError!}');
                                  return;
                                }
                                if (isScanningPhoto) {
                                  setSheetState(() {
                                    formValidationError = 'AI is verifying the photo, please wait a moment...';
                                  });
                                  _snack('⏳ AI is verifying the photo, please wait a moment...');
                                  return;
                                }
                                if (scanResult?.isCat != true) {
                                  setSheetState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = scanResult?.message ??
                                        'Photo verification failed: image was not recognized as a cat.';
                                  });
                                  _snack('⚠️ ${formValidationError!}');
                                  return;
                                }
                                if (isSheltered) {
                                  final sErr =
                                      TextModerationService.validateFacilityName(
                                          shelterNameCtrl.text,
                                          label: 'Shelter name');
                                  if (sErr != null || shelterNameCtrl.text.trim().isEmpty) {
                                    final msg = isOnRegisterNewTab
                                        ? 'You have an unregistered shelter draft. Please press "Register your suggested Shelter" first, or pick from Nearby Shelters.'
                                        : (sErr ?? 'Please select a shelter or register a new one first.');
                                    setSheetState(() {
                                      hasAttemptedSubmit = true;
                                      formValidationError = msg;
                                    });
                                    _snack('⚠️ $msg');
                                    return;
                                  }
                                }
                                if (isSheltered || outcomeAction == 'returnedToSpot') {
                                  final addrErr = TextModerationService.validateAddress(
                                    shelterAddressCtrl.text,
                                    label: outcomeAction == 'returnedToSpot'
                                        ? 'Release colony address'
                                        : 'Facility address',
                                  );
                                  if (addrErr != null || shelterAddressCtrl.text.trim().isEmpty) {
                                    setSheetState(() {
                                      hasAttemptedSubmit = true;
                                      formValidationError = addrErr ??
                                          (outcomeAction == 'returnedToSpot'
                                              ? 'Release colony location address is required.'
                                              : 'Facility location address is required.');
                                    });
                                    _snack('⚠️ ${formValidationError!}');
                                    return;
                                  }
                                }
                                if (isRehome) {
                                  final nErr =
                                      TextModerationService.validateDescription(
                                          noteCtrl.text,
                                          fieldName: 'Outcome note');
                                  if (nErr != null || noteCtrl.text.trim().isEmpty) {
                                    setSheetState(() {
                                      hasAttemptedSubmit = true;
                                      formValidationError = nErr ?? 'Outcome note is required for rehomed cat.';
                                    });
                                    _snack('⚠️ ${formValidationError!}');
                                    return;
                                  }
                                } else if (noteCtrl.text.trim().isNotEmpty) {
                                  final nErr =
                                      TextModerationService.validateDescription(
                                          noteCtrl.text,
                                          fieldName: 'Outcome note');
                                  if (nErr != null) {
                                    setSheetState(() {
                                      hasAttemptedSubmit = true;
                                      formValidationError = nErr;
                                    });
                                    _snack('⚠️ $nErr');
                                    return;
                                  }
                                }

                                if (!DoubleTapGuard.allow('outcome_proof_${s.id}')) return;
                                setSheetState(() {
                                  formValidationError = null;
                                  isSubmitting = true;
                                });
                                setSheetState(() => isSubmitting = true);
                                try {
                                  String finalNote = noteCtrl.text.trim();
                                  if (isSheltered && shelterNameCtrl.text.trim().isNotEmpty) {
                                    final sAddr = shelterAddressCtrl.text.trim();
                                    finalNote =
                                        'Admitted to ${shelterNameCtrl.text.trim()}${sAddr.isNotEmpty ? " ($sAddr)" : ""}. $finalNote'
                                            .trim();
                                  }

                                  final earnedXp = await FirebaseService.instance
                                      .completeCareOutcome(
                                    sightingId: s.id,
                                    outcomeAction: outcomeAction,
                                    note: finalNote.isNotEmpty
                                        ? finalNote
                                        : (isRehome
                                            ? 'Rehomed with a loving family!'
                                            : (isSheltered ? 'Admitted to shelter' : 'Returned safely to spot')),
                                    proofPhotoFile: proofFile,
                                    proofVideoFile: proofVideoFile,
                                    updatedLatitude: (isSheltered || outcomeAction == 'returnedToSpot')
                                        ? shelterLat
                                        : null,
                                    updatedLongitude: (isSheltered || outcomeAction == 'returnedToSpot')
                                        ? shelterLng
                                        : null,
                                    updatedLocationAddress: (isSheltered || outcomeAction == 'returnedToSpot') &&
                                            shelterAddressCtrl.text.trim().isNotEmpty
                                        ? shelterAddressCtrl.text.trim()
                                        : null,
                                    shelterOrClinicName: isSheltered && shelterNameCtrl.text.trim().isNotEmpty
                                        ? shelterNameCtrl.text.trim()
                                        : null,
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (mounted) {
                                    setState(() {
                                      _hasActed = true;
                                    });
                                    _snack(isRehome
                                        ? '🎉 Cat successfully marked as permanently rehomed! +$earnedXp XP'
                                        : (isSheltered
                                            ? '🏛️ Cat successfully transferred to shelter! +$earnedXp XP'
                                            : '🌿 Cat returned to spot as a protected Community Cat! +$earnedXp XP'));
                                  }
                                } catch (e) {
                                  DoubleTapGuard.reset('outcome_proof_${s.id}');
                                  setSheetState(() => isSubmitting = false);
                                  _snack('Failed to complete outcome: $e');
                                }
                              },
                        child: isSubmitting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : Text(
                                proofFile == null
                                    ? 'Photo Proof Required'
                                    : (isSheltered && shelterNameCtrl.text.trim().isEmpty
                                        ? 'Shelter Name Required'
                                        : (isRehome
                                            ? 'Confirm & Mark Rehomed (+200 XP)'
                                            : (isSheltered
                                                ? 'Confirm & Mark Sheltered (+120 XP)'
                                                : 'Return as Community Cat (+100 XP)'))),
                                style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w800),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLocation(Sighting s) {
    final isResolved = s.urgency == 'resolved';
    final isSheltered = s.isSheltered;
    final isTnrReturn =
        s.resolvedByAction == 'returnedToSpot' || s.isTnrReturned;
    final isPrivateResolved = isResolved && !isSheltered && !isTnrReturn;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
              isPrivateResolved
                  ? Icons.shield_outlined
                  : (isSheltered
                      ? Icons.apartment
                      : (isTnrReturn
                          ? Icons.park_rounded
                          : Icons.location_on_outlined)),
              color: isTnrReturn
                  ? const Color(0xFF00897B)
                  : (isResolved ? _resolved : _lavender),
              size: 18)),
      const SizedBox(width: 8),
      Expanded(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.effectiveDisplayLocation,
              style: GoogleFonts.nunito(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _navy.withValues(alpha: 0.7),
                  height: 1.4)),
          if (isPrivateResolved)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '🔒 Adopter Home Privacy Protected',
                style: GoogleFonts.nunito(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _resolved,
                ),
              ),
            )
          else if (isSheltered)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '🏢 Shelter Facility • Open for Adoption Visits',
                style: GoogleFonts.nunito(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _resolved,
                ),
              ),
            )
          else if (isTnrReturn)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      size: 13, color: Color(0xFF00897B)),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      '🌿 TNR Colony Release Spot • Community Monitored',
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF00897B),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
        ],
      )),
      const SizedBox(width: 8),
      if (!isPrivateResolved)
        GestureDetector(
          onTap: () => _openMaps(s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: isTnrReturn
                  ? const Color(0xFF00897B).withValues(alpha: 0.1)
                  : _lavLight,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: isTnrReturn
                      ? const Color(0xFF00897B).withValues(alpha: 0.4)
                      : _lavender.withValues(alpha: 0.35)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.near_me_outlined,
                  size: 13,
                  color: isTnrReturn ? const Color(0xFF00897B) : _lavender),
              const SizedBox(width: 4),
              Text('Open in Maps',
                  style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isTnrReturn ? const Color(0xFF00897B) : _lavender)),
            ]),
          ),
        ),
    ]);
  }

  Widget _buildStats(Sighting s) {
    final dt = s.createdAt;
    const mon = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final dateStr = '${dt.day} ${mon[dt.month - 1]} ${dt.year}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: _navy.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem(Icons.calendar_today_outlined, 'REPORTED', dateStr),
          Container(
              height: 28, width: 1, color: _navy.withValues(alpha: 0.08)),
          _statItem(Icons.chat_bubble_outline, 'COMMUNITY',
              '${s.commentCount} posts'),
          Container(
              height: 28, width: 1, color: _navy.withValues(alpha: 0.08)),
          _statItem(
              Icons.tag, 'CATEGORY', s.category),
        ],
      ),
    );
  }

  Widget _statItem(IconData icon, String lbl, String val) => Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Column(children: [
            Icon(icon, size: 16, color: _lavender),
            const SizedBox(height: 4),
            Text(lbl,
                style: GoogleFonts.nunito(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _navy.withValues(alpha: 0.5))),
            const SizedBox(height: 3),
            Text(val,
                textAlign: TextAlign.center,
                style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                    height: 1.3)),
          ]),
        ),
      );

  void _showEditHealthTagsSheet(Sighting s) {
    final facilityCtrl =
        TextEditingController(text: s.shelterOrClinicName ?? '');
    final contactCtrl = TextEditingController(text: s.adoptionContact ?? '');
    final List<String> currentTags = List.from(s.healthTags);
    bool isSaving = false;

    final availableTags = [
      '🩺 Vet Checked',
      '💉 Vaccinated',
      '✂️ Spayed / Neutered',
      '🪱 Dewormed',
      '🏷️ Microchipped',
      '🩹 Medical Clear',
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final bottomPadding = MediaQuery.paddingOf(ctx).bottom;
          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, bottomPadding > 0 ? bottomPadding + 20 : 28),
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
                            color:
                                const Color(0xFF673AB7).withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.volunteer_activism_rounded,
                              color: Color(0xFF673AB7), size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Edit Adoption Profile',
                                style: GoogleFonts.nunito(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  color: _navy,
                                ),
                              ),
                              Text(
                                'Manage verified health badges and shelter info.',
                                style: GoogleFonts.nunito(
                                  fontSize: 12,
                                  color: _navy.withValues(alpha: 0.6),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Shelter / Clinic / Caretaker Facility Name',
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: facilityCtrl,
                      style: GoogleFonts.nunito(fontSize: 13, color: _navy),
                      decoration: InputDecoration(
                        hintText: 'e.g. Pejaten Animal Shelter, Medivet Clinic',
                        filled: true,
                        fillColor: _lavLight,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Adoption Contact Info (WhatsApp / Phone / IG)',
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: contactCtrl,
                      style: GoogleFonts.nunito(fontSize: 13, color: _navy),
                      decoration: InputDecoration(
                        hintText: 'e.g. WhatsApp: +62 812-3456-7890 or @instagram',
                        filled: true,
                        fillColor: _lavLight,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Verified Health Clearance Badges',
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableTags.map((tag) {
                        final isSelected = currentTags.contains(tag);
                        return GestureDetector(
                          onTap: () {
                            setSheetState(() {
                              if (isSelected) {
                                currentTags.remove(tag);
                              } else {
                                currentTags.add(tag);
                              }
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF2E7D32)
                                  : _lavLight,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF2E7D32)
                                    : _navy.withValues(alpha: 0.15),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.check_circle_rounded
                                      : Icons.add_circle_outline_rounded,
                                  size: 14,
                                  color: isSelected ? Colors.white : _navy,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  tag,
                                  style: GoogleFonts.nunito(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: isSelected ? Colors.white : _navy,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF673AB7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: isSaving
                            ? null
                            : () async {
                                setSheetState(() => isSaving = true);
                                try {
                                  await FirebaseService.instance
                                      .updateAdoptionShowcaseProfile(
                                    sightingId: s.id,
                                    healthTags: currentTags,
                                    shelterOrClinicName:
                                        facilityCtrl.text.trim(),
                                    adoptionContact:
                                        contactCtrl.text.trim(),
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  if (mounted) {
                                    _snack('Adoption Showcase profile updated! 🐾');
                                  }
                                } catch (e) {
                                  setSheetState(() => isSaving = false);
                                  _snack('Failed to update: $e');
                                }
                              },
                        child: isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : Text('Save Profile Badges',
                                style: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w800)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openAdopterChat(Sighting s) {
    final otherId = s.careTakerId?.isNotEmpty == true
        ? s.careTakerId!
        : s.reporterId;
    final otherName = s.careTakerName?.isNotEmpty == true
        ? s.careTakerName!
        : s.reporterName;

    if (otherId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CoordinationChatScreen(
            sighting: s,
            otherUserId: otherId,
            otherUserName: otherName,
            otherUserRole:
                s.isSheltered ? 'Shelter Coordinator' : 'Foster Caregiver',
          ),
        ),
      );
    } else {
      _snack('Caregiver contact info unavailable.');
    }
  }

  void _showSubmitAdoptionApplicationSheet(Sighting s) {
    final facilityName = s.shelterOrClinicName?.isNotEmpty == true
        ? s.shelterOrClinicName!
        : (s.isSheltered ? 'Animal Shelter' : 'Foster Caregiver');
    final otherName = s.careTakerName?.isNotEmpty == true
        ? s.careTakerName!
        : s.reporterName;

    final noteCtrl = TextEditingController();
    final contactCtrl = TextEditingController();
    bool isSubmitting = false;
    bool hasAttemptedSubmit = false;
    String? formValidationError;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final keyboardInset = MediaQuery.viewInsetsOf(ctx).bottom;
          final systemBottomNav = MediaQuery.paddingOf(ctx).bottom;
          final effectiveBottomPadding = keyboardInset > 0
              ? keyboardInset + 16
              : (systemBottomNav > 0 ? systemBottomNav + 24 : 36.0);

          final noteErr = TextModerationService.validateDescription(
            noteCtrl.text,
            fieldName: 'Adoption intro/note',
          );
          final phoneErr = TextModerationService.validatePhoneNumber(
            contactCtrl.text,
            label: 'Adoption contact phone number',
          );

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, effectiveBottomPadding),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
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
                          color:
                              const Color(0xFF2E7D32).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.volunteer_activism_rounded,
                            color: Color(0xFF2E7D32), size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Adoption Application',
                              style: GoogleFonts.nunito(
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                color: _navy,
                              ),
                            ),
                            Text(
                              'Request to adopt ${s.title.isNotEmpty ? s.title : "this cat"} from $otherName ($facilityName)',
                              style: GoogleFonts.nunito(
                                fontSize: 12,
                                color: _navy.withValues(alpha: 0.6),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Why do you want to adopt? (Household, setup, experience)',
                    style: GoogleFonts.nunito(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: noteCtrl,
                    onChanged: (_) => setSheetState(() {}),
                    maxLines: 3,
                    style: GoogleFonts.nunito(fontSize: 13, color: _navy),
                    decoration: InputDecoration(
                      hintText:
                          'Share a brief intro about your home, pets, and commitment to adopt...',
                      hintStyle: GoogleFonts.nunito(
                        fontSize: 12.5,
                        color: _navy.withValues(alpha: 0.4),
                      ),
                      filled: true,
                      fillColor: _bgWhite,
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: (hasAttemptedSubmit && noteErr != null)
                              ? const Color(0xFFE53935)
                              : _navy.withValues(alpha: 0.15),
                          width: (hasAttemptedSubmit && noteErr != null) ? 1.5 : 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: (hasAttemptedSubmit && noteErr != null)
                              ? const Color(0xFFE53935)
                              : _navy.withValues(alpha: 0.15),
                          width: (hasAttemptedSubmit && noteErr != null) ? 1.5 : 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: (hasAttemptedSubmit && noteErr != null)
                              ? const Color(0xFFE53935)
                              : const Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ),
                  if (hasAttemptedSubmit && noteErr != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '⚠️ $noteErr',
                      style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFE53935),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    'Your Phone / WhatsApp Number',
                    style: GoogleFonts.nunito(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: contactCtrl,
                    onChanged: (_) => setSheetState(() {}),
                    keyboardType: TextInputType.phone,
                    style: GoogleFonts.nunito(fontSize: 13, color: _navy),
                    decoration: InputDecoration(
                      hintText: 'e.g. +62 812-3456-7890',
                      hintStyle: GoogleFonts.nunito(
                        fontSize: 12.5,
                        color: _navy.withValues(alpha: 0.4),
                      ),
                      prefixIcon: const Icon(Icons.phone_outlined,
                          size: 18, color: Color(0xFF2E7D32)),
                      filled: true,
                      fillColor: _bgWhite,
                      contentPadding: const EdgeInsets.all(12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: (hasAttemptedSubmit && phoneErr != null)
                              ? const Color(0xFFE53935)
                              : _navy.withValues(alpha: 0.15),
                          width: (hasAttemptedSubmit && phoneErr != null) ? 1.5 : 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: (hasAttemptedSubmit && phoneErr != null)
                              ? const Color(0xFFE53935)
                              : _navy.withValues(alpha: 0.15),
                          width: (hasAttemptedSubmit && phoneErr != null) ? 1.5 : 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: (hasAttemptedSubmit && phoneErr != null)
                              ? const Color(0xFFE53935)
                              : const Color(0xFF2E7D32),
                        ),
                      ),
                    ),
                  ),
                  if (hasAttemptedSubmit && phoneErr != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '⚠️ $phoneErr',
                      style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFE53935),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (formValidationError != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFEF5350)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFD32F2F)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              formValidationError!,
                              style: GoogleFonts.nunito(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFB71C1C),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                      onPressed: isSubmitting
                          ? null
                          : () async {
                              final currentNoteErr = TextModerationService.validateDescription(
                                noteCtrl.text,
                                fieldName: 'Adoption intro/note',
                              );
                              if (currentNoteErr != null) {
                                setSheetState(() {
                                  hasAttemptedSubmit = true;
                                  formValidationError = '⚠️ $currentNoteErr';
                                });
                                return;
                              }

                              final currentPhoneErr = TextModerationService.validatePhoneNumber(
                                contactCtrl.text,
                                label: 'Adoption contact phone number',
                              );
                              if (currentPhoneErr != null) {
                                setSheetState(() {
                                  hasAttemptedSubmit = true;
                                  formValidationError = '⚠️ $currentPhoneErr';
                                });
                                return;
                              }

                              setSheetState(() {
                                isSubmitting = true;
                                formValidationError = null;
                              });
                              try {
                                await FirebaseService.instance
                                    .submitAdoptionApplication(
                                  sightingId: s.id,
                                  message: noteCtrl.text.trim(),
                                  contactPhone: contactCtrl.text.trim(),
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                _snack(
                                    'Adoption application submitted! Awaiting confirmation from $otherName.');
                              } catch (e) {
                                setSheetState(() {
                                  isSubmitting = false;
                                  formValidationError = 'Failed to submit application: $e';
                                });
                              }
                            },
                      child: isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.volunteer_activism_rounded,
                                    size: 18, color: Colors.white),
                                const SizedBox(width: 8),
                                Text(
                                  'Send Adoption Request',
                                  style: GoogleFonts.nunito(
                                      fontWeight: FontWeight.w900, fontSize: 14),
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPendingAdoptionBanner(Sighting s) {
    final currentUid = _uid;
    final isApplicant =
        currentUid != null && s.pendingAdoptionApplicantId == currentUid;
    final applicantName = s.pendingAdoptionApplicantName ?? 'Adopter';
    final otherName = s.careTakerName?.isNotEmpty == true
        ? s.careTakerName!
        : s.reporterName;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF2E7D32).withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(
                  color: Color(0xFF2E7D32),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.volunteer_activism_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isApplicant
                          ? 'Adoption Application Pending 🏡'
                          : 'Adoption Request from $applicantName 🏡',
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: _navy,
                      ),
                    ),
                    Text(
                      isApplicant
                          ? 'Sent to $otherName. Awaiting their confirmation.'
                          : 'Review application and confirm to finalize adoption (+200 XP).',
                      style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        color: _navy.withValues(alpha: 0.65),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (s.pendingAdoptionMessage?.isNotEmpty == true) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Applicant Note:',
                    style: GoogleFonts.nunito(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF2E7D32),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.pendingAdoptionMessage!,
                    style: GoogleFonts.nunito(
                      fontSize: 12,
                      color: _navy,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (s.pendingAdoptionContact?.isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      '📞 Contact: ${s.pendingAdoptionContact}',
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        color: _navy.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (isApplicant) ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF2E7D32)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => _openAdopterChat(s),
                icon: const Icon(Icons.chat_bubble_outline_rounded,
                    size: 15, color: Color(0xFF2E7D32)),
                label: Text(
                  '💬 Coordinate in Chat with $otherName',
                  style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: const Color(0xFF2E7D32)),
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    onPressed: () => _confirmApproveAdoptionDialog(s),
                    icon: const Icon(Icons.check_circle_rounded, size: 15),
                    label: Text(
                      'Confirm Adoption 🎉',
                      style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w900, fontSize: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: _navy.withValues(alpha: 0.2)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () async {
                    await FirebaseService.instance.declineAdoption(
                      sightingId: s.id,
                      updateId: s.pendingAdoptionUpdateId,
                    );
                    _snack('Adoption application declined.');
                  },
                  child: Text(
                    'Decline',
                    style: GoogleFonts.nunito(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: _navy.withValues(alpha: 0.6)),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Chat with Applicant',
                  icon: const Icon(Icons.chat_bubble_outline_rounded,
                      color: Color(0xFF2E7D32), size: 20),
                  onPressed: () {
                    final appUid = s.pendingAdoptionApplicantId ?? '';
                    if (appUid.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CoordinationChatScreen(
                            sighting: s,
                            otherUserId: appUid,
                            otherUserName: applicantName,
                            otherUserRole: 'Adoption Applicant',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmApproveAdoptionDialog(Sighting s) async {
    final applicantName = s.pendingAdoptionApplicantName ?? 'the applicant';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.celebration_rounded, color: Color(0xFF2E7D32)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Confirm Adoption? 🏡🎉',
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w900, fontSize: 16, color: _navy),
              ),
            ),
          ],
        ),
        content: Text(
          'Approving will officially mark this rescue as Rehomed and complete! Both you and $applicantName will receive +200 XP.',
          style: GoogleFonts.nunito(
              fontSize: 13, color: _navy.withValues(alpha: 0.8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text('Cancel',
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w700, color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text('Confirm & Rehome (+200 XP)',
                style: GoogleFonts.nunito(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      try {
        await FirebaseService.instance.approveAdoption(
          sightingId: s.id,
          updateId: s.pendingAdoptionUpdateId,
          applicantId: s.pendingAdoptionApplicantId ?? '',
          applicantName: applicantName,
        );
        _snack('🎉 Adoption confirmed! Cat successfully rehomed (+200 XP)');
      } catch (e) {
        _snack('Failed to confirm adoption: $e');
      }
    }
  }

  Widget _buildAdoptionShowcaseCard(Sighting s, bool isCaretaker) {
    final facilityName = s.shelterOrClinicName?.isNotEmpty == true
        ? s.shelterOrClinicName!
        : (s.isSheltered ? 'Verified Shelter' : 'Foster Home');

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFF2E7D32).withValues(alpha: 0.25),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Title on top
          Text(
            'Adoption Showcase Profile',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF2E7D32),
            ),
          ),
          const SizedBox(height: 14),

          // 2. Custom logo in the middle
          Center(
            child: Image.asset(
              'assets/images/review.png',
              height: 76,
              fit: BoxFit.contain,
            ),
          ),
          if (isCaretaker) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _showEditHealthTagsSheet(s),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.edit_note_rounded,
                        size: 14, color: Color(0xFF2E7D32)),
                    const SizedBox(width: 4),
                    Text(
                      'Edit Badges',
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF2E7D32),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),

          // 3. Short desc at the bottom
          Text(
            'Facility: $facilityName • Health verified under care supervision',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: _navy.withValues(alpha: 0.7),
              height: 1.3,
            ),
          ),
          if (s.healthTags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 5,
              alignment: WrapAlignment.center,
              children: s.healthTags.map((tag) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    tag,
                    style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF2E7D32),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
          if (isCaretaker) ...[
            const SizedBox(height: 16),
            InkWell(
              onTap: () => _showActionProofSheet('sheltered', s),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 170,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: const Color(0xFFE65100).withValues(alpha: 0.35),
                    width: 1.4,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Transfer to Shelter Instead',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFFE65100),
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Image.asset(
                      'assets/images/shelter.png',
                      width: 52,
                      height: 52,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE65100).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        '+120 XP',
                        style: GoogleFonts.nunito(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFE65100),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF2E7D32)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _openAdopterChat(s),
                    icon: const Icon(Icons.chat_bubble_outline_rounded,
                        size: 14, color: Color(0xFF2E7D32)),
                    label: Text(
                      'Chat Caretaker',
                      style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: const Color(0xFF2E7D32)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    onPressed: () => _showSubmitAdoptionApplicationSheet(s),
                    icon: const Icon(Icons.home_rounded, size: 14),
                    label: Text(
                      'Request to Adopt',
                      style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w800, fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCaretakerSquareActionButton({
    required String title,
    required String assetPath,
    required String xpText,
    required Color color,
    required VoidCallback onTap,
    bool isLocked = false,
    double? width,
  }) {
    final activeColor = isLocked ? Colors.grey.shade600 : color;
    final borderColor = isLocked
        ? Colors.grey.withValues(alpha: 0.35)
        : color.withValues(alpha: 0.35);
    final bgColor = isLocked
        ? Colors.grey.withValues(alpha: 0.05)
        : color.withValues(alpha: 0.04);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: width,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: 1.4,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              height: 30,
              child: Center(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: activeColor,
                    height: 1.15,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: isLocked ? 0.35 : 1.0,
                  child: Image.asset(
                    assetPath,
                    width: 50,
                    height: 50,
                    fit: BoxFit.contain,
                  ),
                ),
                if (isLocked)
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: _navy.withValues(alpha: 0.75),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isLocked
                    ? Colors.grey.withValues(alpha: 0.15)
                    : color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLocked) ...[
                    Icon(Icons.lock_outline_rounded,
                        size: 10, color: Colors.grey.shade700),
                    const SizedBox(width: 3),
                  ],
                  Text(
                    isLocked ? 'Locked' : xpText,
                    style: GoogleFonts.nunito(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: isLocked ? Colors.grey.shade700 : color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCareCustodyCard(
      Sighting s, bool isCaretaker, bool areOutcomesUnlocked) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF673AB7).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: const Color(0xFF673AB7).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Title on top
          Text(
            'Cat is Off-Street (${s.careLabel})',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: _navy,
            ),
          ),
          const SizedBox(height: 10),

          // 2. Custom logo in middle
          Center(
            child: Image.asset(
              'assets/images/needshome.png',
              height: 72,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 10),

          // 3. Short desc on bottom
          Text(
            'In active care with ${s.careTakerName?.isNotEmpty == true ? s.careTakerName : "a caregiver"}. Street visits & check-ins are paused.',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: _navy.withValues(alpha: 0.65),
              height: 1.3,
            ),
          ),
          if (isCaretaker) ...[
            const SizedBox(height: 14),
            Divider(color: const Color(0xFF673AB7).withValues(alpha: 0.18), height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                Text(
                  'Caretaker Actions:',
                  style: GoogleFonts.nunito(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                const SizedBox(width: 6),
                if (!areOutcomesUnlocked)
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline_rounded,
                              size: 11, color: Color(0xFFE65100)),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              'Complete checkpoints to unlock',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.nunito(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFFE65100),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (s.isFeral) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF00897B).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF00897B).withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.nature_people_rounded,
                        color: Color(0xFF00897B), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Mandatory TNR Colony Return 🌿',
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF00897B),
                            ),
                          ),
                          Text(
                            'This cat is an adult feral community cat. Feral cats thrive in their outdoor colony under community care. Domestic adoption and sheltering are prohibited.',
                            style: GoogleFonts.nunito(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _navy.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Center(
                child: _buildCaretakerSquareActionButton(
                  title: 'Return to Colony\n(TNR)',
                  assetPath: 'assets/images/feral.png',
                  xpText: '+100 XP',
                  color: const Color(0xFF00897B),
                  width: 170,
                  onTap: () => _showOutcomeConfirmationRequestSheet(
                      'returnedToSpot', s),
                ),
              ),
            ] else if (s.isOpenForAdoption) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFE65100).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFFE65100).withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.volunteer_activism_rounded,
                        color: Color(0xFFE65100), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Actively Listed for Adoption 🏡',
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFFE65100),
                            ),
                          ),
                          Text(
                            'Community members can view the adoption profile and apply. When someone adopts the cat, confirm Rehomed below.',
                            style: GoogleFonts.nunito(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _navy.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _buildCaretakerSquareActionButton(
                        title: 'Confirm Rehomed',
                        assetPath: 'assets/images/needshome.png',
                        xpText: '+200 XP',
                        color: _resolved,
                        onTap: () =>
                            _showOutcomeConfirmationRequestSheet('rehomed', s),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildCaretakerSquareActionButton(
                        title: 'Transfer to Shelter',
                        assetPath: 'assets/images/shelter.png',
                        xpText: '+120 XP',
                        color: const Color(0xFF673AB7),
                        onTap: () =>
                            _showOutcomeConfirmationRequestSheet('sheltered', s),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _buildCaretakerSquareActionButton(
                        title: 'Open for Adoption',
                        assetPath: 'assets/images/review.png',
                        xpText: '+100 XP',
                        color: const Color(0xFFE65100),
                        isLocked: !areOutcomesUnlocked,
                        onTap: areOutcomesUnlocked
                            ? () => _showOpenForAdoptionSheet(s)
                            : () => _snack(
                                'Complete all care checkpoints first to unlock adoption! 🐾'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildCaretakerSquareActionButton(
                        title: 'Already Rehomed',
                        assetPath: 'assets/images/needshome.png',
                        xpText: '+200 XP',
                        color: _resolved,
                        isLocked: !areOutcomesUnlocked,
                        onTap: areOutcomesUnlocked
                            ? () => _showOutcomeConfirmationRequestSheet(
                                'rehomed', s)
                            : () => _snack(
                                'Complete all care checkpoints first to unlock permanent rehoming! 🐾'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: _buildCaretakerSquareActionButton(
                  title: 'Transfer to Shelter',
                  assetPath: 'assets/images/shelter.png',
                  xpText: '+120 XP',
                  color: const Color(0xFF673AB7),
                  width: 170,
                  isLocked: !areOutcomesUnlocked,
                  onTap: areOutcomesUnlocked
                      ? () => _showOutcomeConfirmationRequestSheet(
                          'sheltered', s)
                      : () => _snack(
                          'Complete all care checkpoints first to unlock sheltering! 🐾'),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildActions(Sighting s, [bool showWaitingOnTop = false]) {
    final allActs = [
      {
        'key': 'vet',
        'icon': Icons.medical_services,
        'label': 'Vet Visit',
        'xp': '+100 XP',
        'sub': 'Took to vet',
        'asset': 'assets/images/guardianangel.png',
      },
      {
        'key': 'tookIn',
        'icon': Icons.home,
        'label': 'Took In',
        'xp': '+150 XP',
        'sub': 'Taking care',
        'asset': 'assets/images/needshome.png',
      },
      {
        'key': 'sheltered',
        'icon': Icons.house,
        'label': 'Sheltered',
        'xp': '+120 XP',
        'sub': 'In shelter',
        'asset': 'assets/images/shelter.png',
      },
      {
        'key': 'fed',
        'icon': Icons.restaurant,
        'label': 'Fed',
        'xp': '+30 XP',
        'sub': 'Gave food',
        'asset': 'assets/images/straycare.png',
      },
      {
        'key': 'roaming',
        'icon': Icons.edit_location_alt_outlined,
        'label': 'Still Here / Move',
        'xp': '+15-25 XP',
        'sub': 'Update spot',
        'asset': 'assets/images/location.png',
      },
    ];

    List<Map<String, Object>> acts;
    final cat = s.category;
    final isPriorityVet = s.isMedicalOrTriagePriority && !s.hasVetVisit;

    if (s.isNeedsHome ||
        cat == 'Needs Home' ||
        cat == 'Needs Foster' ||
        cat == 'Rehomed') {
      acts = [
        {
          'key': 'rehomed',
          'icon': Icons.favorite_rounded,
          'label': 'Rehomed',
          'xp': '+200 XP',
          'sub': 'Found forever home',
          'asset': 'assets/images/needshome.png',
        },
        {
          'key': 'sheltered',
          'icon': Icons.house_rounded,
          'label': 'Sheltered',
          'xp': '+120 XP',
          'sub': 'In shelter',
          'asset': 'assets/images/shelter.png',
        },
      ];
    } else if (s.isTnrCommunityCat) {
      acts = allActs;
    } else if (isPriorityVet) {
      acts = allActs
          .where((a) =>
              a['key'] == 'vet' ||
              a['key'] == 'roaming')
          .toList();
    } else if (cat == 'Injured' ||
        cat == 'Needs Vet' ||
        cat == 'Trapped' ||
        cat == 'Urgent Rescue' ||
        cat == 'Kitten') {
      acts = allActs
          .where((a) =>
              a['key'] == 'tookIn' ||
              a['key'] == 'sheltered' ||
              a['key'] == 'vet' ||
              a['key'] == 'roaming')
          .toList();
    } else {
      acts = allActs;
    }

    final uid = _uid;
    final isClaimed = s.rescueClaimed;
    final isClaimedByMe = isClaimed && uid != null && s.rescueClaimedBy == uid;
    final isHandoverPending = s.pendingHandoverRescuerId != null &&
        s.pendingHandoverRescuerId!.isNotEmpty;
    final isOutcomePending = s.pendingOutcomeAction != null &&
        s.pendingOutcomeAction!.isNotEmpty;
    final isVetPending = s.isVetVisitPending && !s.hasVetVisit;
    final isVetRescuer = _isVetRescuer(s);
    final isLockedForMe =
        (isClaimed && !isClaimedByMe && !_isOwner(s)) ||
            isHandoverPending ||
            isOutcomePending ||
            isVetPending ||
            (s.isAwaitingPostVetDecision && !isVetRescuer);
    final isFosterDeclinedForMe = uid != null && s.isFosterDeclinedFor(uid);

    if (s.isInCare && !s.isOpenForAdoption) {
      final isCaretaker = uid != null && s.careTakerId == uid;
      final areOutcomesUnlocked = s.areOutcomesUnlocked;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Care Custody',
                  style: GoogleFonts.nunito(
                      fontSize: 17, fontWeight: FontWeight.w900, color: _navy)),
              const Spacer(),
              Builder(builder: (context) {
                final isAdoption = s.isOpenForAdoption || s.category == 'Needs Home';
                final badgeColor = isAdoption ? const Color(0xFF9C27B0) : const Color(0xFF673AB7);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    s.careLabel,
                    style: GoogleFonts.nunito(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: badgeColor,
                    ),
                  ),
                );
              }),
            ],
          ),
          const SizedBox(height: 8),
          _buildCareCustodyCard(s, isCaretaker, areOutcomesUnlocked),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Actions',
              style: GoogleFonts.nunito(
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: _navy,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _lavender.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                s.isOneTimeTask ? '🎯 Targeted Task' : '🍲 Community Care',
                style: GoogleFonts.nunito(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: _lavender,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          isPriorityVet
              ? '🏥 Medical Triage: For ${s.category} situations, a vet clinic visit is required first.'
              : (s.isOneTimeTask
                  ? 'Action focused on ${s.category} situation. Verified by AI proof.'
                  : 'Choose an action to help. Visible to all rescuers.'),
          style: GoogleFonts.nunito(
              fontSize: 12,
              color: isPriorityVet
                  ? const Color(0xFF673AB7)
                  : _navy.withValues(alpha: 0.55),
              fontWeight: FontWeight.w600),
        ),
        if (isPriorityVet && !isVetPending) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF673AB7).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: const Color(0xFF673AB7).withValues(alpha: 0.25)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF673AB7).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.local_hospital_rounded,
                      color: Color(0xFF673AB7), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Veterinary Triage Required First',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFF673AB7),
                        ),
                      ),
                      Text(
                        'Please bring this cat for a vet checkup first. Once the vet visit is verified, Foster Care and Shelter options will unlock!',
                        style: GoogleFonts.nunito(
                          fontSize: 11,
                          color: _navy.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ] else if ((s.hasVetVisit || s.isAwaitingPostVetDecision) &&
            s.urgency != 'resolved' &&
            s.resolvedByAction != 'returnedToSpot') ...[
          const SizedBox(height: 10),
          Builder(builder: (ctx) {
            if (s.isAwaitingPostVetDecision) {
              if (showWaitingOnTop) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF673AB7).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFF673AB7).withValues(alpha: 0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_upward_rounded,
                          size: 16, color: Color(0xFF673AB7)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Awaiting next step — response box pinned to the very top of this report.',
                          style: GoogleFonts.nunito(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF673AB7),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }
              return _buildPostVetDecisionBanner(s);
            } else if (s.isCommunityFosterRequested) {
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E88E5).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color(0xFF1E88E5).withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E88E5).withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.volunteer_activism_rounded,
                              color: Color(0xFF1E88E5), size: 20),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '📢 Community Foster Care Needed',
                                style: GoogleFonts.nunito(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w900,
                                  color: const Color(0xFF1565C0),
                                ),
                              ),
                              Text(
                                '${s.lastVetRescuerName ?? "The rescuer"} completed vet care and requested community foster help.',
                                style: GoogleFonts.nunito(
                                  fontSize: 11,
                                  color: _navy.withValues(alpha: 0.7),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        InkWell(
                          onTap: () => _showActionProofSheet('tookIn', s),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF673AB7),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image.asset(
                                  'assets/images/needshome.png',
                                  width: 16,
                                  height: 16,
                                  fit: BoxFit.contain,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Offer Foster Care (+150 XP)',
                                  style: GoogleFonts.nunito(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => _showActionProofSheet('sheltered', s),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE65100),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Image.asset(
                                  'assets/images/shelter.png',
                                  width: 16,
                                  height: 16,
                                  fit: BoxFit.contain,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Transfer to Shelter (+120 XP)',
                                  style: GoogleFonts.nunito(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (s.lastVetRescuerId != null && s.lastVetRescuerId!.isNotEmpty)
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CoordinationChatScreen(
                                    sighting: s,
                                    otherUserId: s.lastVetRescuerId!,
                                    otherUserName: s.lastVetRescuerName ?? 'Rescuer',
                                  ),
                                ),
                              );
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF1E88E5)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.chat_bubble_rounded,
                                      size: 13, color: Color(0xFF1E88E5)),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Chat with Rescuer',
                                    style: GoogleFonts.nunito(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                        color: const Color(0xFF1E88E5)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }
            return const SizedBox.shrink();
          }),
        ],
      if (isLockedForMe && !s.isAwaitingPostVetDecision) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isVetPending
                ? const Color(0xFF673AB7).withValues(alpha: 0.08)
                : _lavender.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: isVetPending
                    ? const Color(0xFF673AB7).withValues(alpha: 0.25)
                    : _lavender.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isVetPending
                      ? const Color(0xFF673AB7).withValues(alpha: 0.15)
                      : _lavender.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isVetPending
                      ? Icons.medical_services_rounded
                      : (isHandoverPending || isOutcomePending
                          ? Icons.pending_actions_rounded
                          : Icons.directions_run),
                  color: isVetPending ? const Color(0xFF673AB7) : _lavender,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isVetPending
                          ? '⏳ Vet Visit Verification in Progress'
                          : (isHandoverPending
                              ? '⏳ Foster Custody Review Pending'
                              : (isOutcomePending
                                  ? '⏳ Final Outcome Review Pending'
                                  : '🏃 Rescuer Heading to Spot')),
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: isVetPending
                            ? const Color(0xFF673AB7)
                            : _lavender,
                      ),
                    ),
                    Text(
                      isVetPending
                          ? (_isOwner(s)
                              ? '${s.pendingVetRescuerName ?? "A rescuer"} submitted a vet visit report. Actions are locked until you verify or decline the report in the banner above.'
                              : '${s.pendingVetRescuerName ?? "A rescuer"} submitted vet visit report. Actions locked pending reporter confirmation.')
                          : (isHandoverPending
                              ? 'A foster custody request is awaiting reporter review.'
                              : (isOutcomePending
                                  ? 'Final outcome proof submitted, awaiting confirmation.'
                                  : '${s.rescueClaimedByName.isNotEmpty ? s.rescueClaimedByName : "A rescuer"} is on their way (45m window).')),
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        color: _navy.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (isVetPending && (_isOwner(s) || uid == s.pendingVetRescuerId))
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded,
                      color: Color(0xFF673AB7), size: 20),
                  onPressed: () {
                    final targetId = _isOwner(s)
                        ? (s.pendingVetRescuerId ?? '')
                        : s.reporterId;
                    final targetName = _isOwner(s)
                        ? (s.pendingVetRescuerName ?? 'Rescuer')
                        : (s.reporterName.isNotEmpty ? s.reporterName : 'Reporter');
                    if (targetId.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CoordinationChatScreen(
                            sighting: s,
                            otherUserId: targetId,
                            otherUserName: targetName,
                            otherUserRole: _isOwner(s) ? 'Vet Rescuer' : 'Reporter',
                          ),
                        ),
                      );
                    } else {
                      _snack('Contact info unavailable.');
                    }
                  },
                )
              else if (isClaimed && !isClaimedByMe && s.rescueClaimedBy.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.chat_bubble_outline_rounded,
                      color: _lavender, size: 20),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CoordinationChatScreen(
                          sighting: s,
                          otherUserId: s.rescueClaimedBy,
                          otherUserName: s.rescueClaimedByName,
                          otherUserRole: 'En Route Rescuer',
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
      if (!s.isAwaitingPostVetDecision &&
          (!s.hasVetVisit || s.isTnrCommunityCat) &&
          !s.isCommunityFosterRequested) ...[
        const SizedBox(height: 12),
        Container(
          height: acts.length <= 2 ? 340 : 380,
          decoration: BoxDecoration(
            color: const Color(0xFFF9F9FB),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _navy.withValues(alpha: 0.08),
              width: 1.2,
            ),
          ),
          child: RawScrollbar(
            thumbVisibility: true,
            trackVisibility: true,
            thickness: 6,
            radius: const Radius.circular(8),
            thumbColor: _navy.withValues(alpha: 0.3),
            trackColor: _navy.withValues(alpha: 0.06),
            trackRadius: const Radius.circular(8),
            controller: _actionsScrollController,
            child: ListView.separated(
              controller: _actionsScrollController,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              itemCount: acts.length,
              separatorBuilder: (context, index) => const SizedBox(height: 22),
              itemBuilder: (context, index) {
                final a = acts[index];
                final key = a['key'] as String;
                final isTookIn = key == 'tookIn';
                final isDeclinedTookIn = isTookIn && isFosterDeclinedForMe;
                final isSel = _myAction == key;
                final isTileLocked = isLockedForMe || isDeclinedTookIn;
                final isVetPriorityTile =
                    key == 'vet' && s.isMedicalOrTriagePriority && !s.hasVetVisit;
                final col = _aColor(key);
                final assetPath = a['asset'] as String?;

                return GestureDetector(
                  onTap: () {
                    if (_isActionSheetOpen) return;
                    if (!DoubleTapGuard.allow('action_tile_${key}_${s.id}')) return;
                    if (isDeclinedTookIn) {
                      _snack(
                          'Your foster custody request for this cat was previously declined by the reporter.');
                      return;
                    }
                    if (isLockedForMe) {
                      if (isVetPending) {
                        _snack(_isOwner(s)
                            ? '⏳ Actions are locked while vet visit report is pending. Please verify or decline the report in the banner above.'
                            : '⏳ ${s.pendingVetRescuerName?.isNotEmpty == true ? s.pendingVetRescuerName : "A rescuer"} submitted a vet visit report. Actions are locked pending verification.');
                      } else if (s.isAwaitingPostVetDecision) {
                        _snack(
                            '⏳ ${s.lastVetRescuerName?.isNotEmpty == true ? s.lastVetRescuerName : "The rescuer"} is currently in charge of this cat after vet care.');
                      } else {
                        _snack(
                            '🏃 ${s.rescueClaimedByName.isNotEmpty ? s.rescueClaimedByName : "A rescuer"} is already heading to help this cat.');
                      }
                      return;
                    }
                    if (key == 'roaming') {
                      _showRoamingUpdateSheet(s);
                    } else if (key == 'rehomed') {
                      _showOutcomeConfirmationRequestSheet('rehomed', s);
                    } else if (s.isFeral &&
                        (key == 'tookIn' || key == 'sheltered')) {
                      _snack(
                          '🌿 This is an unsocialized feral cat. Foster and shelter adoptions are not suitable for feral cats. Mandatory TNR Return to Colony is the only permitted outcome.');
                    } else if ((key == 'tookIn' || key == 'sheltered') &&
                        s.isMedicalOrTriagePriority &&
                        !s.hasVetVisit) {
                      _showMedicalTriageGuidanceDialog(s, key);
                    } else {
                      _showActionProofSheet(key, s);
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 1. Action Name (Title at top)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isVetPriorityTile) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF673AB7),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '⭐ Priority 1st',
                                style: GoogleFonts.nunito(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                          Text(
                            a['label'] as String,
                            textAlign: TextAlign.center,
                            style: GoogleFonts.nunito(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: isDeclinedTookIn
                                  ? Colors.red.shade400
                                  : (isTileLocked
                                      ? _navy.withValues(alpha: 0.5)
                                      : (isVetPriorityTile
                                          ? const Color(0xFF673AB7)
                                          : _navy)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // 2. Big box with custom icon in the center
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 110,
                        height: 110,
                        decoration: BoxDecoration(
                          color: isTileLocked
                              ? Colors.grey.withValues(alpha: 0.08)
                              : (isVetPriorityTile
                                  ? const Color(0xFF673AB7).withValues(alpha: 0.08)
                                  : (isSel
                                      ? col.withValues(alpha: 0.12)
                                      : Colors.white)),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isTileLocked
                                ? (isDeclinedTookIn
                                    ? Colors.red.shade200
                                    : Colors.grey.withValues(alpha: 0.2))
                                : (isVetPriorityTile
                                    ? const Color(0xFF673AB7)
                                    : (isSel
                                        ? col
                                        : _navy.withValues(alpha: 0.14))),
                            width: (isSel || isVetPriorityTile) ? 2.5 : 1.2,
                          ),
                          boxShadow: isTileLocked
                              ? null
                              : [
                                  BoxShadow(
                                    color: (isVetPriorityTile
                                            ? const Color(0xFF673AB7)
                                            : col)
                                        .withValues(alpha: 0.16),
                                    blurRadius: 10,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Opacity(
                              opacity: isTileLocked ? 0.45 : 1.0,
                              child: assetPath != null
                                  ? Image.asset(
                                      assetPath,
                                      width: 66,
                                      height: 66,
                                      fit: BoxFit.contain,
                                    )
                                  : Icon(
                                      isDeclinedTookIn
                                          ? Icons.block_rounded
                                          : (a['icon'] as IconData),
                                      size: 40,
                                      color: isDeclinedTookIn
                                          ? Colors.red.shade400
                                          : (isVetPriorityTile
                                              ? const Color(0xFF673AB7)
                                              : col),
                                    ),
                            ),
                            if (isTileLocked && !isDeclinedTookIn)
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.lock_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            if (isDeclinedTookIn)
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color:
                                      Colors.red.shade400.withValues(alpha: 0.8),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 7),

                      // 3. Short desc at bottom
                      Text(
                        isDeclinedTookIn
                            ? 'Not available (Declined)'
                            : '${a['sub']} • ${a['xp']}',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.nunito(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDeclinedTookIn
                              ? Colors.red.shade300
                              : (isTileLocked
                                  ? _navy.withValues(alpha: 0.4)
                                  : (isVetPriorityTile
                                      ? const Color(0xFF673AB7)
                                      : _navy.withValues(alpha: 0.6))),
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ],
  ]);
}

  Widget _buildThanks() => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: _lavLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _lavender.withValues(alpha: 0.25),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: _lavender.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Thank you for helping!',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: _navy,
              ),
            ),
            const SizedBox(height: 12),
            Image.asset(
              'assets/images/signoutpop.png',
              height: 80,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 12),
            Text(
              'Your action makes a big difference.',
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 13,
                color: _navy.withValues(alpha: 0.65),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  Widget _buildResolvedBanner(Sighting s) {
    final cat = s.category;
    String resolutionTitle = 'Rescue Case Resolved';
    String resolutionMsg =
        'This sighting is resolved and the rescue goal has been achieved. Comments and photo updates remain open for discussion below!';
    String customAsset = 'assets/images/guardianangel.png';

    final wasFosteredOrRehomed = s.resolvedByAction == 'rehomed' ||
        s.careTakerId != null ||
        s.careStartedAt != null ||
        s.completedMilestones.isNotEmpty ||
        s.careStatus == 'resolved' ||
        cat == 'Rehomed' ||
        cat == 'Needs Foster' ||
        cat == 'Needs Home' ||
        s.isRehomed;

    final isTnr = s.resolvedByAction == 'returnedToSpot' || s.isTnrReturned;
    final isSheltered = s.resolvedByAction == 'sheltered' ||
        s.careStatus == 'inCare_shelter' ||
        s.isSheltered;

    final bannerCol = isSheltered
        ? const Color(0xFF673AB7)
        : (isTnr ? const Color(0xFF00897B) : _resolved);

    if (isSheltered) {
      resolutionTitle = 'Safely Transferred to Shelter';
      customAsset = 'assets/images/shelter.png';
      resolutionMsg =
          'This cat was safely admitted to verified shelter care. Comments remain open for updates!';
    } else if (isTnr) {
      resolutionTitle = 'Returned Safely to Colony (TNR)';
      customAsset = 'assets/images/feral.png';
      resolutionMsg =
          'This cat completed veterinary recovery care and was safely returned to its outdoor colony territory. Community feeders are welcomed to check in, log feedings, and post photo updates!';
    } else if (wasFosteredOrRehomed) {
      resolutionTitle = 'Cat Successfully Rehomed';
      customAsset = 'assets/images/needshome.png';
      resolutionMsg =
          'This cat has completed foster care and was successfully adopted into a loving forever home! Feel free to share congratulations or photo updates below.';
    } else if (cat == 'Injured' || cat == 'Needs Vet' || s.resolvedByAction == 'vet') {
      resolutionTitle = 'Medical Care Completed';
      customAsset = 'assets/images/guardianangel.png';
      resolutionMsg =
          'This cat was safely brought for veterinary medical care. Comments remain open for recovery and follow-up updates!';
    } else {
      resolutionTitle = 'Cat Safely Fostered / Rehomed';
      customAsset = 'assets/images/needshome.png';
      resolutionMsg =
          'This cat has found a safe foster or loving home! Feel free to share congratulations or photo updates in comments below.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: bannerCol.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: bannerCol.withValues(alpha: 0.28),
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 1. Title on top
          Text(
            resolutionTitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: _navy,
            ),
          ),
          const SizedBox(height: 10),

          // 2. Custom logo in middle
          Center(
            child: Image.asset(
              customAsset,
              height: 72,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 10),

          // 3. Short desc on bottom
          Text(
            resolutionMsg,
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: _navy.withValues(alpha: 0.65),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommunity(Sighting s) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          'Community Updates',
          style: GoogleFonts.nunito(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: _navy,
          ),
        ),
        const SizedBox(height: 12),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: FirebaseService.instance.streamCommunityUpdates(s.id),
          builder: (context, snap) {
            final updates = snap.data ?? [];

            List<Map<String, dynamic>> getReplies(String parentId) {
              return updates
                  .where((r) =>
                      r['parentId'] == parentId && r['isDeleted'] != true)
                  .toList();
            }

            final top = updates.where((u) {
              if ((u['parentId'] ?? '') != '') return false;
              final isDeleted = u['isDeleted'] == true;
              final childReplies = getReplies(u['id'] ?? '');
              if (isDeleted && childReplies.isEmpty) return false;
              return true;
            }).toList();

            if (top.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Center(
                    child: Column(children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 36, color: _lavender.withValues(alpha: 0.3)),
                  const SizedBox(height: 8),
                  Text('No updates yet. Be the first to help!',
                      style: GoogleFonts.nunito(
                          fontSize: 13,
                          color: _navy.withValues(alpha: 0.45),
                          fontWeight: FontWeight.w600)),
                ])),
              );
            }

            return Column(
                children: top.map((u) {
              final replies = getReplies(u['id'] ?? '');
              return _updateTile(u, replies, s);
            }).toList());
          },
        ),
        const SizedBox(height: 14),
        _buildCommentInput(s.id),
      ]);

  Widget _updateTile(Map<String, dynamic> u,
      List<Map<String, dynamic>> replies, Sighting s) {
    final sid = s.id;
    final type = u['type'] ?? 'comment';
    final name = u['authorName'] ?? 'Anonymous';
    final action = u['action'] as String?;
    final isWay = type == 'onMyWay';
    final isWayCancelled = type == 'onMyWayCancelled';
    final isTripCancelled = u['isCancelled'] == true;
    final isAct = type == 'action';
    final isCustodyRequest = type == 'custodyRequest';
    final isHandoverApproved = type == 'handoverApproved';
    final isMilestone = type == 'milestoneCheckIn';
    final isOutcomeResolved = type == 'outcomeResolved';
    final isOutcomeRequest = type == 'outcomeRequest';
    final isAdoptionOpened = type == 'adoptionOpened';
    final isAnon = u['isAnonymous'] == true;
    final isDeleted = u['isDeleted'] == true;
    final isEdited = u['isEdited'] == true;
    final dName = isAnon ? 'Anonymous' : name;
    final aCol = isOutcomeResolved || isOutcomeRequest
        ? const Color(0xFF2E7D32)
        : isAdoptionOpened
            ? const Color(0xFFE65100)
            : isMilestone
                ? const Color(0xFFFFA000)
                : isCustodyRequest
                    ? const Color(0xFF673AB7)
                    : isHandoverApproved
                        ? const Color(0xFF2E7D32)
                        : isWayCancelled || (isWay && isTripCancelled)
                            ? const Color(0xFF78909C)
                            : isWay
                                ? _lavender
                                : isAct
                                    ? _aColor(action ?? '')
                                    : _avColor(isAnon ? 'Anon' : name);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () {
            final authorUid = u['authorId']?.toString() ?? '';
            if (!isAnon && authorUid.isNotEmpty) {
              _showRescuerTrustModal(authorUid, name);
            }
          },
          child: Container(
              width: 34,
              height: 34,
              decoration:
                  BoxDecoration(color: aCol, shape: BoxShape.circle),
              child: Center(
                  child: isAdoptionOpened
                      ? const Icon(Icons.volunteer_activism_rounded,
                          size: 16, color: Colors.white)
                      : isOutcomeResolved || isOutcomeRequest
                          ? Icon(
                              action == 'rehomed'
                                  ? Icons.celebration
                                  : (action == 'sheltered'
                                      ? Icons.house
                                      : Icons.pets),
                              size: 16,
                              color: Colors.white,
                            )
                          : isMilestone
                              ? const Icon(Icons.assignment_turned_in,
                                  size: 16, color: Colors.white)
                              : isCustodyRequest
                                  ? const Icon(Icons.handshake_rounded,
                                      size: 16, color: Colors.white)
                                  : isHandoverApproved
                                      ? const Icon(Icons.verified,
                                          size: 16, color: Colors.white)
                                      : isWayCancelled || (isWay && isTripCancelled)
                                          ? const Icon(Icons.person_off_outlined,
                                              size: 16, color: Colors.white)
                                          : isWay
                                              ? const Icon(Icons.directions_run,
                                                  size: 16, color: Colors.white)
                                              : isAct
                                                  ? Icon(_aIcon(action ?? ''),
                                                      size: 14, color: Colors.white)
                                                  : Text(_ini(isAnon ? 'AN' : name),
                                                        style: GoogleFonts.nunito(
                                                            fontSize: 11,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: Colors.white)))),
        ),
        const SizedBox(width: 10),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        GestureDetector(
                          onTap: () {
                            final authorUid = u['authorId']?.toString() ?? '';
                            if (!isAnon && authorUid.isNotEmpty) {
                              _showRescuerTrustModal(authorUid, name);
                            }
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(dName,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.nunito(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: _navy)),
                              ),
                              if (!isAnon) ...[
                                const SizedBox(width: 3),
                                Icon(Icons.shield_outlined,
                                    size: 12, color: _lavender),
                              ],
                            ],
                          ),
                        ),
                        if (isMilestone)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color:
                                    const Color(0xFFFFA000).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(
                                'Day ${u['milestoneDay'] ?? 1} Care Check-In',
                                style: GoogleFonts.nunito(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFFFFA000))),
                          ),
                        if (isAdoptionOpened)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color:
                                    const Color(0xFFE65100).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text('Adoption Open 🏡',
                                style: GoogleFonts.nunito(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFFE65100))),
                          ),
                        if (isOutcomeResolved || isOutcomeRequest)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color:
                                    const Color(0xFF2E7D32).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(
                                action == 'rehomed'
                                    ? 'Permanently Rehomed 🏡'
                                    : (action == 'sheltered'
                                        ? 'Shelter Transfer 🏛️'
                                        : 'Returned (TNR) 🌿'),
                                style: GoogleFonts.nunito(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF2E7D32))),
                          ),
                        if (isCustodyRequest)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color:
                                    const Color(0xFF673AB7).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text('Foster Request',
                                style: GoogleFonts.nunito(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF673AB7))),
                          ),
                        if (isHandoverApproved)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color:
                                    const Color(0xFF2E7D32).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text('Custody Transferred',
                                style: GoogleFonts.nunito(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF2E7D32))),
                          ),
                        if (isAct && action != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color:
                                    _aColor(action).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(_aLabels[action] ?? action,
                                style: GoogleFonts.nunito(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    color: _aColor(action))),
                          ),
                        if (isWay)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: isTripCancelled
                                    ? const Color(0xFF78909C).withValues(alpha: 0.12)
                                    : _lavender.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(
                              isTripCancelled ? 'Trip Cancelled' : 'On My Way',
                              style: GoogleFonts.nunito(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: isTripCancelled
                                    ? const Color(0xFF78909C)
                                    : _lavender,
                              ),
                            ),
                          ),
                        if (isWayCancelled)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: const Color(0xFF78909C).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(6)),
                            child: Text(
                              'Rescue Cancelled',
                              style: GoogleFonts.nunito(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF78909C),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_fmtTime(u['createdAt']),
                          style: GoogleFonts.nunito(
                              fontSize: 10,
                              color: _navy.withValues(alpha: 0.4),
                              fontWeight: FontWeight.w600)),
                      if (isEdited && !isDeleted)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text('(edited)',
                              style: GoogleFonts.nunito(
                                  fontSize: 10,
                                  fontStyle: FontStyle.italic,
                                  color: _navy.withValues(alpha: 0.35))),
                        ),
                      if (!isDeleted && !isWayCancelled)
                        GestureDetector(
                          onTap: () => _showCommentMenu(u, s),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(Icons.more_horiz,
                                size: 16,
                                color: _navy.withValues(alpha: 0.4)),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 2),
              if (isDeleted)
                Text('(comment deleted)',
                    style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: _navy.withValues(alpha: 0.4),
                        fontWeight: FontWeight.w500))
              else if (isWay && isTripCancelled)
                Text(
                  '$dName cancelled their rescue trip.',
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: _navy.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w600,
                  ),
                )
              else if (isWayCancelled)
                Text(
                  '$dName cancelled the rescue.',
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    color: _navy.withValues(alpha: 0.65),
                    fontWeight: FontWeight.w600,
                  ),
                )
              else if (type == 'comment')
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: SelectableText(
                    (u['text'] ?? '').toString(),
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      color: _navy.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                )
              else ...[
                InkWell(
                  onTap: () => _showUpdateDetailsModal(u, s),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            style: GoogleFonts.nunito(
                                fontSize: 13,
                                color: (isOutcomeResolved || isOutcomeRequest)
                                    ? const Color(0xFF1B5E20)
                                    : (isAdoptionOpened
                                        ? const Color(0xFFBF360C)
                                        : _navy.withValues(alpha: 0.8)),
                                fontWeight: FontWeight.w600,
                                height: 1.4),
                            children: [
                              TextSpan(
                                  text: '$dName ',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                              TextSpan(
                                text: _getCleanSummaryText(u),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _lavLight.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _lavender.withValues(alpha: 0.28),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline_rounded,
                                  size: 13, color: _lavender),
                              const SizedBox(width: 5),
                              Text(
                                'Tap to view action details',
                                style: GoogleFonts.nunito(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: _navy,
                                ),
                              ),
                              const Spacer(),
                              Icon(Icons.chevron_right_rounded,
                                  size: 14,
                                  color: _navy.withValues(alpha: 0.4)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (isAct) ...[
                const SizedBox(height: 6),
                if (u['isReporterConfirmed'] == true || u['action'] == 'returnedToSpot')
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _resolved.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border:
                          Border.all(color: _resolved.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.verified, size: 12, color: _resolved),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            u['action'] == 'returnedToSpot'
                                ? 'Verified Colony Return (+${u['pendingXp'] ?? 100} XP)'
                                : 'Verified by Reporter (+${u['pendingXp'] ?? 15} XP)',
                            style: GoogleFonts.nunito(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: _resolved,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (_isOwner(s) && u['authorId'] != _uid)
                  GestureDetector(
                    onTap: () async {
                      final awarded = await FirebaseService.instance
                          .confirmRescueAction(sid, u['id']);
                      if (mounted) {
                        _snack('Rescue action verified! +$awarded XP awarded to $dName 🐾');
                      }
                    },
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _resolved.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _resolved),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle,
                              size: 13, color: _resolved),
                          const SizedBox(width: 5),
                          Text(
                            'Verify & Award +${u['pendingXp'] ?? 15} XP',
                            style: GoogleFonts.nunito(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: _resolved,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (u['authorId'] == _uid)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFA000).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: const Color(0xFFFFA000).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.schedule,
                            size: 12, color: Color(0xFFFFA000)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            'Pending Reporter Verification (+${u['pendingXp'] ?? 15} XP)',
                            style: GoogleFonts.nunito(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFFFFA000),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _navy.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Awaiting Reporter Confirmation',
                      style: GoogleFonts.nunito(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: _navy.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
              ],
              if (isCustodyRequest) ...[
                const SizedBox(height: 6),
                if (u['status'] == 'approved')
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle,
                            size: 12, color: Color(0xFF2E7D32)),
                        const SizedBox(width: 4),
                        Text(
                          'Handover Approved by Reporter (+150 XP)',
                          style: GoogleFonts.nunito(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF2E7D32),
                          ),
                        ),
                      ],
                    ),
                  )
                else if (u['status'] == 'declined')
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '✕ Handover declined by reporter',
                      style: GoogleFonts.nunito(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.red.shade400,
                      ),
                    ),
                  )
                else if (_isOwner(s)) ...[
                  Row(
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade400,
                          side: BorderSide(color: Colors.red.shade300),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          await FirebaseService.instance
                              .declineCustodyHandover(
                            sightingId: s.id,
                            updateId: u['id'] ?? '',
                            rescuerId: u['userId']?.toString() ??
                                s.pendingHandoverRescuerId,
                          );
                          _snack('Foster handover request declined.');
                        },
                        child: Text('Decline',
                            style: GoogleFonts.nunito(
                                fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () async {
                          final authorUid = u['authorId']?.toString() ?? '';
                          final authorName =
                              u['authorName']?.toString() ?? 'Rescuer';
                          try {
                            await FirebaseService.instance
                                .approveCustodyHandover(
                              sightingId: s.id,
                              updateId: u['id']?.toString(),
                              rescuerUid: authorUid,
                              rescuerName: authorName,
                            );
                            _snack(
                                'Handover approved! Custody transferred to $authorName 🐾');
                            _showReporterReviewSheet(
                                authorUid, authorName, s.id);
                          } catch (e) {
                            _snack('Error approving handover: $e');
                          }
                        },
                        child: Text('Approve Handover',
                            style: GoogleFonts.nunito(
                                fontSize: 11, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                ] else if (u['authorId'] == _uid) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF673AB7).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: const Color(0xFF673AB7).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.schedule,
                            size: 12, color: Color(0xFF673AB7)),
                        const SizedBox(width: 4),
                        Text(
                          'Custody Request Pending Reporter Review',
                          style: GoogleFonts.nunito(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF673AB7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _navy.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Pending Reporter Handover Review',
                      style: GoogleFonts.nunito(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: _navy.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              ],
              if (isWay)
                Text('Auto-posted when marked on my way',
                    style: GoogleFonts.nunito(
                        fontSize: 10,
                        fontStyle: FontStyle.italic,
                        color: _lavender.withValues(alpha: 0.7))),
              if (!isDeleted)
                GestureDetector(
                  onTap: () => setState(() {
                    _replyingToId = u['id'];
                    _replyingToName = dName;
                  }),
                  child: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('Reply',
                          style: GoogleFonts.nunito(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _lavender))),
                ),
              if (replies.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4),
                  child: Column(
                      children: replies.map((r) {
                    final rAnon = r['isAnonymous'] == true;
                    final rName = rAnon
                        ? 'Anonymous'
                        : (r['authorName'] ?? 'Anonymous');
                    final rDeleted = r['isDeleted'] == true;
                    final rEdited = r['isEdited'] == true;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Container(
                                width: 2,
                                height: 28,
                                margin: const EdgeInsets.only(
                                    right: 10),
                                color: _lavender.withValues(
                                    alpha: 0.3)),
                            Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                    color: _avColor(
                                        rAnon ? 'Anon' : rName),
                                    shape: BoxShape.circle),
                                child: Center(
                                    child: Text(
                                        _ini(rAnon ? 'AN' : rName),
                                        style: GoogleFonts.nunito(
                                            fontSize: 9,
                                            fontWeight:
                                                FontWeight.w800,
                                            color: Colors.white)))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Row(children: [
                                    Text(rName,
                                        style: GoogleFonts.nunito(
                                            fontSize: 12,
                                            fontWeight:
                                                FontWeight.w800,
                                            color: _navy)),
                                    const Spacer(),
                                    Text(_fmtTime(r['createdAt']),
                                        style: GoogleFonts.nunito(
                                            fontSize: 10,
                                            color: _navy.withValues(
                                                alpha: 0.4),
                                            fontWeight:
                                                FontWeight.w600)),
                                    if (rEdited && !rDeleted)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                            left: 4),
                                        child: Text('(edited)',
                                            style: GoogleFonts.nunito(
                                                fontSize: 10,
                                                fontStyle:
                                                    FontStyle.italic,
                                                color: _navy.withValues(
                                                    alpha: 0.35))),
                                      ),
                                    if (!rDeleted)
                                      GestureDetector(
                                        onTap: () =>
                                            _showCommentMenu(r, s),
                                        child: Padding(
                                          padding:
                                              const EdgeInsets.only(
                                                  left: 6),
                                          child: Icon(Icons.more_horiz,
                                              size: 14,
                                              color: _navy.withValues(
                                                  alpha: 0.4)),
                                        ),
                                      ),
                                  ]),
                                  const SizedBox(height: 2),
                                  if (rDeleted)
                                    Text('(comment deleted)',
                                        style: GoogleFonts.nunito(
                                            fontSize: 12,
                                            fontStyle: FontStyle.italic,
                                            color: _navy.withValues(
                                                alpha: 0.4),
                                            fontWeight:
                                                FontWeight.w500))
                                  else
                                    Text(r['text'] ?? '',
                                        style: GoogleFonts.nunito(
                                            fontSize: 12,
                                            color: _navy.withValues(
                                                alpha: 0.7),
                                            fontWeight:
                                                FontWeight.w600)),
                                ])),
                          ]),
                    );
                  }).toList()),
                ),
            ])),
      ]),
    );
  }

  Widget _buildCommentInput(String sid) {
    final isReply = _replyingToId != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (isReply)
        Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: _lavLight,
              borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            Icon(Icons.reply, size: 14, color: _lavender),
            const SizedBox(width: 6),
            Expanded(
                child: Text('Replying to $_replyingToName',
                    style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _lavender))),
            GestureDetector(
                onTap: () => setState(() {
                      _replyingToId = null;
                      _replyingToName = null;
                    }),
                child: Icon(Icons.close, size: 14, color: _lavender)),
          ]),
        ),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: _navy.withValues(alpha: 0.1))),
            child: TextField(
              controller: isReply ? _replyCtrl : _commentCtrl,
              maxLines: 3,
              minLines: 1,
              style: GoogleFonts.nunito(
                  fontSize: 13,
                  color: _navy,
                  fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: isReply
                    ? 'Write a reply...'
                    : 'Write a comment...',
                hintStyle: GoogleFonts.nunito(
                    fontSize: 13,
                    color: _navy.withValues(alpha: 0.35)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _isPostingComment
              ? null
              : () => isReply ? _postReply(sid) : _postComment(sid),
          child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: _isPostingComment
                      ? _lavender.withValues(alpha: 0.5)
                      : _lavender,
                  shape: BoxShape.circle),
              child: _isPostingComment
                  ? const Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 18)),
        ),
      ]),
      const SizedBox(height: 6),
      GestureDetector(
        onTap: () => setState(() => _isAnon = !_isAnon),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: _isAnon ? _lavender : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                  color: _isAnon
                      ? _lavender
                      : _navy.withValues(alpha: 0.25)),
            ),
            child: _isAnon
                ? const Icon(Icons.check, size: 12, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 6),
          Text('Post anonymously',
              style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _navy.withValues(alpha: 0.55))),
        ]),
      ),
    ]);
  }

  Widget _moreMenu(Sighting s) {
    final own = _isOwner(s);
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child:
              Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: _navy.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2))),
            if (own) ...[
              ListTile(
                leading: const Icon(Icons.edit_outlined,
                    color: Color(0xFF9B8EC4)),
                title: Text('Edit Report',
                    style: GoogleFonts.nunito(
                        fontWeight: FontWeight.w700, color: _navy)),
                subtitle: Text('Change title or description',
                    style: GoogleFonts.nunito(
                        fontSize: 12,
                        color: _navy.withValues(alpha: 0.5))),
                onTap: () {
                  Navigator.pop(context);
                  _showEdit(s);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: Color(0xFFE53935)),
                title: Text('Delete Report',
                    style: GoogleFonts.nunito(
                        fontWeight: FontWeight.w700, color: _urgent)),
                subtitle: Text('This cannot be undone',
                    style: GoogleFonts.nunito(
                        fontSize: 12,
                        color: _navy.withValues(alpha: 0.5))),
                onTap: () => _confirmDelete(s),
              ),
            ] else ...[
              ListTile(
                leading: const Icon(Icons.flag_outlined,
                    color: Color(0xFFE53935)),
                title: Text('Flag this Sighting',
                    style: GoogleFonts.nunito(
                        fontWeight: FontWeight.w700, color: _urgent)),
                subtitle: Text(
                    'Report inappropriate or incorrect information',
                    style: GoogleFonts.nunito(
                        fontSize: 12,
                        color: _navy.withValues(alpha: 0.5))),
                onTap: () => _showFlag(s),
              ),
            ],
            const Divider(height: 1),
            ListTile(
              leading:
                  Icon(Icons.close, color: _navy.withValues(alpha: 0.4)),
              title: Text('Cancel',
                  style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w600,
                      color: _navy.withValues(alpha: 0.6))),
              onTap: () => Navigator.pop(context),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _editSheet(Sighting s, TextEditingController tc,
      TextEditingController dc) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    bool hasAttemptedSubmit = false;
    String? formValidationError;
    bool isSaving = false;

    return StatefulBuilder(
      builder: (sheetCtx, setSheetState) {
        final titleErr = TextModerationService.validateReportTitle(tc.text);
        final descErr = TextModerationService.validateDescription(
          dc.text,
          fieldName: 'Description',
        );

        return Container(
          decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(24))),
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, bottomPadding > 0 ? bottomPadding + 16 : 24),
          child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                      child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                              color: _navy.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(2)))),
                  Text('Edit Report',
                      style: GoogleFonts.nunito(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: _navy)),
                  const SizedBox(height: 16),
                  Text('Title',
                      style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w700,
                          color: _navy,
                          fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                      controller: tc,
                      onChanged: (_) => setSheetState(() {}),
                      maxLength: 70,
                      style: GoogleFonts.nunito(
                          fontSize: 14,
                          color: _navy,
                          fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'Report title...',
                        hintStyle: GoogleFonts.nunito(
                            color: _navy.withValues(alpha: 0.35)),
                        filled: true,
                        fillColor: _lavLight,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && titleErr != null)
                                ? const Color(0xFFE53935)
                                : BorderSide.none.color,
                            width: (hasAttemptedSubmit && titleErr != null) ? 1.5 : 0,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && titleErr != null)
                                ? const Color(0xFFE53935)
                                : Colors.transparent,
                            width: (hasAttemptedSubmit && titleErr != null) ? 1.5 : 0,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && titleErr != null)
                                ? const Color(0xFFE53935)
                                : _lavender,
                            width: 1.5,
                          ),
                        ),
                        counterStyle: GoogleFonts.nunito(
                            fontSize: 11,
                            color: _navy.withValues(alpha: 0.4)),
                      )),
                  if (hasAttemptedSubmit && titleErr != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '⚠️ $titleErr',
                      style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFE53935),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  const SizedBox(height: 12),
                  Text('Description',
                      style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w700,
                          color: _navy,
                          fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                      controller: dc,
                      onChanged: (_) => setSheetState(() {}),
                      maxLines: 4,
                      maxLength: 500,
                      style: GoogleFonts.nunito(
                          fontSize: 13,
                          color: _navy,
                          fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        hintText: 'Describe what you saw...',
                        hintStyle: GoogleFonts.nunito(
                            color: _navy.withValues(alpha: 0.35)),
                        filled: true,
                        fillColor: _lavLight,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && descErr != null)
                                ? const Color(0xFFE53935)
                                : BorderSide.none.color,
                            width: (hasAttemptedSubmit && descErr != null) ? 1.5 : 0,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && descErr != null)
                                ? const Color(0xFFE53935)
                                : Colors.transparent,
                            width: (hasAttemptedSubmit && descErr != null) ? 1.5 : 0,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: (hasAttemptedSubmit && descErr != null)
                                ? const Color(0xFFE53935)
                                : _lavender,
                            width: 1.5,
                          ),
                        ),
                        counterStyle: GoogleFonts.nunito(
                            fontSize: 11,
                            color: _navy.withValues(alpha: 0.4)),
                      )),
                  if (hasAttemptedSubmit && descErr != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '⚠️ $descErr',
                      style: GoogleFonts.nunito(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFFE53935),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  const SizedBox(height: 16),
                  if (formValidationError != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFEF5350)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFD32F2F)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              formValidationError!,
                              style: GoogleFonts.nunito(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFB71C1C),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _lavender,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14))),
                        onPressed: isSaving
                            ? null
                            : () async {
                                final currentTitleErr =
                                    TextModerationService.validateReportTitle(tc.text);
                                if (currentTitleErr != null) {
                                  setSheetState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = '⚠️ $currentTitleErr';
                                  });
                                  return;
                                }
                                final currentDescErr =
                                    TextModerationService.validateDescription(dc.text,
                                        fieldName: 'Description');
                                if (currentDescErr != null) {
                                  setSheetState(() {
                                    hasAttemptedSubmit = true;
                                    formValidationError = '⚠️ $currentDescErr';
                                  });
                                  return;
                                }
                                setSheetState(() {
                                  isSaving = true;
                                  formValidationError = null;
                                });
                                try {
                                  await FirebaseService.instance.updateSighting(
                                      s.id,
                                      title: tc.text.trim(),
                                      description: dc.text.trim());
                                  if (mounted) {
                                    Navigator.pop(context);
                                    _snack('Report updated!');
                                  }
                                } catch (e) {
                                  setSheetState(() {
                                    isSaving = false;
                                    formValidationError = 'Failed to update report: $e';
                                  });
                                }
                              },
                        child: isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
                              )
                            : Text('Save Changes',
                                style: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w800, fontSize: 15)),
                      )),
                ]),
        );
      },
    );
  }

  Widget _buildRescueBtn(Sighting s) {
    final uid = _uid;
    final claimed = s.rescueClaimed;
    final claimedByMe =
        claimed && uid != null && s.rescueClaimedBy == uid;
    final canCancel = claimed && (claimedByMe || _isOwner(s));

    // Hide if resolved, already in care, has vet visit, pending verification, awaiting post-vet decision, or if unclaimed and current user is the reporter
    if (s.urgency == 'resolved' ||
        s.isInCare ||
        s.hasVetVisit ||
        s.isVetVisitPending ||
        s.isPendingVerification ||
        s.isAwaitingPostVetDecision ||
        (!claimed && _isOwner(s))) {
      return const SizedBox.shrink();
    }
    final bottomNavPadding = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: BoxDecoration(
          color: _bgWhite,
          boxShadow: [
            BoxShadow(
                color: _navy.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, -4))
          ]),
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, bottomNavPadding > 0 ? bottomNavPadding + 10 : 16),
      child: claimed && !canCancel
          ? Container(
              padding: const EdgeInsets.symmetric(
                  vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                  color: _navy.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16)),
              child: Row(children: [
                Icon(Icons.directions_run,
                    color: _lavender, size: 20),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                      Text('${s.rescueClaimedByName} is on their way!',
                          style: GoogleFonts.nunito(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: _navy)),
                      Text(
                        s.rescueClaimRemainingMinutes > 0
                            ? '⏱️ ${s.rescueClaimRemainingMinutes}m left in arrival window'
                            : 'Arrival window expiring...',
                        style: GoogleFonts.nunito(
                            fontSize: 11,
                            color: _lavender,
                            fontWeight: FontWeight.w700)),
                    ])),
                IconButton(
                  icon: const Icon(Icons.chat_bubble_outline_rounded,
                      color: _lavender, size: 22),
                  onPressed: () {
                    final otherId = s.rescueClaimedBy;
                    final otherName = s.rescueClaimedByName;
                    if (otherId.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CoordinationChatScreen(
                            sighting: s,
                            otherUserId: otherId,
                            otherUserName: otherName,
                            otherUserRole: 'En Route Rescuer',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ]))
          : GestureDetector(
              onTap: canCancel
                  ? () => _cancelRescue(s)
                  : () => _claimRescue(s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: canCancel ? _urgent : _lavender,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: (canCancel ? _urgent : _lavender)
                            .withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                          canCancel
                              ? Icons.cancel_outlined
                              : Icons.directions_run,
                          color: Colors.white,
                          size: 20),
                      const SizedBox(width: 10),
                      Column(children: [
                        Text(
                            canCancel
                                ? (_isOwner(s) && !claimedByMe
                                    ? 'Release Spot for Others'
                                    : 'Cancel My Rescue (${s.rescueClaimRemainingMinutes}m left)')
                                : "I'm on my way",
                            style: GoogleFonts.nunito(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                                color: Colors.white)),
                        Text(
                            canCancel
                                ? (_isOwner(s) && !claimedByMe
                                    ? 'Reopen spot for other rescuers'
                                    : 'Release spot so others can help')
                                : 'Let others know you are heading there (45m window)',
                            style: GoogleFonts.nunito(
                                fontSize: 11,
                                color: Colors.white
                                    .withValues(alpha: 0.8),
                                fontWeight: FontWeight.w600)),
                      ]),
                    ]),
              ),
            ),
    );
  }

  void _showRescuerTrustModal(String uid, String fallbackName) {
    if (uid.isEmpty || uid == 'anon') return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StreamBuilder<UserProfile>(
          stream: FirebaseService.instance.streamUserProfile(uid),
          builder: (context, snapshot) {
            final profile = snapshot.data ??
                UserProfile(
                  uid: uid,
                  displayName: fallbackName,
                  email: '',
                  joinedAt: DateTime.now(),
                );

            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, 32 + MediaQuery.paddingOf(ctx).bottom),
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
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: profile.trustTierColor.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: profile.trustTierColor, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            profile.initials,
                            style: GoogleFonts.nunito(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: profile.trustTierColor,
                            ),
                          ),
                        ),
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
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: _navy,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: profile.trustTierColor
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(profile.trustTierIcon,
                                          size: 12,
                                          color: profile.trustTierColor),
                                      const SizedBox(width: 4),
                                      Text(
                                        profile.trustTierTitle,
                                        style: GoogleFonts.nunito(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                          color: profile.trustTierColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              profile.city,
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
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _lavLight,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        Column(
                          children: [
                            Text(
                              '${profile.trustScore.toStringAsFixed(1)} ★',
                              style: GoogleFonts.nunito(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFFFFA000),
                              ),
                            ),
                            Text('Trust Score',
                                style: GoogleFonts.nunito(
                                    fontSize: 11,
                                    color: _navy.withValues(alpha: 0.6))),
                          ],
                        ),
                        Container(
                            width: 1,
                            height: 28,
                            color: _navy.withValues(alpha: 0.1)),
                        Column(
                          children: [
                            Text(
                              '${profile.successfulRescues}',
                              style: GoogleFonts.nunito(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: const Color(0xFF2E7D32),
                              ),
                            ),
                            Text('Rescues Done',
                                style: GoogleFonts.nunito(
                                    fontSize: 11,
                                    color: _navy.withValues(alpha: 0.6))),
                          ],
                        ),
                        Container(
                            width: 1,
                            height: 28,
                            color: _navy.withValues(alpha: 0.1)),
                        Column(
                          children: [
                            Text(
                              'Lv.${profile.level}',
                              style: GoogleFonts.nunito(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: _lavender,
                              ),
                            ),
                            Text('${profile.totalXp} XP',
                                style: GoogleFonts.nunito(
                                    fontSize: 11,
                                    color: _navy.withValues(alpha: 0.6))),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (profile.bio.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      '"${profile.bio}"',
                      style: GoogleFonts.nunito(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: _navy.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _navy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Close Trust Card',
                          style: GoogleFonts.nunito(
                              fontWeight: FontWeight.w800, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _AllPhotosScreen extends StatefulWidget {
  final List<String> photoUrls;
  const _AllPhotosScreen({required this.photoUrls});
  @override
  State<_AllPhotosScreen> createState() => _AllPhotosScreenState();
}

class _AllPhotosScreenState extends State<_AllPhotosScreen> {
  int _cur = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text('${_cur + 1} / ${widget.photoUrls.length}',
              style: GoogleFonts.nunito(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 16)),
        ),
        body: PageView.builder(
          itemCount: widget.photoUrls.length,
          onPageChanged: (i) => setState(() => _cur = i),
          itemBuilder: (_, i) {
            final url = widget.photoUrls[i];
            return InteractiveViewer(
              child: Center(
                child: PawImage(
                  url: url,
                  fit: BoxFit.contain,
                  placeholder: const Icon(
                    Icons.broken_image,
                    color: Colors.white,
                    size: 60,
                  ),
                ),
              ),
            );
          },
        ),
      );
}
