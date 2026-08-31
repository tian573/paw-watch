import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/sighting.dart';
import '../../services/firebase_service.dart';
import '../../services/ai_service.dart';
import '../../services/location_service.dart';

class SightingDetailScreen extends StatefulWidget {
  final Sighting sighting;
  const SightingDetailScreen({super.key, required this.sighting});
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

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void dispose() {
    _commentCtrl.dispose();
    _replyCtrl.dispose();
    super.dispose();
  }

  bool _isOwner(Sighting s) => _uid != null && _uid == s.reporterId;

  Color _sColor(String u) => u == 'urgent' ? _urgent : (u == 'resolved' ? _resolved : _needsHelp);
  String _sLabel(String u) => u == 'urgent' ? 'Urgent' : u == 'resolved' ? 'Resolved' : 'Needs Help';
  IconData _sIcon(String u) => u == 'resolved' ? Icons.check_circle : Icons.error;

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
              await FirebaseService.instance.deleteSighting(s.id);
              if (mounted) Navigator.pop(context, true);
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
      'Fake / inaccurate information', 'Not a cat / wrong animal',
      'Spam or duplicate', 'Inappropriate content', 'Other'
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

  void _showActionProofSheet(String action, Sighting s) {
    final col = _aColor(action);
    final actionLabel = _aLabels[action] ?? action;
    final xp = _aXp[action] ?? 10;
    File? proofFile;
    RescueActionValidationResult? scanResult;
    bool isScanning = false;
    bool isSubmitting = false;
    bool isAnonymous = _isAnon;
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

          final canSubmit = proofFile != null &&
              scanResult != null &&
              scanResult!.isValid &&
              !isScanning &&
              !isSubmitting;

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
                                'Log Rescue: $actionLabel',
                                style: GoogleFonts.nunito(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: _navy,
                                ),
                              ),
                              Text(
                                '+$xp XP reward upon verification',
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
                    const SizedBox(height: 16),
                    Text(
                      'Photo Proof (Required)',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'AI will verify the cat in your proof photo to prevent fake claims.',
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        color: _navy.withValues(alpha: 0.55),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (proofFile == null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _lavLight.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _lavender.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.add_a_photo_outlined,
                                size: 36, color: _lavender),
                            const SizedBox(height: 8),
                            Text(
                              'Take or upload proof of your rescue action',
                              style: GoogleFonts.nunito(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: _navy.withValues(alpha: 0.7),
                              ),
                            ),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: () => pickPhoto(ImageSource.camera),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _lavender,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 11),
                              ),
                              icon: const Icon(Icons.camera_alt, size: 16),
                              label: Text(
                                'Take Live Photo (Recommended)',
                                style: GoogleFonts.nunito(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextButton.icon(
                              onPressed: () => pickPhoto(ImageSource.gallery),
                              style: TextButton.styleFrom(
                                foregroundColor: _navy.withValues(alpha: 0.6),
                              ),
                              icon: const Icon(Icons.photo_library, size: 14),
                              label: Text(
                                'Choose from Gallery',
                                style: GoogleFonts.nunito(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isScanning
                                ? _lavender
                                : (scanResult?.isValid == true
                                    ? _resolved
                                    : _urgent),
                            width: 2,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Stack(
                            children: [
                              Image.file(
                                proofFile!,
                                width: double.infinity,
                                height: 160,
                                fit: BoxFit.cover,
                              ),
                              if (isScanning)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2.5),
                                          const SizedBox(height: 10),
                                          Text(
                                            'AI verifying cat & action proof...',
                                            style: GoogleFonts.nunito(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w800,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              if (!isScanning && scanResult != null)
                                Positioned(
                                  top: 8,
                                  left: 8,
                                  right: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: scanResult!.isValid
                                          ? _resolved.withValues(alpha: 0.9)
                                          : _urgent.withValues(alpha: 0.9),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          scanResult!.isValid
                                              ? Icons.check_circle
                                              : Icons.error,
                                          color: Colors.white,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            scanResult!.message,
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
                                ),
                              Positioned(
                                bottom: 8,
                                right: 8,
                                child: Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () =>
                                          pickPhoto(ImageSource.camera),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.65),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.refresh,
                                                color: Colors.white, size: 13),
                                            const SizedBox(width: 4),
                                            Text(
                                              'Retake',
                                              style: GoogleFonts.nunito(
                                                fontSize: 11,
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
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    Text(
                      'Action Note (Optional)',
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
                        hintText:
                            'e.g. Fed 2 cans of cat food near the alleyway',
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
                                  final awardedXp = await FirebaseService.instance.logRescueAction(
                                    sightingId: s.id,
                                    action: action,
                                    anonymous: isAnonymous,
                                    proofPhotoFile: proofFile,
                                    customNote: noteCtrl.text,
                                  );
                                  if (ctx.mounted) {
                                    Navigator.pop(ctx);
                                  }
                                  if (mounted) {
                                    setState(() {
                                      _hasActed = true;
                                      _myAction = action;
                                    });
                                    if (awardedXp > 0) {
                                      _snack('Verified & Logged! +$awardedXp XP awarded 🐾');
                                    } else {
                                      _snack('Spot status updated! (XP already collected for this spot recently)');
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
                                            ? 'Confirm & Log $actionLabel (+$xp XP)'
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

  void _showRoamingUpdateSheet(Sighting s) {
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

  void _showRelocationSheet(Sighting s) {
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

  void _showNotHereDialog(Sighting s) {
    final noteCtrl = TextEditingController();
    String selectedReason = 'roaming'; // 'roaming' or 'helpedOffline'
    final isOwner = _isOwner(s);

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
      // Distance check
      final userLoc = await LocationService().getCurrentUserLocation().catchError((_) => null);
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
    final t = _commentCtrl.text.trim();
    if (t.isEmpty) return;
    await FirebaseService.instance
        .addComment(sightingId: sid, text: t, anonymous: _isAnon);
    _commentCtrl.clear();
  }

  Future<void> _postReply(String sid) async {
    final t = _replyCtrl.text.trim();
    if (t.isEmpty || _replyingToId == null) return;
    await FirebaseService.instance.addComment(
        sightingId: sid, text: t, parentId: _replyingToId, anonymous: _isAnon);
    _replyCtrl.clear();
    setState(() {
      _replyingToId = null;
      _replyingToName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Sighting?>(
      stream: FirebaseService.instance.streamSightingById(widget.sighting.id),
      builder: (context, snap) {
        final s = snap.data ?? widget.sighting;
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
                          Text(s.displayTitle,
                              style: GoogleFonts.nunito(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: _navy,
                                  height: 1.2)),
                          const SizedBox(height: 12),
                          _buildReporter(s),
                          const SizedBox(height: 12),
                          if (s.urgency != 'resolved') ...[
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
                          if (s.urgency != 'resolved') ...[
                            _buildActions(s),
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
                            height: (s.urgency != 'resolved' ? 140.0 : 60.0) +
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
                    return url.startsWith('http')
                        ? Image.network(url,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, err, st) => _placeholder())
                        : Image.file(File(url),
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, err, st) => _placeholder());
                  })
              : _placeholder(),
          Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                  height: 80,
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.4)
                      ])))),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                    Colors.black.withValues(alpha: 0.45),
                    Colors.transparent
                  ])),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          ),
          Positioned(
              top: kToolbarHeight + MediaQuery.of(context).padding.top - 8,
              left: 16,
              child: _badge(s.urgency)),
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

  Widget _buildReporter(Sighting s) => Row(children: [
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
        Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.reporterName,
              style: GoogleFonts.nunito(
                  fontSize: 14, fontWeight: FontWeight.w800, color: _navy)),
          Text('${s.timeAgo}  \u2022  ${s.distance}',
              style: GoogleFonts.nunito(
                  fontSize: 12,
                  color: _navy.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w600)),
        ])),
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

  Widget _buildLocation(Sighting s) {
    final isResolved = s.urgency == 'resolved';
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(
              isResolved ? Icons.shield_outlined : Icons.location_on_outlined,
              color: isResolved ? _resolved : _lavender,
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
          if (isResolved)
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
            ),
        ],
      )),
      const SizedBox(width: 8),
      if (!isResolved)
        GestureDetector(
          onTap: () => _openMaps(s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _lavLight,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _lavender.withValues(alpha: 0.35)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.near_me_outlined, size: 13, color: _lavender),
              const SizedBox(width: 4),
              Text('Open in Maps',
                  style: GoogleFonts.nunito(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _lavender)),
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

  Widget _buildActions(Sighting s) {
    final allActs = [
      {'key': 'roaming', 'icon': Icons.edit_location_alt_outlined, 'label': 'Still Here / Move', 'xp': '+15-25 XP', 'sub': 'Update spot'},
      {'key': 'fed', 'icon': Icons.restaurant, 'label': 'Fed', 'xp': '+30 XP', 'sub': 'Gave food'},
      {'key': 'vet', 'icon': Icons.medical_services, 'label': 'Vet Visit', 'xp': '+100 XP', 'sub': 'Took to vet'},
      {'key': 'tookIn', 'icon': Icons.home, 'label': 'Took In', 'xp': '+150 XP', 'sub': 'Taking care'},
      {'key': 'sheltered', 'icon': Icons.house, 'label': 'Sheltered', 'xp': '+120 XP', 'sub': 'In shelter'},
      {'key': 'rehomed', 'icon': Icons.favorite, 'label': 'Rehomed', 'xp': '+200 XP', 'sub': 'Found a home'},
    ];

    List<Map<String, Object>> acts;
    final cat = s.category;
    if (cat == 'Injured' || cat == 'Needs Vet') {
      acts = allActs
          .where((a) => a['key'] == 'vet' || a['key'] == 'tookIn' || a['key'] == 'roaming')
          .toList();
    } else if (cat == 'Kitten') {
      acts = allActs
          .where((a) =>
              a['key'] == 'tookIn' ||
              a['key'] == 'sheltered' ||
              a['key'] == 'rehomed' ||
              a['key'] == 'vet' ||
              a['key'] == 'roaming')
          .toList();
    } else if (cat == 'Needs Foster' || cat == 'Rehomed') {
      acts = allActs
          .where((a) =>
              a['key'] == 'rehomed' ||
              a['key'] == 'tookIn' ||
              a['key'] == 'sheltered' ||
              a['key'] == 'roaming')
          .toList();
    } else if (cat == 'Urgent Rescue') {
      acts = allActs
          .where((a) =>
              a['key'] == 'tookIn' ||
              a['key'] == 'vet' ||
              a['key'] == 'sheltered' ||
              a['key'] == 'roaming')
          .toList();
    } else {
      acts = allActs;
    }

    final int cols = acts.length <= 2 ? 2 : (acts.length == 4 ? 2 : 3);
    final double ratio = acts.length <= 2 ? 1.35 : (acts.length == 4 ? 1.2 : 0.92);
    final uid = _uid;
    final isClaimed = s.rescueClaimed;
    final isClaimedByMe = isClaimed && uid != null && s.rescueClaimedBy == uid;
    final isLockedForMe = isClaimed && !isClaimedByMe && !_isOwner(s);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(
        children: [
          Text('Take Action',
              style: GoogleFonts.nunito(
                  fontSize: 17, fontWeight: FontWeight.w900, color: _navy)),
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
        s.isOneTimeTask
            ? 'Action focused on ${s.category} situation. Verified by AI proof.'
            : 'Choose an action to help. Visible to all rescuers.',
        style: GoogleFonts.nunito(
            fontSize: 12,
            color: _navy.withValues(alpha: 0.55),
            fontWeight: FontWeight.w600),
      ),
      if (isLockedForMe) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _lavender.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _lavender.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _lavender.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.directions_run,
                    color: _lavender, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${s.rescueClaimedByName.isNotEmpty ? s.rescueClaimedByName : "A rescuer"} is on the way',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _navy,
                      ),
                    ),
                    Text(
                      'Action logging is currently reserved for the active rescuer. You can coordinate in the comments below.',
                      style: GoogleFonts.nunito(
                        fontSize: 11,
                        color: _navy.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
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
          final isSel = _myAction == key;
          final col = _aColor(key);
          return GestureDetector(
            onTap: () {
              if (isLockedForMe) {
                _snack(
                    '🏃 ${s.rescueClaimedByName.isNotEmpty ? s.rescueClaimedByName : "A rescuer"} is already heading to help this cat.');
                return;
              }
              if (key == 'roaming') {
                _showRoamingUpdateSheet(s);
              } else {
                _showActionProofSheet(key, s);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: isLockedForMe
                    ? Colors.grey.withValues(alpha: 0.08)
                    : (isSel ? col.withValues(alpha: 0.1) : _cardBg),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: isLockedForMe
                        ? Colors.grey.withValues(alpha: 0.2)
                        : (isSel ? col : _navy.withValues(alpha: 0.1)),
                    width: isSel ? 1.5 : 1),
              ),
              child: Opacity(
                opacity: isLockedForMe ? 0.65 : 1.0,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(a['icon'] as IconData,
                        size: 24, color: isLockedForMe ? Colors.grey : col),
                    const SizedBox(height: 4),
                    Text(a['xp'] as String,
                        style: GoogleFonts.nunito(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: isLockedForMe ? Colors.grey : col)),
                    const SizedBox(height: 2),
                    Text(a['label'] as String,
                        style: GoogleFonts.nunito(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: _navy)),
                    const SizedBox(height: 1),
                    Text(a['sub'] as String,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.nunito(
                            fontSize: 10,
                            color: _navy.withValues(alpha: 0.45),
                            fontWeight: FontWeight.w600,
                            height: 1.2)),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
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

    if (cat == 'Injured' || cat == 'Needs Vet') {
      resolutionTitle = 'Medical Care Completed 🩺';
      resolutionMsg =
          'This cat was safely brought for veterinary medical care. Comments remain open for recovery and follow-up updates!';
    } else if (cat == 'Kitten' || cat == 'Needs Foster' || cat == 'Rehomed') {
      resolutionTitle = 'Cat Safely Fostered / Rehomed 💖';
      resolutionMsg =
          'This cat has found a safe foster or loving home! Feel free to share congratulations or photo updates in comments below.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _resolved.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: _resolved.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _resolved.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded,
                color: _resolved, size: 24),
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
                    color: _resolved,
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
    final isComment = type == 'comment';
    final isAnon = u['isAnonymous'] == true;
    final isDeleted = u['isDeleted'] == true;
    final isEdited = u['isEdited'] == true;
    final dName = isAnon ? 'Anonymous' : name;
    final aCol = isWayCancelled || (isWay && isTripCancelled)
        ? const Color(0xFF78909C)
        : isWay
            ? _lavender
            : isAct
                ? _aColor(action ?? '')
                : _avColor(isAnon ? 'Anon' : name);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
            width: 34,
            height: 34,
            decoration:
                BoxDecoration(color: aCol, shape: BoxShape.circle),
            child: Center(
                child: isWayCancelled || (isWay && isTripCancelled)
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
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)))),
        const SizedBox(width: 10),
        Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Text(dName,
                    style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: _navy)),
                const SizedBox(width: 6),
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
                if (isComment && !isDeleted)
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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: u['proofPhotoUrl'].toString().startsWith('http')
                            ? Image.network(
                                u['proofPhotoUrl'].toString(),
                                width: 140,
                                height: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) =>
                                    const SizedBox.shrink(),
                              )
                            : Image.file(
                                File(u['proofPhotoUrl'].toString()),
                                width: 140,
                                height: 100,
                                fit: BoxFit.cover,
                                errorBuilder: (c, e, s) =>
                                    const SizedBox.shrink(),
                              ),
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
              if (u['isReporterConfirmed'] == true) ...[
                const SizedBox(height: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _resolved.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _resolved.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified, size: 12, color: _resolved),
                      const SizedBox(width: 4),
                      Text(
                        'Verified & Confirmed by Reporter',
                        style: GoogleFonts.nunito(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          color: _resolved,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (_isOwner(s) && isAct && u['authorId'] != _uid) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () async {
                    await FirebaseService.instance
                        .confirmRescueAction(sid, u['id']);
                    _snack('Rescue action confirmed! ✅');
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _lavLight,
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: _lavender.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 12, color: _lavender),
                        const SizedBox(width: 4),
                        Text(
                          'Confirm this Rescue Action',
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
          onTap: () =>
              isReply ? _postReply(sid) : _postComment(sid),
          child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                  color: _lavender, shape: BoxShape.circle),
              child: const Icon(Icons.send_rounded,
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
    if (s.urgency == 'resolved') {
      return const SizedBox.shrink();
    }
    final uid = _uid;
    final claimed = s.rescueClaimed;
    final claimedByMe =
        claimed && uid != null && s.rescueClaimedBy == uid;
    final canCancel = claimed && (claimedByMe || _isOwner(s));
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
                    child: url.startsWith('http')
                        ? Image.network(url,
                            fit: BoxFit.contain,
                            errorBuilder: (ctx, err, st) => const Icon(
                                Icons.broken_image,
                                color: Colors.white,
                                size: 60))
                        : Image.file(File(url),
                            fit: BoxFit.contain,
                            errorBuilder: (ctx, err, st) => const Icon(
                                Icons.broken_image,
                                color: Colors.white,
                                size: 60))));
          },
        ),
      );
}
