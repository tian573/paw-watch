import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _sendMessage([String? textToSend]) {
    final text = (textToSend ?? _msgCtrl.text).trim();
    if (text.isEmpty) return;

    FirebaseService.instance.sendChatMessage(
      chatId: _chatId,
      sightingId: widget.sighting.id,
      text: text,
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
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
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

                        return Align(
                          alignment: isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            constraints: BoxConstraints(
                              maxWidth:
                                  MediaQuery.of(context).size.width * 0.76,
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isMe ? _lavender : Colors.white,
                              borderRadius: BorderRadius.only(
                                topLeft: const Radius.circular(16),
                                topRight: const Radius.circular(16),
                                bottomLeft: isMe
                                    ? const Radius.circular(16)
                                    : const Radius.circular(4),
                                bottomRight: isMe
                                    ? const Radius.circular(4)
                                    : const Radius.circular(16),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: _navy.withValues(alpha: 0.04),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                              border: isMe
                                  ? null
                                  : Border.all(
                                      color: _navy.withValues(alpha: 0.08)),
                            ),
                            child: Column(
                              crossAxisAlignment: isMe
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                Text(
                                  msg.text,
                                  style: GoogleFonts.nunito(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: isMe ? Colors.white : _navy,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${msg.createdAt.hour.toString().padLeft(2, '0')}:${msg.createdAt.minute.toString().padLeft(2, '0')}',
                                  style: GoogleFonts.nunito(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: isMe
                                        ? Colors.white.withValues(alpha: 0.7)
                                        : _navy.withValues(alpha: 0.4),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
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
                        onTap: () => _sendMessage(),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: const BoxDecoration(
                            color: _lavender,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.send_rounded,
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
}
