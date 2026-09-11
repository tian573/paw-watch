import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/sighting.dart';
import '../../models/chat_message.dart';
import '../../services/firebase_service.dart';

class CoordinationChatScreen extends StatefulWidget {
  final Sighting sighting;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserRole; // 'Foster Volunteer' or 'Reporter'

  const CoordinationChatScreen({
    super.key,
    required this.sighting,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserRole,
  });

  @override
  State<CoordinationChatScreen> createState() => _CoordinationChatScreenState();
}

class _CoordinationChatScreenState extends State<CoordinationChatScreen> {
  static const _navy = Color(0xFF2D3142);
  static const _lavender = Color(0xFF9B8EC4);
  static const _lavLight = Color(0xFFF3F0F9);

  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();
  File? _selectedPhotoFile;
  bool _isUploadingPhoto = false;
  final Set<String> _locallyHiddenMessageIds = {};
  final Set<String> _revealedReportedMessageIds = {};
  late final String _chatId;
  late final String _myUid;

  @override
  void initState() {
    super.initState();
    _myUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    _chatId = FirebaseService.instance.getCoordinationChatId(
      widget.sighting.id,
      _myUid,
      widget.otherUserId,
    );
    if (_myUid.isNotEmpty) {
      FirebaseService.instance.markChatAsRead(
        chatId: _chatId,
        userId: _myUid,
      );
    }
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage([String? textToSend]) async {
    final text = (textToSend ?? _msgCtrl.text).trim();
    if (text.isEmpty && _selectedPhotoFile == null) return;

    final photoToSend = _selectedPhotoFile;
    setState(() {
      _selectedPhotoFile = null;
      if (photoToSend != null) _isUploadingPhoto = true;
    });

    String? uploadedPhotoUrl;
    if (photoToSend != null) {
      try {
        final urls = await FirebaseService.instance.uploadPhotos(
          [photoToSend],
          'chat_${widget.sighting.id}',
        );
        if (urls.isNotEmpty) {
          uploadedPhotoUrl = urls.first;
        }
      } catch (e) {
        debugPrint('Failed to upload photo via storage: $e');
        try {
          final bytes = await photoToSend.readAsBytes();
          uploadedPhotoUrl = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        } catch (_) {
          uploadedPhotoUrl = photoToSend.path;
        }
      }
    }

    if (mounted) {
      setState(() => _isUploadingPhoto = false);
    }

    if (text.isEmpty && uploadedPhotoUrl == null) return;

    await FirebaseService.instance.sendChatMessage(
      chatId: _chatId,
      sightingId: widget.sighting.id,
      text: text.isNotEmpty ? text : '📷 Sent a photo',
      photoUrl: uploadedPhotoUrl,
      otherUserId: widget.otherUserId,
      otherUserName: widget.otherUserName,
      sightingTitle: widget.sighting.displayTitle,
      sightingPhoto: widget.sighting.photoUrls.isNotEmpty
          ? widget.sighting.photoUrls.first
          : null,
    );

    if (textToSend == null) {
      _msgCtrl.clear();
    }

    Future.delayed(const Duration(milliseconds: 150), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 82,
      );
      if (picked != null) {
        setState(() {
          _selectedPhotoFile = File(picked.path);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick image: $e')),
        );
      }
    }
  }

  void _showAttachPhotoMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Send a Photo',
                style: GoogleFonts.nunito(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: _navy,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Share carrier setup, location landmarks, or cat recovery photos.',
                style: GoogleFonts.nunito(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _navy.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickPhoto(ImageSource.camera);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _lavLight,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: _lavender.withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.camera_alt_rounded,
                                color: _lavender, size: 28),
                            const SizedBox(height: 6),
                            Text(
                              'Camera',
                              style: GoogleFonts.nunito(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: _navy,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _pickPhoto(ImageSource.gallery);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _lavLight,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: _lavender.withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.photo_library_rounded,
                                color: Color(0xFF1E88E5), size: 28),
                            const SizedBox(height: 6),
                            Text(
                              'Gallery',
                              style: GoogleFonts.nunito(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: _navy,
                              ),
                            ),
                          ],
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
    );
  }

