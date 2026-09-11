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
import 'chat_screen.dart';
import '../widgets/paw_image.dart';

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
  static const Color _needsHelp = Color(0xFFFF7043);
  static const Color _cardBg = Color(0xFFFFFFFF);

  final _aiService = AiValidationService();
  final _picker = ImagePicker();
  final _commentCtrl = TextEditingController();
  final _replyCtrl = TextEditingController();
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

  String? _validateCommentSpam(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return 'Please enter a comment.';
    if (trimmed.length < 2) return 'Comment is too short.';

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

    // 3. Anti-spam: Excessive repeated characters (e.g. 8+ identical consecutive chars)
    final repeatedCharRegex = RegExp(r'(.)\1{7,}');
    if (repeatedCharRegex.hasMatch(trimmed)) {
      return '⚠️ Your comment contains repetitive characters. Please write a meaningful message.';
    }

    return null;
  }

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
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

  Color _sColor(String u) => u == 'communityCare'
      ? const Color(0xFF00897B)
      : (u == 'urgent' ? _urgent : (u == 'resolved' ? _resolved : _needsHelp));
  String _sLabel(String u) => u == 'communityCare'
      ? 'Community Cat'
      : (u == 'urgent' ? 'Urgent' : u == 'resolved' ? 'Resolved' : 'Needs Help');
  IconData _sIcon(String u) => u == 'communityCare'
      ? Icons.pets
      : (u == 'resolved' ? Icons.check_circle : Icons.error);

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

  void _showMore(Sighting s) => showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent, builder: (_) => _moreMenu(s));

  void _showEdit(Sighting s) {
    final tc = TextEditingController(text: s.title);
    final dc = TextEditingController(text: s.description);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _editSheet(s, tc, dc),
      ),
    );
  }

  void _confirmDelete(Sighting s) {
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
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (c2, ss) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('Flag this Sighting',
              style: GoogleFonts.nunito(fontWeight: FontWeight.w800, color: _navy)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: reasons
                .map((r) => RadioListTile<String>(
                      dense: true,
                      title: Text(r,
                          style: GoogleFonts.nunito(
                              fontSize: 13, fontWeight: FontWeight.w600, color: _navy)),
                      value: r,
                      groupValue: sel,
                      activeColor: _lavender,
                      onChanged: (v) => ss(() => sel = v),
                    ))
                .toList(),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: GoogleFonts.nunito(color: _navy))),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await FirebaseService.instance.flagSighting(s.id, sel ?? '');
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

  void _showCommentMenu(Map<String, dynamic> c, String sightingId) {
    final isOwn = _uid != null && c['authorId'] == _uid;
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
                    leading: const Icon(Icons.edit_outlined, color: _lavender),
                    title: Text('Edit',
                        style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w700, color: _navy)),
                    subtitle: Text('Edit your message',
                        style: GoogleFonts.nunito(
                            fontSize: 12, color: _navy.withValues(alpha: 0.5))),
                    onTap: () {
                      Navigator.pop(context);
                      _showEditCommentSheet(c, sightingId);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: _urgent),
                    title: Text('Delete',
                        style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w700, color: _urgent)),
                    subtitle: Text('Mark comment as deleted',
                        style: GoogleFonts.nunito(
                            fontSize: 12, color: _navy.withValues(alpha: 0.5))),
                    onTap: () {
                      Navigator.pop(context);
                      _confirmDeleteComment(c, sightingId);
                    },
                  ),
                ] else ...[
                  ListTile(
                    leading: const Icon(Icons.flag_outlined, color: _urgent),
                    title: Text('Report',
                        style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w700, color: _urgent)),
                    subtitle: Text('Report inappropriate content or spam',
                        style: GoogleFonts.nunito(
                            fontSize: 12, color: _navy.withValues(alpha: 0.5))),
                    onTap: () {
                      Navigator.pop(context);
                      _showReportCommentDialog(c, sightingId);
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

  void _showEditCommentSheet(Map<String, dynamic> c, String sightingId) {
    final editCtrl = TextEditingController(text: c['text'] ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomPadding = MediaQuery.of(ctx).padding.bottom;
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
              Text('Edit Message',
                  style: GoogleFonts.nunito(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _navy)),
              const SizedBox(height: 14),
              TextField(
                controller: editCtrl,
                maxLines: 4,
                maxLength: 400,
                style: GoogleFonts.nunito(
                    fontSize: 14,
                    color: _navy,
                    fontWeight: FontWeight.w600),
                decoration: InputDecoration(
                  hintText: 'Edit your comment...',
                  filled: true,
                  fillColor: _lavLight,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none),
                  counterStyle: GoogleFonts.nunito(
                      fontSize: 11, color: _navy.withValues(alpha: 0.4)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _lavender,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () async {
                    if (editCtrl.text.trim().isEmpty) return;
                    await FirebaseService.instance.editComment(
                      sightingId: sightingId,
                      commentId: c['id'] ?? '',
                      newText: editCtrl.text,
                    );
                    if (mounted) {
                      Navigator.pop(context);
                      _snack('Comment updated!');
                    }
                  },
                  child: Text('Save Changes',
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
}

  void _confirmDeleteComment(Map<String, dynamic> c, String sightingId) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Delete Comment?',
            style: GoogleFonts.nunito(
                fontWeight: FontWeight.w800, color: _navy)),
        content: Text(
            'Your comment will be marked as "(comment deleted)".',
            style: GoogleFonts.nunito(color: _navy.withValues(alpha: 0.65))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.nunito(color: _navy))),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await FirebaseService.instance.deleteComment(
                sightingId: sightingId,
                commentId: c['id'] ?? '',
              );
              if (mounted) _snack('Comment deleted.');
            },
            child: Text('Delete',
                style: GoogleFonts.nunito(
                    color: _urgent, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _showReportCommentDialog(Map<String, dynamic> c, String sightingId) {
    final reasons = [
      'Inappropriate or offensive',
      'Spam or advertising',
      'Harassment or hate speech',
      'Misleading / false information',
      'Other',
    ];
    String? selected = reasons[0];
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text('Report Comment',
              style: GoogleFonts.nunito(
                  fontWeight: FontWeight.w800, color: _navy)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: reasons
                .map((r) => RadioListTile<String>(
                      dense: true,
                      title: Text(r,
                          style: GoogleFonts.nunito(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _navy)),
                      value: r,
                      groupValue: selected,
                      activeColor: _lavender,
                      onChanged: (v) => ss(() => selected = v),
                    ))
                .toList(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.nunito(color: _navy))),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await FirebaseService.instance.flagComment(
                  sightingId: sightingId,
                  commentId: c['id'] ?? '',
                  reason: selected ?? '',
                );
                if (mounted) _snack('Report submitted. Thank you!');
              },
              child: Text('Submit',
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
        final bottomInset = MediaQuery.of(ctx).padding.bottom;
        final maxH = MediaQuery.of(ctx).size.height * 0.85;

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
                                  ? '🌿 Feral Cat TNR Mandate'
                                  : '🩺 Vet Visit Verified!',
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
                  const SizedBox(height: 18),
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
                    const SizedBox(height: 14),
                    if (rescuerId.isNotEmpty && rescuerId != _uid)
                      _buildPostVetOptionTile(
                        icon: Icons.chat_bubble_rounded,
                        iconColor: const Color(0xFF1E88E5),
                        title: '💬 Discuss Release Spot with $rescuerName',
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
                    if (_isVetRescuer(s))
                      _buildPostVetOptionTile(
                        icon: Icons.nature_people_rounded,
                        iconColor: const Color(0xFF00897B),
                        title: '🌿 Confirm Return to Colony / Spot',
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
                      icon: Icons.public_rounded,
                      iconColor: const Color(0xFF1E88E5),
                      title: '🐾 Delegate to $rescuerName (Rescuer in Charge)',
                      subtitle:
                          'Grants custody authority to $rescuerName to decide and log next steps (foster, shelter, or adoption).',
                      badgeText: 'Delegate Power',
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
                    const SizedBox(height: 10),

                    // 2. Take In for Foster Care (Reporter Takes Cat)
                    _buildPostVetOptionTile(
                      icon: Icons.volunteer_activism_rounded,
                      iconColor: const Color(0xFF673AB7),
                      title: '🏡 I Will Take In for Foster Care',
                      subtitle:
                          'Bring cat into your own care for quarantine & recovery. Sets up daily milestone journey.',
                      badgeText: '+150 XP',
                      badgeColor: const Color(0xFF673AB7),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showActionProofSheet('tookIn', s);
                      },
                    ),
                    const SizedBox(height: 10),

                    // 3. Transfer to Shelter
                    _buildPostVetOptionTile(
                      icon: Icons.house_rounded,
                      iconColor: const Color(0xFFE65100),
                      title: '🏛️ Transfer to Animal Shelter',
                      subtitle:
                          'Direct admission to a verified rescue center or shelter.',
                      badgeText: '+120 XP',
                      badgeColor: const Color(0xFFE65100),
                      onTap: () {
                        Navigator.pop(ctx);
                        _showActionProofSheet('sheltered', s);
                      },
                    ),
                    const SizedBox(height: 10),

                    // 4. Discuss Next Steps with Rescuer (Coordinate before deciding)
                    if (rescuerId.isNotEmpty && rescuerId != _uid)
                      _buildPostVetOptionTile(
                        icon: Icons.chat_bubble_rounded,
                        iconColor: const Color(0xFF1E88E5),
                        title: '💬 Discuss Next Steps with $rescuerName',
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

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (bCtx) => StatefulBuilder(
        builder: (context, setSheetState) {
          final canSubmit = proofFile != null && !isSubmitting;
          final bottomPadding = MediaQuery.of(context).viewInsets.bottom +
              MediaQuery.of(context).padding.bottom +
              32;

          Future<void> pickProof(ImageSource src) async {
            try {
              final picker = ImagePicker();
              final picked = await picker.pickImage(
                source: src,
                maxWidth: 1200,
                maxHeight: 1200,
                imageQuality: 80,
              );
              if (picked != null) {
                setSheetState(() => proofFile = File(picked.path));
              }
            } catch (e) {
              _snack('Could not pick photo: $e');
            }
          }

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.90,
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
                  if (proofFile != null)
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
                            onTap: () =>
                                setSheetState(() => proofFile = null),
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
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => pickProof(ImageSource.camera),
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
                    maxLines: 2,
                    style: GoogleFonts.nunito(fontSize: 13, color: _navy),
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
                  const SizedBox(height: 20),

                  // Submit Button Guidance (when photo is missing)
                  if (proofFile == null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.lock_rounded,
                              size: 16, color: Colors.amber.shade900),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Release photo proof is required above to enable this button.',
                              style: GoogleFonts.nunito(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFFE65100),
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
                        backgroundColor: const Color(0xFF00897B),
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade300,
                        disabledForegroundColor: Colors.grey.shade500,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      onPressed: !canSubmit
                          ? null
                          : () async {
                              setSheetState(() => isSubmitting = true);
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
                    height: MediaQuery.of(context).padding.bottom > 0
                        ? MediaQuery.of(context).padding.bottom + 20
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
    String selectedTemp = s.temperament ?? 'feral';
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
                  {
                    'key': 'feral',
                    'label': '🌿 Feral / Colony Adult (Mandatory TNR)',
                    'desc':
                        'Unsocialized to humans. Cannot be adopted indoors; must be safely returned to colony.',
                    'color': const Color(0xFF00897B),
                  },
                  {
                    'key': 'shy',
                    'label': '🐾 Shy / Timid Stray',
                    'desc':
                        'Cautious but socializable indoors through quiet foster care.',
                    'color': const Color(0xFF1E88E5),
                  },
                  {
                    'key': 'friendly',
                    'label': '💖 Friendly Pet (Adoptable)',
                    'desc':
                        'Approachable and gentle. Suitable for indoor home adoption.',
                    'color': const Color(0xFF9C27B0),
                  },
                  {
                    'key': 'kitten',
                    'label': '🍼 Kitten (Under 4 Months)',
                    'desc':
                        'Young kitten. Highly socializable indoors, requires specialized foster care, nursing, or adoption.',
                    'color': const Color(0xFFE91E63),
                  },
                ].map((opt) {
                  final key = opt['key'] as String;
                  final label = opt['label'] as String;
                  final desc = opt['desc'] as String;
                  final color = opt['color'] as Color;
                  final isSelected = selectedTemp == key;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => setDlgState(() => selectedTemp = key),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color.withValues(alpha: 0.1)
                              : _lavLight.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? color
                                : _navy.withValues(alpha: 0.15),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 18,
                              color: isSelected ? color : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label,
                                    style: GoogleFonts.nunito(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                      color: isSelected ? color : _navy,
                                    ),
                                  ),
                                  Text(
                                    desc,
                                    style: GoogleFonts.nunito(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                      color: _navy.withValues(alpha: 0.65),
                                    ),
                                  ),
                                ],
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
                        ? '🌿 Feral / Colony Adult'
                        : (selectedTemp == 'friendly'
                            ? '💖 Friendly Pet'
                            : '🐾 Shy Stray');
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
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required String badgeText,
    required Color badgeColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: iconColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 22),
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
                          title,
                          style: GoogleFonts.nunito(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badgeText,
                          style: GoogleFonts.nunito(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                            color: badgeColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.nunito(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: _navy.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded,
                color: _navy.withValues(alpha: 0.35), size: 20),
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
    bool isAnonymous = _isAnon;
    final isShelteredAction = action == 'sheltered';
    final isTookInAction = action == 'tookIn' || action == 'holding';
    final isOwner = _isOwner(s);
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
    bool isLocatingShelter = false;
    final shelterNameCtrl = TextEditingController();
    final shelterAddressCtrl = TextEditingController(text: isShelteredAction ? s.effectiveLocationAddress : '');
    final noteCtrl = TextEditingController();

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
          if (isTookInAction && !isOwner) {
            for (int d = 1; d <= planDurationDays; d++) {
              if (getDayCtrl(d, planDurationDays).text.trim().isEmpty) {
                areAllMilestonesFilled = false;
                break;
              }
            }
          }

          final canSubmit = proofFile != null &&
              scanResult != null &&
              scanResult!.isValid &&
              !isScanning &&
              !isSubmitting &&
              (!isShelteredAction || shelterNameCtrl.text.trim().isNotEmpty) &&
              (!isTookInAction ||
                  isOwner ||
                  ((!isCustomGoal || customGoalCtrl.text.trim().isNotEmpty) &&
                      areAllMilestonesFilled));

          final bottomPadding = MediaQuery.of(ctx).padding.bottom;
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
                                isTookInAction && !isOwner
                                    ? 'Request Foster Custody'
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
                                    : (isTookInAction && !isOwner
                                        ? 'Requires reporter confirmation for animal welfare (+150 XP)'
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
                    if (isTookInAction && !isOwner) ...[
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
                            const Icon(Icons.handshake_outlined,
                                color: Color(0xFF673AB7), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Foster Handshake: Taking this cat into foster care will send your Custom Care Plan and Trust Card to the reporter for approval.',
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
                                    color: _navy.withValues(alpha: 0.2)),
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
                                    color: _navy.withValues(alpha: 0.2)),
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
                      Text(
                        'Shelter / Organization Name *',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: shelterNameCtrl,
                        onChanged: (_) => setSheetState(() {}),
                        style: GoogleFonts.nunito(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _navy),
                        decoration: InputDecoration(
                          hintText:
                              'e.g. Pejaten Animal Shelter, ASPERA, etc.',
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
                      Text(
                        'Shelter Address / Contact (Optional)',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: shelterAddressCtrl,
                        style: GoogleFonts.nunito(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _navy),
                        decoration: InputDecoration(
                          hintText:
                              'e.g. Jl. Pejaten Barat No. 23 (Open for adoption)',
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
                      const SizedBox(height: 10),
                      Container(
                        height: 140,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: _navy.withValues(alpha: 0.15)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Stack(
                            children: [
                              FlutterMap(
                                options: MapOptions(
                                  initialCenter:
                                      ll.LatLng(shelterLat, shelterLng),
                                  initialZoom: 16.0,
                                  onTap: (tapPos, point) async {
                                    shelterLat = point.latitude;
                                    shelterLng = point.longitude;
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
                                        width: 38,
                                        height: 38,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF673AB7),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: Colors.white, width: 2),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.25),
                                                blurRadius: 6,
                                              ),
                                            ],
                                          ),
                                          child: const Center(
                                            child: Icon(Icons.apartment,
                                                size: 18,
                                                color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (isLocatingShelter)
                                Container(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      color: Color(0xFF673AB7),
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              Positioned(
                                bottom: 6,
                                left: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Tap map to set shelter location',
                                    style: GoogleFonts.nunito(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
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
                      'Custom Note / Details (Optional)',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: noteCtrl,
                      maxLength: 150,
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _navy,
                      ),
                      decoration: InputDecoration(
                        hintText: isShelteredAction
                            ? 'e.g. Admitted safely into intake quarantine kennel #4'
                            : 'e.g. Fed 2 cans of cat food near the alleyway',
                        hintStyle: GoogleFonts.nunito(
                            fontSize: 12,
                            color: _navy.withValues(alpha: 0.35)),
                        filled: true,
                        fillColor: _lavLight,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        counterStyle: GoogleFonts.nunito(
                            fontSize: 10,
                            color: _navy.withValues(alpha: 0.4)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: () =>
                          setSheetState(() => isAnonymous = !isAnonymous),
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color:
                                  isAnonymous ? _lavender : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isAnonymous
                                    ? _lavender
                                    : _navy.withValues(alpha: 0.25),
                              ),
                            ),
                            child: isAnonymous
                                ? const Icon(Icons.check,
                                    size: 12, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Post anonymously to community feed',
                            style: GoogleFonts.nunito(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _navy.withValues(alpha: 0.65),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isTookInAction && !isOwner && !areAllMilestonesFilled) ...[
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
                                'Please enter a title for all $planDurationDays days to submit your Foster Care Plan.',
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
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              canSubmit ? col : Colors.grey.shade300,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: canSubmit ? 2 : 0,
                        ),
                        onPressed: canSubmit
                            ? () async {
                                setSheetState(() => isSubmitting = true);
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
                                    anonymous: isAnonymous,
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
                                  _snack('Failed to submit: $e');
                                }
                              }
                            : null,
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

  void _showRoamingUpdateSheet(Sighting s) {
    if (s.isVetVisitPending) {
      _snack('⏳ Vet visit verification is pending. Actions are currently locked.');
      return;
    }
    if (s.isAwaitingPostVetDecision) {
      if (!_isVetRescuer(s) && !_isOwner(s) && !s.isRescuerCustodyDelegated) {
        _snack(
            '⏳ ${s.lastVetRescuerName?.isNotEmpty == true ? s.lastVetRescuerName : "The rescuer"} currently has custody of this cat after vet care.');
        return;
      }
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomPadding = MediaQuery.of(ctx).padding.bottom;
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
                onTap: () {
                  Navigator.pop(ctx);
                  _showActionProofSheet('stillHere', s);
                },
              ),
              const SizedBox(height: 10),
              _buildRoamingOptionTile(
                icon: Icons.edit_location_alt_outlined,
                color: const Color(0xFFFF9800),
                title: '📍 Moved Nearby (Update Location)',
                subtitle: 'Cat has moved to a nearby street, alley, or building',
                xpTag: '+25 XP',
                onTap: () {
                  Navigator.pop(ctx);
                  _showRelocationSheet(s);
                },
              ),
              const SizedBox(height: 10),
              _buildRoamingOptionTile(
                icon: Icons.search_off_outlined,
                color: const Color(0xFF78909C),
                title: '🔍 Checked: Cat Not Here Right Now',
                subtitle: 'Visited the area but could not find the cat',
                xpTag: '+10 XP',
                onTap: () {
                  Navigator.pop(ctx);
                  _showNotHereDialog(s);
                },
              ),
            ],
          ),
        ),
      );
    },
  );
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

  void _showRelocationSheet(Sighting s) async {
    if (!await _ensureNoConflictingRescueTrip(s)) return;
    if (!await _ensureNoConflictingVetCare(s)) return;
    File? proofFile;
    bool isScanning = false;
    CatValidationResult? scanResult;
    bool isSubmitting = false;
    bool isLocating = true;
    double newLat = s.effectiveLatitude;
    double newLng = s.effectiveLongitude;
    String newAddress = s.effectiveLocationAddress;
    final noteCtrl = TextEditingController();
    final addressCtrl = TextEditingController(text: newAddress);

    LocationService().getCurrentUserLocation().then((res) {
      newLat = res.latitude;
      newLng = res.longitude;
      newAddress = res.formattedAddress;
      addressCtrl.text = newAddress;
      isLocating = false;
    }).catchError((_) {
      isLocating = false;
    });

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

          final canSubmit = proofFile != null &&
              scanResult?.isCat == true &&
              !isScanning &&
              !isSubmitting;

          final bottomPadding = MediaQuery.of(ctx).padding.bottom;
          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
                      'New Location Address / Landmark',
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: addressCtrl,
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _navy,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: _lavLight,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        suffixIcon: isLocating
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: _lavender),
                                ),
                              )
                            : IconButton(
                                icon: const Icon(Icons.my_location,
                                    color: _lavender, size: 18),
                                onPressed: () async {
                                  setSheetState(() => isLocating = true);
                                  final res = await LocationService()
                                      .getCurrentUserLocation();
                                  newLat = res.latitude;
                                  newLng = res.longitude;
                                  newAddress = res.formattedAddress;
                                  addressCtrl.text = newAddress;
                                  setSheetState(() => isLocating = false);
                                },
                              ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 150,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: _navy.withValues(alpha: 0.15)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(
                          children: [
                            FlutterMap(
                              options: MapOptions(
                                initialCenter: ll.LatLng(newLat, newLng),
                                initialZoom: 16.0,
                                onTap: (tapPos, point) async {
                                  newLat = point.latitude;
                                  newLng = point.longitude;
                                  setSheetState(() => isLocating = true);
                                  final addr = await LocationService()
                                      .getAddressFromCoordinates(
                                          point.latitude, point.longitude);
                                  newAddress = addr;
                                  addressCtrl.text = newAddress;
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
                                      width: 38,
                                      height: 38,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFF9800),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: Colors.white, width: 2),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black
                                                  .withValues(alpha: 0.25),
                                              blurRadius: 6,
                                            ),
                                          ],
                                        ),
                                        child: const Center(
                                          child: Icon(Icons.pets,
                                              size: 18, color: Colors.white),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Positioned(
                              bottom: 6,
                              left: 6,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Tap map to relocate pin',
                                  style: GoogleFonts.nunito(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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
                    if (proofFile == null)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                side: BorderSide(
                                    color: _navy.withValues(alpha: 0.2)),
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
                                    color: _navy.withValues(alpha: 0.2)),
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
                      )
                    else
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
                      'Roam Note (Optional)',
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: noteCtrl,
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
                          borderSide: BorderSide.none,
                        ),
                        counterStyle: GoogleFonts.nunito(
                            fontSize: 10, color: _navy.withValues(alpha: 0.4)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: canSubmit
                              ? const Color(0xFFFF9800)
                              : Colors.grey.shade300,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: canSubmit
                            ? () async {
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
                                  _snack('Failed to update: $e');
                                }
                              }
                            : null,
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
  }

  void _showNotHereDialog(Sighting s) async {
    if (!await _ensureNoConflictingRescueTrip(s)) return;
    if (!await _ensureNoConflictingVetCare(s)) return;
    final noteCtrl = TextEditingController();
    String selectedReason = 'roaming'; // 'roaming' or 'helpedOffline'
    final isOwner = _isOwner(s);

    if (!mounted) return;
    showDialog(
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
                  'Details or Note (optional):',
                  style: GoogleFonts.nunito(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: _navy.withValues(alpha: 0.7)),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: noteCtrl,
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
      stream: FirebaseService.instance.streamSightingById(widget.sighting.id),
      builder: (context, snap) {
        final s = snap.data ?? widget.sighting;
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
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (s.temperament == 'feral')
                                    _traitChip('🌿 Feral / Colony Adult',
                                        const Color(0xFF00897B)),
                                  if (s.temperament == 'friendly')
                                    _traitChip('😻 Friendly Pet (Adoptable)',
                                        const Color(0xFF9C27B0)),
                                  if (s.temperament == 'shy')
                                    _traitChip('🙈 Shy / Timid Stray',
                                        const Color(0xFF1E88E5)),
                                  if (s.temperament == 'kitten')
                                    _traitChip('🍼 Kitten (Under 4 Months)',
                                        const Color(0xFFE91E63)),
                                  if (s.hasEarTip)
                                    _traitChip('✂️ Ear-Tipped (TNR Fixed)',
                                        const Color(0xFF2E7D32)),
                                  if (canEditTemperament)
                                    InkWell(
                                      onTap: () =>
                                          _showUpdateCatTemperamentDialog(s),
                                      borderRadius: BorderRadius.circular(20),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF673AB7)
                                              .withValues(alpha: 0.08),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                            color: const Color(0xFF673AB7)
                                                .withValues(alpha: 0.3),
                                            width: 0.8,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.edit_rounded,
                                                size: 11,
                                                color: Color(0xFF673AB7)),
                                            const SizedBox(width: 3),
                                            Text(
                                              s.temperament != null
                                                  ? 'Change Diagnosis'
                                                  : '+ Add Vet Diagnosis',
                                              style: GoogleFonts.nunito(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w800,
                                                color: const Color(0xFF673AB7),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
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
                          ] else if (s.urgency != 'resolved') ...[
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
                                MediaQuery.of(context).padding.bottom,
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
          Positioned(
              top: kToolbarHeight + MediaQuery.of(context).padding.top - 8,
              left: 16,
              child: s.isTnrCommunityCat
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                          color: const Color(0xFF00897B),
                          borderRadius: BorderRadius.circular(10)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.pets, size: 12, color: Colors.white),
                        const SizedBox(width: 5),
                        Text('Community Cat',
                            style: GoogleFonts.nunito(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ]),
                    )
                  : (s.isOpenForAdoption || s.category == 'Needs Home')
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                              color: const Color(0xFF9C27B0),
                              borderRadius: BorderRadius.circular(10)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.home_outlined, size: 12, color: Colors.white),
                            const SizedBox(width: 5),
                            Text('Needs Home',
                                style: GoogleFonts.nunito(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white)),
                          ]),
                        )
                      : s.isInCare
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                  color: const Color(0xFF673AB7),
                                  borderRadius: BorderRadius.circular(10)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(s.careIcon, size: 12, color: Colors.white),
                                const SizedBox(width: 5),
                                Text(s.careLabel,
                                    style: GoogleFonts.nunito(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white)),
                              ]),
                            )
                          : _badge(s.urgency)),
          if (has && photos.length > 1)
            Positioned(
              top: kToolbarHeight + MediaQuery.of(context).padding.top - 8,
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

  Widget _badge(String u) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: _sColor(u), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(_sIcon(u), size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(_sLabel(u),
              style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white)),
        ]),
      );

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

  Widget _traitChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: GoogleFonts.nunito(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _buildCategoryBadge(Sighting s) {
    Color col;
    IconData icon;
    String label;
    String subtitle;

    final cat = s.category;
    if (cat == 'Feral / Colony Cat') {
      col = const Color(0xFF00897B);
      icon = Icons.nature_people_rounded;
      label = 'Feral / Colony Cat (TNR)';
      subtitle = '🌿 Wild Adult • Outdoor Colony Care';
    } else if (s.isTnrCommunityCat || cat == 'Community Cat' || cat == 'Community Care') {
      col = const Color(0xFF00897B);
      icon = Icons.pets;
      label = 'Community Cat (TNR)';
      subtitle = '🌿 Sterilized & Under Community Care';
    } else if (cat == 'Urgent Rescue' || cat == 'Trapped') {
      col = const Color(0xFFFF5722);
      icon = Icons.warning_amber_rounded;
      label = 'Trapped / In Danger';
      subtitle = '🎯 One-Time Extraction Task';
    } else if (cat == 'Injured') {
      col = _urgent;
      icon = Icons.healing_outlined;
      label = 'Injured / Sick';
      subtitle = '🩺 Medical & Vet Attention Needed';
    } else if (cat == 'Kitten') {
      col = const Color(0xFFE91E63);
      icon = Icons.pets;
      label = 'Vulnerable Kitten(s)';
      subtitle = '🍼 Needs Safe Foster or Care';
    } else if (cat == 'Needs Foster' || cat == 'Needs Home' || cat == 'Rehomed') {
      col = const Color(0xFF9C27B0);
      icon = Icons.home_outlined;
      label = 'Needs Foster / Adopter';
      subtitle = '🏡 Looking for Temporary/Permanent Home';
    } else if (cat == 'Feeding Spot' || cat == 'Stray' || cat == 'Stray Cat') {
      col = _lavender;
      icon = Icons.restaurant_outlined;
      label = 'Stray / Feeding Spot';
      subtitle = '🍲 Ongoing Community Care & Food';
    } else if (cat == 'Needs Vet' || cat == 'Vet Visit') {
      col = _urgent;
      icon = Icons.medical_services_outlined;
      label = 'Vet Treatment Required';
      subtitle = '🩺 Needs Clinic Visit';
    } else if (cat == 'Resolved') {
      col = _resolved;
      icon = Icons.check_circle_outline;
      label = 'Rescue Resolved';
      subtitle = '🎉 Cat is safe and accounted for';
    } else {
      col = _lavender;
      icon = Icons.remove_red_eye_outlined;
      label = cat.isNotEmpty ? cat : 'Spotted Stray';
      subtitle = 'Community Cat Sighting';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: col.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: col.withValues(alpha: 0.25), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: col.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: col, size: 16),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: col,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: col.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        s.isOneTimeTask ? 'ONE-TIME' : 'ONGOING',
                        style: GoogleFonts.nunito(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: col,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  subtitle,
                  style: GoogleFonts.nunito(
                    fontSize: 11,
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
              color: _sColor(s.urgency),
              borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_sIcon(s.urgency), size: 12, color: Colors.white),
            const SizedBox(width: 4),
            Text(_sLabel(s.urgency),
                style: GoogleFonts.nunito(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ]),
        ),
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, 28 + MediaQuery.of(ctx).padding.bottom),
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
                    'Feedback / Endorsement Note',
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: commentCtrl,
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
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                              setSheetState(() => isSubmitting = true);
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
                                    () => isSubmitting = false);
                                _snack('Error submitting review: $e');
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _lavender.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child:
                    Icon(Icons.timeline_rounded, color: _lavender, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Care Progress Lifecycle',
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: _navy,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'In care with ${s.careTakerName ?? "Caretaker"} • ${s.daysInCare} ${s.daysInCare == 1 ? "day" : "days"} in care',
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
    bool isSubmitting = false;
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
            final picked = await _picker.pickImage(
              source: source,
              maxWidth: 1200,
              maxHeight: 1200,
              imageQuality: 85,
            );
            if (picked == null) return;
            setSheetState(() => proofFile = File(picked.path));
          }

          final xp = milestoneDay == 1
              ? 30
              : (milestoneDay == s.effectiveMilestoneDays.last ? 60 : 25);

          final isCustomFilled = !isCustomCondition ||
              customConditionCtrl.text.trim().isNotEmpty;
          final canSubmit =
              !isSubmitting && proofFile != null && isCustomFilled;

          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.fromLTRB(
                  20, 16, 20, 28 + MediaQuery.of(ctx).padding.bottom),
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
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'Care Notes / Medical Update',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: noteCtrl,
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
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Photo Proof of Cat (Mandatory)',
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
                    if (proofFile != null)
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
                              onTap: () =>
                                   setSheetState(() => proofFile = null),
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
                      )
                    else
                      Row(
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _lavender,
                              side: BorderSide(
                                  color:
                                      _lavender.withValues(alpha: 0.5)),
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
                                  color: _navy.withValues(alpha: 0.2)),
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
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              canSubmit ? _lavender : Colors.grey.shade300,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: canSubmit
                            ? () async {
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
                                  );
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  _snack(
                                      'Day $milestoneDay Check-In verified! +$earned XP awarded 🐾');
                                } catch (e) {
                                  setSheetState(
                                      () => isSubmitting = false);
                                  _snack('Failed to submit check-in: $e');
                                }
                              }
                            : null,
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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFF57C00).withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: const Color(0xFFF57C00).withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF57C00).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.celebration_rounded,
                      color: Color(0xFFF57C00), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isOwner(s)
                            ? '🎉 Your Vet Visit Was Verified! (+100 XP)'
                            : '🎉 Placement Delegated to You (+100 XP)',
                        style: GoogleFonts.nunito(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w900,
                          color: const Color(0xFFE65100),
                        ),
                      ),
                      Text(
                        _isOwner(s)
                            ? 'Since you have physical custody of the cat, select your next action:'
                            : '${s.reporterName.isNotEmpty ? s.reporterName : "The reporter"} placed you in charge of placement. Select your next action:',
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
                        const Icon(Icons.volunteer_activism_rounded,
                            size: 13, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          '🏡 Foster at My Place (+150 XP)',
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
                        const Icon(Icons.house_rounded,
                            size: 13, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          '🏛️ Transfer to Shelter (+120 XP)',
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
                  onTap: () => _showOpenForAdoptionSheet(s),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.volunteer_activism_rounded,
                            size: 13, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          '🐾 Open for Adoption (+100 XP)',
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
            final picked = await _picker.pickImage(
              source: source,
              maxWidth: 1200,
              maxHeight: 1200,
              imageQuality: 85,
            );
            if (picked == null) return;
            setSheetState(() => showcaseFile = File(picked.path));
          }

          final bottomPadding = MediaQuery.of(ctx).padding.bottom;

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.88,
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
                          borderSide: BorderSide(color: _navy.withValues(alpha: 0.15)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: _navy.withValues(alpha: 0.15)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF2E7D32)),
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
                        hintStyle: GoogleFonts.nunito(
                          fontSize: 12.5,
                          color: _navy.withValues(alpha: 0.4),
                        ),
                        prefixIcon: const Icon(Icons.contact_phone_outlined, size: 18, color: Color(0xFF2E7D32)),
                        filled: true,
                        fillColor: _bgWhite,
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: _navy.withValues(alpha: 0.15)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: _navy.withValues(alpha: 0.15)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF2E7D32)),
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
                      'Adoption Story & Personality Notes',
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: noteCtrl,
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
                          borderSide: BorderSide(color: _navy.withValues(alpha: 0.15)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: _navy.withValues(alpha: 0.15)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFF2E7D32)),
                        ),
                      ),
                    ),
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
                              onTap: () => setSheetState(() => showcaseFile = null),
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
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: const Color(0xFF2E7D32).withValues(alpha: 0.5),
                                  width: 1.2,
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
                                    color: const Color(0xFF2E7D32),
                                  )),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                  color: const Color(0xFF2E7D32).withValues(alpha: 0.5),
                                  width: 1.2,
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
                                    color: const Color(0xFF2E7D32),
                                  )),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
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
                                if (showcaseFile == null) {
                                  _snack('Please take or upload a showcase photo. It is mandatory for the Adoption Showcase profile.');
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
    bool isSubmitting = false;
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> pickPhoto(ImageSource source) async {
            final picked = await _picker.pickImage(
              source: source,
              maxWidth: 1200,
              maxHeight: 1200,
              imageQuality: 85,
            );
            if (picked == null) return;
            setSheetState(() => proofFile = File(picked.path));
          }

          final bottomPadding = MediaQuery.of(ctx).padding.bottom;
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
          final canSubmit = proofFile != null &&
              (!isSheltered || shelterNameCtrl.text.trim().isNotEmpty);

          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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
                        Text(
                          'Shelter / Organization Name *',
                          style: GoogleFonts.nunito(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: shelterNameCtrl,
                          onChanged: (_) => setSheetState(() {}),
                          style: GoogleFonts.nunito(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _navy),
                          decoration: InputDecoration(
                            hintText:
                                'e.g. Pejaten Animal Shelter, ASPERA, etc.',
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
                      ],
                      Text(
                        outcomeAction == 'returnedToSpot'
                            ? 'Colony Release Spot / Feeding Station Address *'
                            : 'Shelter Address / Contact (Optional)',
                        style: GoogleFonts.nunito(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: shelterAddressCtrl,
                        style: GoogleFonts.nunito(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _navy),
                        decoration: InputDecoration(
                          hintText: outcomeAction == 'returnedToSpot'
                              ? 'e.g. Near Taman Menteng Banyan Tree / RT 04 feeding spot'
                              : 'e.g. Jl. Pejaten Barat No. 23 (Open for adoption)',
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
                      const SizedBox(height: 10),
                      Container(
                        height: 140,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: _navy.withValues(alpha: 0.15)),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Stack(
                            children: [
                              FlutterMap(
                                options: MapOptions(
                                  initialCenter:
                                      ll.LatLng(shelterLat, shelterLng),
                                  initialZoom: 16.0,
                                  onTap: (tapPos, point) async {
                                    shelterLat = point.latitude;
                                    shelterLng = point.longitude;
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
                                        width: 38,
                                        height: 38,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: outcomeAction == 'returnedToSpot'
                                                ? const Color(0xFF00897B)
                                                : const Color(0xFF673AB7),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: Colors.white, width: 2),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black
                                                    .withValues(alpha: 0.25),
                                                blurRadius: 6,
                                              ),
                                            ],
                                          ),
                                          child: Center(
                                            child: Icon(
                                                outcomeAction == 'returnedToSpot'
                                                    ? Icons.park_rounded
                                                    : Icons.apartment,
                                                size: 18,
                                                color: Colors.white),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              if (isLocatingShelter)
                                Container(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      color: outcomeAction == 'returnedToSpot'
                                          ? const Color(0xFF00897B)
                                          : const Color(0xFF673AB7),
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              Positioned(
                                bottom: 6,
                                left: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    outcomeAction == 'returnedToSpot'
                                        ? 'Tap map to place colony release pin'
                                        : 'Tap map to set shelter location',
                                    style: GoogleFonts.nunito(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                    Text(
                      'Outcome Note / Details',
                      style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w800, color: _navy),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: noteCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: _lavLight,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Outcome Photo Proof (Required)',
                      style: GoogleFonts.nunito(fontSize: 13, fontWeight: FontWeight.w800, color: _navy),
                    ),
                    const SizedBox(height: 8),
                    if (proofFile != null)
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
                              onTap: () => setSheetState(() => proofFile = null),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                child: const Icon(Icons.close, size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => pickPhoto(ImageSource.camera),
                              icon: Icon(Icons.camera_alt, size: 16, color: primaryCol),
                              label: Text('Camera', style: GoogleFonts.nunito(fontWeight: FontWeight.w800, color: _navy, fontSize: 12)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => pickPhoto(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library, size: 16, color: _lavender),
                              label: Text('Gallery', style: GoogleFonts.nunito(fontWeight: FontWeight.w800, color: _navy, fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: canSubmit ? primaryCol : Colors.grey.shade300,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: (isSubmitting || !canSubmit)
                            ? null
                            : () async {
                                if (isSheltered && shelterNameCtrl.text.trim().isEmpty) {
                                  _snack('Please enter the shelter or organization name.');
                                  return;
                                }
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
          final bottomPadding = MediaQuery.of(ctx).padding.bottom;
          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final bottomPadding = MediaQuery.of(ctx).viewInsets.bottom;

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(
                20, 16, 20, bottomPadding > 0 ? bottomPadding + 16 : 28),
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
                              'Adoption Application 🏡🐾',
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
                        borderSide:
                            BorderSide(color: _navy.withValues(alpha: 0.15)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: _navy.withValues(alpha: 0.15)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Color(0xFF2E7D32)),
                      ),
                    ),
                  ),
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
                        borderSide:
                            BorderSide(color: _navy.withValues(alpha: 0.15)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: _navy.withValues(alpha: 0.15)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: Color(0xFF2E7D32)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
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
                              final msg = noteCtrl.text.trim();
                              if (msg.isEmpty) {
                                _snack(
                                    'Please share a brief note about your interest in adopting.');
                                return;
                              }
                              setSheetState(() => isSubmitting = true);
                              try {
                                await FirebaseService.instance
                                    .submitAdoptionApplication(
                                  sightingId: s.id,
                                  message: msg,
                                  contactPhone: contactCtrl.text.trim(),
                                );
                                if (ctx.mounted) Navigator.pop(ctx);
                                _snack(
                                    '🏡 Adoption application submitted! Awaiting confirmation from $otherName.');
                              } catch (e) {
                                setSheetState(() => isSubmitting = false);
                                _snack('Failed to submit application: $e');
                              }
                            },
                      child: isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          : Text(
                              'Send Adoption Request 🏡',
                              style: GoogleFonts.nunito(
                                  fontWeight: FontWeight.w900, fontSize: 13.5),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF2E7D32).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.volunteer_activism_rounded,
                    size: 16, color: Color(0xFF2E7D32)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Adoption Showcase Profile',
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF2E7D32),
                      ),
                    ),
                    Text(
                      'Facility: $facilityName',
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        color: _navy.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (isCaretaker)
                GestureDetector(
                  onTap: () => _showEditHealthTagsSheet(s),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.edit_note_rounded,
                            size: 14, color: Color(0xFF2E7D32)),
                        const SizedBox(width: 3),
                        Text(
                          'Edit Badges',
                          style: GoogleFonts.nunito(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF2E7D32),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (s.healthTags.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: s.healthTags.map((tag) {
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    tag,
                    style: GoogleFonts.nunito(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF2E7D32),
                    ),
                  ),
                );
              }).toList(),
            )
          else
            Text(
              'Health Check: Verified under care supervision',
              style: GoogleFonts.nunito(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: _navy.withValues(alpha: 0.6),
              ),
            ),
          if (isCaretaker) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65100),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                onPressed: () => _showActionProofSheet('sheltered', s),
                icon: const Icon(Icons.house_rounded, size: 15),
                label: Text(
                  '🏛️ Transfer to Shelter Instead (+120 XP)',
                  style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 10),
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
                      '💬 Chat Caretaker',
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
                      '🏡 Request to Adopt',
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
                child: Icon(s.careIcon,
                    color: const Color(0xFF673AB7), size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cat is Off-Street (${s.careLabel})',
                      style: GoogleFonts.nunito(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    Text(
                      'In active care with ${s.careTakerName?.isNotEmpty == true ? s.careTakerName : "a caregiver"}. Street visits & check-ins are paused.',
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        color: _navy.withValues(alpha: 0.65),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isCaretaker) ...[
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
            const SizedBox(height: 8),
            if (s.isFeral) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
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
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00897B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => _showOutcomeConfirmationRequestSheet(
                          'returnedToSpot', s),
                      icon: const Icon(Icons.nature_people_rounded, size: 16),
                      label: Text(
                        'Return to Colony / Spot (TNR)',
                        style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w800, fontSize: 11.5),
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (s.isOpenForAdoption) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
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
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _resolved,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () =>
                          _showOutcomeConfirmationRequestSheet('rehomed', s),
                      icon: const Icon(Icons.celebration, size: 15),
                      label: Text(
                        'Confirm Rehomed (+200 XP)',
                        style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w800, fontSize: 11),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF673AB7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () =>
                          _showOutcomeConfirmationRequestSheet('sheltered', s),
                      icon: const Icon(Icons.house, size: 14),
                      label: Text(
                        'Sheltered (+120 XP)',
                        style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w800, fontSize: 10.5),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: areOutcomesUnlocked
                            ? const Color(0xFFE65100)
                            : Colors.grey.shade300,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: areOutcomesUnlocked
                          ? () => _showOpenForAdoptionSheet(s)
                          : () => _snack(
                              'Complete all care checkpoints first to unlock adoption! 🐾'),
                      icon: Icon(
                          areOutcomesUnlocked
                              ? Icons.volunteer_activism_rounded
                              : Icons.lock_rounded,
                          size: 14),
                      label: Text(
                        'Open for Adoption (+100 XP)',
                        style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w800, fontSize: 10.5),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: areOutcomesUnlocked
                            ? _resolved
                            : Colors.grey.shade300,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: areOutcomesUnlocked
                          ? () => _showOutcomeConfirmationRequestSheet(
                              'rehomed', s)
                          : () => _snack(
                              'Complete all care checkpoints first to unlock permanent rehoming! 🐾'),
                      icon: Icon(
                          areOutcomesUnlocked
                              ? Icons.celebration
                              : Icons.lock_rounded,
                          size: 14),
                      label: Text(
                        'Already Rehomed (+200 XP)',
                        style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w800, fontSize: 10.5),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: areOutcomesUnlocked
                            ? const Color(0xFF673AB7)
                            : Colors.grey.shade300,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: areOutcomesUnlocked
                          ? () => _showOutcomeConfirmationRequestSheet(
                              'sheltered', s)
                          : () => _snack(
                              'Complete all care checkpoints first to unlock sheltering! 🐾'),
                      icon: Icon(
                          areOutcomesUnlocked
                              ? Icons.house
                              : Icons.lock_rounded,
                          size: 14),
                      label: Text(
                        'Sheltered (+120 XP)',
                        style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w800, fontSize: 10.5),
                      ),
                    ),
                  ),
                ],
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
        'sub': 'Took to vet'
      },
      {
        'key': 'tookIn',
        'icon': Icons.home,
        'label': 'Took In',
        'xp': '+150 XP',
        'sub': 'Taking care'
      },
      {
        'key': 'sheltered',
        'icon': Icons.house,
        'label': 'Sheltered',
        'xp': '+120 XP',
        'sub': 'In shelter'
      },
      {
        'key': 'fed',
        'icon': Icons.restaurant,
        'label': 'Fed',
        'xp': '+30 XP',
        'sub': 'Gave food'
      },
      {
        'key': 'roaming',
        'icon': Icons.edit_location_alt_outlined,
        'label': 'Still Here / Move',
        'xp': '+15-25 XP',
        'sub': 'Update spot'
      },
    ];

    List<Map<String, Object>> acts;
    final cat = s.category;
    final isPriorityVet = s.isMedicalOrTriagePriority && !s.hasVetVisit;

    if (s.isTnrCommunityCat) {
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
        cat == 'Kitten' ||
        cat == 'Needs Foster' ||
        cat == 'Needs Home' ||
        cat == 'Rehomed') {
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

    final int cols = acts.length <= 2 ? 2 : (acts.length == 4 ? 2 : 3);
    final double ratio =
        acts.length <= 2 ? 1.35 : (acts.length == 4 ? 1.2 : 0.92);
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(s.careIcon, size: 12, color: badgeColor),
                      const SizedBox(width: 4),
                      Text(
                        s.careLabel,
                        style: GoogleFonts.nunito(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: badgeColor,
                        ),
                      ),
                    ],
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
                                const Icon(Icons.volunteer_activism_rounded,
                                    size: 13, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  '🏡 Offer Foster Care (+150 XP)',
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
                                const Icon(Icons.house_rounded,
                                    size: 13, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  '🏛️ Transfer to Shelter (+120 XP)',
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
        GridView.count(
        crossAxisCount: cols,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: ratio,
        children: acts.map((a) {
          final key = a['key'] as String;
          final isTookIn = key == 'tookIn';
          final isDeclinedTookIn = isTookIn && isFosterDeclinedForMe;
          final isSel = _myAction == key;
          final isTileLocked = isLockedForMe || isDeclinedTookIn;
          final isVetPriorityTile =
              key == 'vet' && s.isMedicalOrTriagePriority && !s.hasVetVisit;
          final col = _aColor(key);
          return GestureDetector(
            onTap: () {
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
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: isTileLocked
                    ? Colors.grey.withValues(alpha: 0.08)
                    : (isVetPriorityTile
                        ? const Color(0xFF673AB7).withValues(alpha: 0.08)
                        : (isSel ? col.withValues(alpha: 0.1) : _cardBg)),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isTileLocked
                        ? (isDeclinedTookIn
                            ? Colors.red.shade200
                            : Colors.grey.withValues(alpha: 0.2))
                        : (isVetPriorityTile
                            ? const Color(0xFF673AB7)
                            : (isSel ? col : _navy.withValues(alpha: 0.1))),
                    width: (isSel || isVetPriorityTile) ? 1.5 : 1),
              ),
              child: Opacity(
                opacity: isTileLocked ? 0.65 : 1.0,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isVetPriorityTile)
                      Container(
                        margin: const EdgeInsets.only(bottom: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF673AB7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '⭐ Priority 1st',
                          style: GoogleFonts.nunito(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    Icon(
                        isDeclinedTookIn
                            ? Icons.block_rounded
                            : (a['icon'] as IconData),
                        size: isVetPriorityTile ? 22 : 24,
                        color: isDeclinedTookIn
                            ? Colors.red.shade400
                            : (isTileLocked
                                ? Colors.grey
                                : (isVetPriorityTile
                                    ? const Color(0xFF673AB7)
                                    : col))),
                    const SizedBox(height: 3),
                    Text(
                        isDeclinedTookIn
                            ? 'Declined'
                            : (a['xp'] as String),
                        style: GoogleFonts.nunito(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: isDeclinedTookIn
                                ? Colors.red.shade400
                                : (isTileLocked
                                    ? Colors.grey
                                    : (isVetPriorityTile
                                        ? const Color(0xFF673AB7)
                                        : col)))),
                    const SizedBox(height: 2),
                    Text(a['label'] as String,
                        style: GoogleFonts.nunito(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: isDeclinedTookIn
                                ? Colors.grey.shade600
                                : _navy)),
                    const SizedBox(height: 1),
                    Text(
                        isDeclinedTookIn
                            ? 'Not available'
                            : (isVetPriorityTile
                                ? 'Triage & checkup'
                                : (a['sub'] as String)),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.nunito(
                            fontSize: 10,
                            color: isDeclinedTookIn
                                ? Colors.red.shade300
                                : (isVetPriorityTile
                                    ? const Color(0xFF673AB7)
                                    : _navy.withValues(alpha: 0.45)),
                            fontWeight: FontWeight.w600,
                            height: 1.2)),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    ],
  ]);
}

  Widget _buildThanks() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _lavLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _lavender.withValues(alpha: 0.3)),
        ),
        child: Row(children: [
          Icon(Icons.shield_outlined, color: _lavender, size: 28),
          const SizedBox(width: 12),
          Expanded(
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Thank you for helping!',
                style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _lavender)),
            Text('Your action makes a big difference.',
                style: GoogleFonts.nunito(
                    fontSize: 12,
                    color: _navy.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w600)),
          ])),
          const Text('\ud83d\udc31', style: TextStyle(fontSize: 28)),
        ]),
      );

  Widget _buildResolvedBanner(Sighting s) {
    final cat = s.category;
    String resolutionTitle = 'Rescue Case Resolved! 🎉';
    String resolutionMsg =
        'This sighting is resolved and the rescue goal has been achieved. Comments and photo updates remain open for discussion below! 🐾';

    final wasFosteredOrRehomed = s.resolvedByAction == 'rehomed' ||
        s.careTakerId != null ||
        s.careStartedAt != null ||
        s.completedMilestones.isNotEmpty ||
        s.careStatus == 'resolved' ||
        cat == 'Rehomed' ||
        cat == 'Needs Foster' ||
        cat == 'Needs Home';

    final isTnr = s.resolvedByAction == 'returnedToSpot' || s.isTnrReturned;
    final bannerCol = isTnr ? const Color(0xFF00897B) : _resolved;

    if (s.resolvedByAction == 'sheltered' || s.careStatus == 'inCare_shelter') {
      resolutionTitle = 'Safely Transferred to Shelter 🏛️';
      resolutionMsg =
          'This cat was safely admitted to verified shelter care. Comments remain open for updates!';
    } else if (isTnr) {
      resolutionTitle = 'Returned Safely to Colony (TNR) 🌿';
      resolutionMsg =
          'This cat completed veterinary recovery care and was safely returned to its outdoor colony territory. Community feeders are welcomed to check in, log feedings, and post photo updates!';
    } else if (wasFosteredOrRehomed) {
      resolutionTitle = 'Cat Successfully Rehomed! 🏡🎉';
      resolutionMsg =
          'This cat has completed foster care and was successfully adopted into a loving forever home! Feel free to share congratulations or photo updates below.';
    } else if (cat == 'Injured' || cat == 'Needs Vet' || s.resolvedByAction == 'vet') {
      resolutionTitle = 'Medical Care Completed 🩺';
      resolutionMsg =
          'This cat was safely brought for veterinary medical care. Comments remain open for recovery and follow-up updates!';
    } else {
      resolutionTitle = 'Cat Safely Fostered / Rehomed 💖';
      resolutionMsg =
          'This cat has found a safe foster or loving home! Feel free to share congratulations or photo updates in comments below.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bannerCol.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: bannerCol.withValues(alpha: 0.35), width: 1.5),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: bannerCol.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                    isTnr ? Icons.park_rounded : Icons.check_circle_rounded,
                    color: bannerCol,
                    size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      resolutionTitle,
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: bannerCol,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      resolutionMsg,
                      style: GoogleFonts.nunito(
                        fontSize: 12.5,
                        color: _navy.withValues(alpha: 0.7),
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
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
    final text = u['text'] ?? '';
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
              Row(children: [
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
                      Text(dName,
                          style: GoogleFonts.nunito(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: _navy)),
                      if (!isAnon) ...[
                        const SizedBox(width: 3),
                        Icon(Icons.shield_outlined,
                            size: 12, color: _lavender),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
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
                const Spacer(),
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
                    onTap: () => _showCommentMenu(u, sid),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(Icons.more_horiz,
                          size: 16,
                          color: _navy.withValues(alpha: 0.4)),
                    ),
                  ),
              ]),
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
                  '$dName $text',
                  style: GoogleFonts.nunito(
                    fontSize: 13,
                    color: _navy.withValues(alpha: 0.65),
                    fontWeight: FontWeight.w600,
                  ),
                )
              else if (isAdoptionOpened)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE65100).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFFE65100).withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: RichText(
                    text: TextSpan(
                      style: GoogleFonts.nunito(
                          fontSize: 13,
                          color: const Color(0xFFBF360C),
                          fontWeight: FontWeight.w600,
                          height: 1.4),
                      children: [
                        TextSpan(
                            text: '$dName ',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFBF360C))),
                        TextSpan(
                            text: text.isNotEmpty
                                ? text
                                : 'completed foster rehabilitation and officially opened this cat for permanent adoption! 🏡🐾' +
                                    (u['customNote'] != null &&
                                            u['customNote'].toString().isNotEmpty
                                        ? ' "${u['customNote']}"'
                                        : '')),
                      ],
                    ),
                  ),
                )
              else if (isOutcomeResolved || isOutcomeRequest)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.25),
                      width: 1,
                    ),
                  ),
                  child: RichText(
                    text: TextSpan(
                      style: GoogleFonts.nunito(
                          fontSize: 13,
                          color: const Color(0xFF1B5E20),
                          fontWeight: FontWeight.w600,
                          height: 1.4),
                      children: [
                        TextSpan(
                            text: '$dName ',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1B5E20))),
                        TextSpan(
                            text: text.isNotEmpty
                                ? text
                                : ((action == 'rehomed'
                                        ? 'successfully rehomed this cat with a loving forever family! 🏡🎉'
                                        : (action == 'sheltered'
                                            ? 'safely transferred this cat to an animal shelter partner! 🏛️🐾'
                                            : 'completed recovery care and safely returned this cat to its territory! 🌿🐾')) +
                                    (u['customNote'] != null &&
                                            u['customNote'].toString().isNotEmpty
                                        ? ' "${u['customNote']}"'
                                        : ''))),
                      ],
                    ),
                  ),
                )
              else if (isAct || isWay)
                RichText(
                    text: TextSpan(
                  style: GoogleFonts.nunito(
                      fontSize: 13,
                      color: _navy.withValues(alpha: 0.75),
                      fontWeight: FontWeight.w600,
                      height: 1.4),
                  children: [
                    TextSpan(
                        text: '$dName ',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700)),
                    TextSpan(text: text),
                  ],
                ))
              else
                Text(text,
                    style: GoogleFonts.nunito(
                        fontSize: 13,
                        color: _navy.withValues(alpha: 0.75),
                        fontWeight: FontWeight.w600,
                        height: 1.4)),
              if (u['proofPhotoUrl'] != null &&
                  u['proofPhotoUrl'].toString().isNotEmpty) ...[
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => _AllPhotosScreen(
                          photoUrls: [u['proofPhotoUrl'].toString()]),
                    ),
                  ),
                  child: Stack(
                    children: [
                      PawImage(
                        url: u['proofPhotoUrl'].toString(),
                        width: 140,
                        height: 100,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(12),
                        placeholder: const SizedBox.shrink(),
                      ),
                      Positioned(
                        bottom: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.verified,
                                  size: 11, color: Color(0xFF7BBF5E)),
                              const SizedBox(width: 4),
                              Text(
                                'Proof Photo',
                                style: GoogleFonts.nunito(
                                  fontSize: 9,
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
                                            _showCommentMenu(r, sid),
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
    final bottomPadding = MediaQuery.of(context).padding.bottom;
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
                        borderSide: BorderSide.none),
                    counterStyle: GoogleFonts.nunito(
                        fontSize: 11,
                        color: _navy.withValues(alpha: 0.4)),
                  )),
              const SizedBox(height: 12),
              Text('Description',
                  style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w700,
                      color: _navy,
                      fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                  controller: dc,
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
                        borderSide: BorderSide.none),
                    counterStyle: GoogleFonts.nunito(
                        fontSize: 11,
                        color: _navy.withValues(alpha: 0.4)),
                  )),
              const SizedBox(height: 16),
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
                    onPressed: () async {
                      await FirebaseService.instance.updateSighting(
                          s.id,
                          title: tc.text,
                          description: dc.text);
                      if (mounted) {
                        Navigator.pop(context);
                        _snack('Report updated!');
                      }
                    },
                    child: Text('Save Changes',
                        style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w800, fontSize: 15)),
                  )),
            ]),
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
    final bottomNavPadding = MediaQuery.of(context).padding.bottom;
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
                  20, 16, 20, 32 + MediaQuery.of(ctx).padding.bottom),
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