  Future<void> _showReportPhotoDialog(ChatMessage msg) async {
    String selectedReason = 'Inappropriate or unwanted content';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.flag_rounded,
                    color: Colors.red, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Report Unwanted Photo',
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
                  'Help keep PawWatch safe and helpful. Why are you reporting this photo?',
                  style: GoogleFonts.nunito(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: _navy.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 12),
                ...[
                  'Inappropriate or graphic content',
                  'Animal cruelty or harm',
                  'Spam or unrelated image',
                  'Harassment or offensive photo',
                  'Other unwanted content',
                ].map((reason) {
                  final isSelected = selectedReason == reason;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: InkWell(
                      onTap: () => setDlgState(() => selectedReason = reason),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.red.withValues(alpha: 0.08)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? Colors.red
                                : _navy.withValues(alpha: 0.12),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected
                                  ? Icons.radio_button_checked_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 16,
                              color: isSelected ? Colors.red : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                reason,
                                style: GoogleFonts.nunito(
                                  fontSize: 12,
                                  fontWeight: isSelected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color:
                                      isSelected ? Colors.red.shade800 : _navy,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
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
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => Navigator.pop(dCtx, true),
              child: Text('Report & Hide',
                  style: GoogleFonts.nunito(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _locallyHiddenMessageIds.add(msg.id);
      });

      try {
        await FirebaseService.instance.reportChatMessage(
          chatId: _chatId,
          messageId: msg.id,
          reason: selectedReason,
          photoUrl: msg.photoUrl,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Photo reported to moderation and hidden from your chat view. 🛡️'),
              backgroundColor: Colors.black87,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to report: $e')),
          );
        }
      }
    }
  }

  Widget _buildChatPhoto(
    String url, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    bool isFullScreen = false,
  }) {
    if (url.startsWith('data:image')) {
      try {
        final commaIdx = url.indexOf(',');
        final b64 = commaIdx != -1 ? url.substring(commaIdx + 1) : url;
        final bytes = base64Decode(b64);
        return Image.memory(
          bytes,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (ctx, err, stack) =>
              _chatImagePlaceholder(height, isFullScreen: isFullScreen),
        );
      } catch (e) {
        debugPrint('Base64 image decode notice: $e');
      }
    }

    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        width: width,
        height: height,
        fit: fit,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            width: width,
            height: height ?? 180,
            color: isFullScreen ? Colors.black : _lavLight,
            child: const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: _lavender,
              ),
            ),
          );
        },
        errorBuilder: (ctx, err, stack) {
          try {
            if (File(url).existsSync()) {
              return Image.file(File(url),
                  width: width, height: height, fit: fit);
            }
          } catch (_) {}
          return _chatImagePlaceholder(height, isFullScreen: isFullScreen);
        },
      );
    }

    if (url.startsWith('assets/')) {
      return Image.asset(
        url,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (ctx, err, stack) =>
            _chatImagePlaceholder(height, isFullScreen: isFullScreen),
      );
    }

    try {
      final file = File(url);
      if (file.existsSync()) {
        return Image.file(
          file,
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (ctx, err, stack) =>
              _chatImagePlaceholder(height, isFullScreen: isFullScreen),
        );
      }
    } catch (_) {}

    return _chatImagePlaceholder(height, isFullScreen: isFullScreen);
  }

  Widget _chatImagePlaceholder(double? height, {bool isFullScreen = false}) {
    return Container(
      height: height ?? 140,
      color: isFullScreen ? Colors.black : _lavLight,
      child: Center(
        child: Icon(
          Icons.broken_image_rounded,
          color: isFullScreen ? Colors.white38 : Colors.grey,
          size: 36,
        ),
      ),
    );
  }

  void _showFullScreenPhoto(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              child: _buildChatPhoto(
                url,
                fit: BoxFit.contain,
                isFullScreen: true,
              ),
            ),
            Positioned(
              top: MediaQuery.of(ctx).padding.top + 10,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmBlockUser() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child:
                  const Icon(Icons.block_rounded, color: Colors.red, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Block User',
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    color: _navy),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to block ${widget.otherUserName}? Neither of you will be able to send messages in this conversation.',
          style: GoogleFonts.nunito(
              fontSize: 13.5,
              color: _navy.withValues(alpha: 0.8),
              height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w700,
                    color: _navy.withValues(alpha: 0.6))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Block',
                style: GoogleFonts.nunito(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await FirebaseService.instance.blockUserInChat(
        chatId: _chatId,
        targetUserId: widget.otherUserId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Blocked ${widget.otherUserName}',
                style: GoogleFonts.nunito(fontWeight: FontWeight.w700)),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  Future<void> _confirmUnblockUser() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_open_rounded,
                  color: Colors.teal, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Unblock User',
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    color: _navy),
              ),
            ),
          ],
        ),
        content: Text(
          'Unblock ${widget.otherUserName}? You will be able to send and receive messages again.',
          style: GoogleFonts.nunito(
              fontSize: 13.5,
              color: _navy.withValues(alpha: 0.8),
              height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w700,
                    color: _navy.withValues(alpha: 0.6))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Unblock',
                style: GoogleFonts.nunito(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await FirebaseService.instance.unblockUserInChat(
        chatId: _chatId,
        targetUserId: widget.otherUserId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unblocked ${widget.otherUserName}',
                style: GoogleFonts.nunito(fontWeight: FontWeight.w700)),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.teal.shade700,
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteConversation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline_rounded,
                  color: Colors.red, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Delete Conversation',
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    color: _navy),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete this entire conversation? All messages will be permanently removed.',
          style: GoogleFonts.nunito(
              fontSize: 13.5,
              color: _navy.withValues(alpha: 0.8),
              height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w700,
                    color: _navy.withValues(alpha: 0.6))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: Text('Delete',
                style: GoogleFonts.nunito(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await FirebaseService.instance.deleteChatThread(_chatId);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Conversation deleted',
                style: GoogleFonts.nunito(fontWeight: FontWeight.w700)),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.sighting.photoUrls.isNotEmpty
        ? widget.sighting.photoUrls.first
        : '';

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseService.instance.streamChatDoc(_chatId),
      builder: (context, chatDocSnap) {
        final chatData = chatDocSnap.data?.data();
        if (chatData != null && _myUid.isNotEmpty) {
          final unreadBy =
              (chatData['unreadBy'] as List<dynamic>?)?.cast<String>() ?? [];
          if (unreadBy.contains(_myUid)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              FirebaseService.instance.markChatAsRead(
                chatId: _chatId,
                userId: _myUid,
              );
            });
          }
        }
        final blockedBy =
            (chatData?['blockedBy'] as List<dynamic>?)?.cast<String>() ?? [];
        final isBlockedByMe = blockedBy.contains(_myUid);
        final isBlockedByOther = blockedBy.isNotEmpty && !isBlockedByMe;

        return Scaffold(
          backgroundColor: const Color(0xFFF8F7FC),
          appBar: AppBar(
            elevation: 1,
            backgroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: _navy),
              onPressed: () => Navigator.pop(context),
            ),
            titleSpacing: 0,
            title: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _lavender.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: _lavender.withValues(alpha: 0.5)),
                  ),
                  child: Center(
                    child: Text(
                      widget.otherUserName.isNotEmpty
                          ? widget.otherUserName.substring(0, 1).toUpperCase()
                          : 'U',
                      style: GoogleFonts.nunito(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _lavender,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.otherUserName,
                        style: GoogleFonts.nunito(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _navy,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        widget.otherUserRole ?? 'Rescue Coordination',
                        style: GoogleFonts.nunito(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF673AB7),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: _navy),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                onSelected: (val) {
                  if (val == 'toggle_block') {
                    if (isBlockedByMe) {
                      _confirmUnblockUser();
                    } else {
                      _confirmBlockUser();
                    }
                  } else if (val == 'delete_chat') {
                    _confirmDeleteConversation();
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem<String>(
                    value: 'toggle_block',
                    child: Row(
                      children: [
                        Icon(
                          isBlockedByMe
                              ? Icons.lock_open_rounded
                              : Icons.block_rounded,
                          color: isBlockedByMe
                              ? Colors.teal
                              : Colors.orange.shade800,
                          size: 19,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          isBlockedByMe ? 'Unblock User' : 'Block User',
                          style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w700,
                            color: isBlockedByMe
                                ? Colors.teal
                                : Colors.orange.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: 'delete_chat',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline_rounded,
                            color: Colors.red, size: 19),
                        const SizedBox(width: 10),
                        Text(
                          'Delete Conversation',
                          style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w700,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: Column(
            children: [
              // Sighting Context Header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: _navy.withValues(alpha: 0.08)),
                  ),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildThumbnail(photo),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Re: ${widget.sighting.displayTitle}',
                            style: GoogleFonts.nunito(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: _navy,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '📍 ${widget.sighting.displayLocation}',
                            style: GoogleFonts.nunito(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _navy.withValues(alpha: 0.55),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Message Stream
              Expanded(
                child: StreamBuilder<List<ChatMessage>>(
                  stream:
                      FirebaseService.instance.streamChatMessages(_chatId),
                  builder: (context, snapshot) {
                    final messages = snapshot.data ?? [];

                    if (messages.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: _lavender.withValues(alpha: 0.12),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    color: _lavender,
                                    size: 36),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Start Coordination Chat 🐾',
                                style: GoogleFonts.nunito(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: _navy,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Coordinate handover location, carrier preparation, and care details directly.',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.nunito(
                                  fontSize: 12.5,
                                  color: _navy.withValues(alpha: 0.6),
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isMe = msg.senderId == _myUid;

                        // System Message Pill
                        if (msg.isSystemMessage) {
                          return Align(
                            alignment: Alignment.center,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: _navy.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                    color: _navy.withValues(alpha: 0.1)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.shield_outlined,
                                      size: 14,
                                      color: _navy.withValues(alpha: 0.6)),
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text(
                                      msg.text,
                                      style: GoogleFonts.nunito(
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                        fontWeight: FontWeight.w600,
                                        color: _navy.withValues(alpha: 0.7),
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }

                        return _buildMessageBubble(msg, isMe);
                      },
                    );
                  },
                ),
              ),

              // Bottom Section: Quick Chips + Input OR Blocked Banner
              if (isBlockedByMe)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(16, 12, 16,
                      12 + MediaQuery.of(context).padding.bottom),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4EC),
                    border: Border(
                        top: BorderSide(
                            color: Colors.deepOrange.withValues(alpha: 0.2))),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.block_rounded,
                          color: Colors.deepOrange, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'You blocked ${widget.otherUserName}',
                              style: GoogleFonts.nunito(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF8B2500),
                              ),
                            ),
                            Text(
                              'You cannot send or receive messages.',
                              style: GoogleFonts.nunito(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF8B2500)
                                    .withValues(alpha: 0.75),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _confirmUnblockUser,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrange,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                        child: Text('Unblock',
                            style: GoogleFonts.nunito(
                                fontSize: 12, fontWeight: FontWeight.w800)),
                      ),
                    ],
                  ),
                )
              else if (isBlockedByOther)
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(16, 14, 16,
                      14 + MediaQuery.of(context).padding.bottom),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F1F5),
                    border: Border(
                        top: BorderSide(
                            color: _navy.withValues(alpha: 0.1))),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: _navy.withValues(alpha: 0.6), size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This conversation is unavailable for messaging.',
                          style: GoogleFonts.nunito(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: _navy.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else ...[
                // Quick Action Suggestion Chips
                Container(
                  height: 38,
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: [
                      _buildQuickChip('📍 I am at the spot now'),
                      _buildQuickChip('🚗 Carrier ready'),
                      _buildQuickChip('⏰ When can we meet?'),
                      _buildQuickChip('🏡 Safe foster space prepared'),
                      _buildQuickChip('🩺 Taking to vet clinic first'),
                    ],
                  ),
                ),

                if (_selectedPhotoFile != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    color: Colors.white,
                    child: Row(
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                _selectedPhotoFile!,
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: -6,
                              right: -6,
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _selectedPhotoFile = null),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Photo attached',
                                style: GoogleFonts.nunito(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: _navy,
                                ),
                              ),
                              Text(
                                'Add a caption below or tap send 🐾',
                                style: GoogleFonts.nunito(
                                  fontSize: 11,
                                  color: _navy.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                // Input Bar
                Container(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    8,
                    12,
                    8 + MediaQuery.of(context).padding.bottom,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: _navy.withValues(alpha: 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: _isUploadingPhoto ? null : _showAttachPhotoMenu,
                        child: Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: _lavLight,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: _lavender.withValues(alpha: 0.25)),
                          ),
                          child: const Icon(Icons.camera_alt_rounded,
                              color: _lavender, size: 19),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: _lavLight,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: TextField(
                            controller: _msgCtrl,
                            textCapitalization: TextCapitalization.sentences,
                            style: GoogleFonts.nunito(
                              fontSize: 13.5,
                              color: _navy,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              hintText:
                                  'Type a message to ${widget.otherUserName}...',
                              hintStyle: GoogleFonts.nunito(
                                fontSize: 12.5,
                                color: _navy.withValues(alpha: 0.4),
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 10),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _isUploadingPhoto ? null : () => _sendMessage(),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: _lavender,
                            shape: BoxShape.circle,
                          ),
                          child: _isUploadingPhoto
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.send_rounded,
                                  color: Colors.white, size: 18),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildQuickChip(String label) {
    return GestureDetector(
      onTap: () => _sendMessage(label),
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _lavender.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: _navy.withValues(alpha: 0.03),
              blurRadius: 4,
            ),
          ],
        ),
        child: Center(
          child: Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: _navy.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnail(String photo) {
    if (photo.isEmpty) return _catPlaceholder();

    if (photo.startsWith('http')) {
      return Image.network(
        photo,
        width: 38,
        height: 38,
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, stack) => _catPlaceholder(),
      );
    }

    if (photo.startsWith('assets/')) {
      return Image.asset(
        photo,
        width: 38,
        height: 38,
        fit: BoxFit.cover,
        errorBuilder: (ctx, err, stack) => _catPlaceholder(),
      );
    }

    return Image.file(
      File(photo),
      width: 38,
      height: 38,
      fit: BoxFit.cover,
      errorBuilder: (ctx, err, stack) => _catPlaceholder(),
    );
  }

  Widget _catPlaceholder() {
    return Container(
      width: 38,
      height: 38,
      color: _lavLight,
      child: const Icon(Icons.pets, color: _lavender, size: 20),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isMe) {
    final hasPhoto = msg.photoUrl != null && msg.photoUrl!.isNotEmpty;
    final isPhotoOnly = hasPhoto &&
        (msg.text.trim().isEmpty || msg.text.trim() == '📷 Sent a photo');
    final isReported =
        msg.isReported || _locallyHiddenMessageIds.contains(msg.id);
    final isRevealed = _revealedReportedMessageIds.contains(msg.id);
    final shouldShield = isReported && !isRevealed;

    final timeStr =
        '${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}';

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Sender name for other user
            if (!isMe)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 3),
                child: Text(
                  msg.senderName,
                  style: GoogleFonts.nunito(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _navy.withValues(alpha: 0.55),
                  ),
                ),
              ),

            // Message Container
            Container(
              decoration: BoxDecoration(
                color: isMe ? _lavender : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
                boxShadow: [
                  BoxShadow(
                    color: _navy.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
                border: isMe
                    ? null
                    : Border.all(color: _navy.withValues(alpha: 0.08)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // PHOTO SECTION
                  if (hasPhoto) ...[
                    if (shouldShield)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        color: Colors.amber.shade50,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(Icons.shield_rounded,
                                color: Colors.amber.shade800, size: 28),
                            const SizedBox(height: 6),
                            Text(
                              'Photo Flagged / Hidden',
                              style: GoogleFonts.nunito(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Colors.amber.shade900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              msg.reportReason != null &&
                                      msg.reportReason!.isNotEmpty
                                  ? 'Reason: ${msg.reportReason}'
                                  : 'Reported as unwanted or inappropriate content.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.nunito(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber.shade900
                                    .withValues(alpha: 0.8),
                              ),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _revealedReportedMessageIds.add(msg.id);
                                });
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: Colors.amber.shade400),
                                ),
                                child: Text(
                                  'View photo anyway',
                                  style: GoogleFonts.nunito(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Stack(
                        children: [
                          GestureDetector(
                            onTap: () => _showFullScreenPhoto(msg.photoUrl!),
                            child: Hero(
                              tag: 'chat_img_${msg.id}',
                              child: _buildChatPhoto(
                                msg.photoUrl!,
                                width: double.infinity,
                                height: 210,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          // Tap to view hint overlay
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.fullscreen_rounded,
                                      color: Colors.white, size: 14),
                                  const SizedBox(width: 3),
                                  Text(
                                    'Expand',
                                    style: GoogleFonts.nunito(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Report button on received photos
                          if (!isMe)
                            Positioned(
                              top: 8,
                              right: 8,
                              child: GestureDetector(
                                onTap: () => _showReportPhotoDialog(msg),
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.flag_outlined,
                                    color: Colors.white,
                                    size: 15,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                  ],

                  // TEXT SECTION (if not photo-only or if caption exists)
                  if (!isPhotoOnly && msg.text.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                      child: Text(
                        msg.text,
                        style: GoogleFonts.nunito(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: isMe ? Colors.white : _navy,
                          height: 1.35,
                        ),
                      ),
                    ),

                  // FOOTER: Timestamp + Report option for non-photo or photo caption
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          timeStr,
                          style: GoogleFonts.nunito(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: isMe
                                ? Colors.white.withValues(alpha: 0.75)
                                : _navy.withValues(alpha: 0.45),
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.done_all_rounded,
                            size: 13,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                        ],
                        if (!isMe && !hasPhoto) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => _showReportPhotoDialog(msg),
                            child: Icon(
                              Icons.flag_outlined,
                              size: 12,
                              color: _navy.withValues(alpha: 0.35),
                            ),
                          ),
                        ],
                      ],
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
}
