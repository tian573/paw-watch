import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/firebase_service.dart';
import '../../models/sighting.dart';
import 'chat_screen.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  static const _navy = Color(0xFF2D3142);
  static const _lavender = Color(0xFF9B8EC4);
  static const _lavLight = Color(0xFFF3F0F9);

  final Set<String> _selectedChatIds = {};
  bool get _isSelectionMode => _selectedChatIds.isNotEmpty;
  bool _isDeleting = false;

  void _toggleSelection(String chatId) {
    setState(() {
      if (_selectedChatIds.contains(chatId)) {
        _selectedChatIds.remove(chatId);
      } else {
        _selectedChatIds.add(chatId);
      }
    });
  }

  void _selectAll(List<String> allIds) {
    setState(() {
      if (_selectedChatIds.length == allIds.length) {
        _selectedChatIds.clear();
      } else {
        _selectedChatIds.addAll(allIds);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedChatIds.clear();
    });
  }

  String _formatChatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    DateTime dt;
    if (timestamp is Timestamp) {
      dt = timestamp.toDate();
    } else if (timestamp is DateTime) {
      dt = timestamp;
    } else {
      return '';
    }
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) {
      return 'Just now';
    } else if (diff.inMinutes < 60) {
      return '${diff.inMinutes}m';
    } else if (diff.inHours < 24 && dt.day == now.day) {
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } else if (diff.inDays == 1 ||
        (diff.inHours < 48 && dt.day == now.subtract(const Duration(days: 1)).day)) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dt.weekday - 1];
    } else {
      return '${dt.day}/${dt.month}';
    }
  }

  Future<void> _confirmDeleteChat(
      BuildContext context, String chatId, String otherName) async {
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
          'Are you sure you want to delete the conversation with $otherName? All messages will be permanently removed.',
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

    if (confirm == true && context.mounted) {
      await FirebaseService.instance.deleteChatThread(chatId);
      if (context.mounted) {
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

  Future<void> _confirmDeleteSelectedChats(BuildContext context) async {
    final count = _selectedChatIds.length;
    if (count == 0) return;

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
                'Delete $count Conversation${count > 1 ? 's' : ''}',
                style: GoogleFonts.nunito(
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                    color: _navy),
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete $count selected conversation${count > 1 ? 's' : ''}? All messages in these threads will be permanently removed.',
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
            child: Text('Delete ($count)',
                style: GoogleFonts.nunito(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      final idsToDelete = _selectedChatIds.toList();
      setState(() {
        _isDeleting = true;
      });

      try {
        await FirebaseService.instance.deleteMultipleChatThreads(idsToDelete);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$count conversation${count > 1 ? 's' : ''} deleted',
                style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: _navy,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to delete conversations: $e',
                style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
              ),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _selectedChatIds.clear();
            _isDeleting = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    if (currentUid == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF8F7FC),
        body: Center(
          child: Text(
            'Please log in to view messages.',
            style: GoogleFonts.nunito(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _navy.withValues(alpha: 0.6),
            ),
          ),
        ),
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: FirebaseService.instance.streamUserChatThreads(currentUid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('⚠️ Firestore streamUserChatThreads error: ${snapshot.error}');
        }

        final chats = snapshot.data ?? [];
        final allChatIds = chats
            .map((c) => c['chatId']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList();

        // Prune any selectedChatIds that no longer exist
        if (_selectedChatIds.isNotEmpty) {
          _selectedChatIds.removeWhere((id) => !allChatIds.contains(id));
        }

        return PopScope(
          canPop: !_isSelectionMode,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (_isSelectionMode) {
              _clearSelection();
            }
          },
          child: Scaffold(
            backgroundColor: const Color(0xFFF8F7FC),
            appBar: _isSelectionMode
                ? AppBar(
                    backgroundColor: const Color(0xFF673AB7),
                    elevation: 2,
                    leading: IconButton(
                      icon: const Icon(Icons.close_rounded, color: Colors.white),
                      tooltip: 'Cancel',
                      onPressed: _clearSelection,
                    ),
                    title: Text(
                      '${_selectedChatIds.length} Selected',
                      style: GoogleFonts.nunito(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    actions: [
                      IconButton(
                        icon: Icon(
                          _selectedChatIds.length == allChatIds.length &&
                                  allChatIds.isNotEmpty
                              ? Icons.deselect_rounded
                              : Icons.select_all_rounded,
                          color: Colors.white,
                        ),
                        tooltip: _selectedChatIds.length == allChatIds.length &&
                                allChatIds.isNotEmpty
                            ? 'Deselect All'
                            : 'Select All',
                        onPressed: () => _selectAll(allChatIds),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded,
                            color: Colors.white),
                        tooltip: 'Delete Selected',
                        onPressed: _isDeleting
                            ? null
                            : () => _confirmDeleteSelectedChats(context),
                      ),
                      const SizedBox(width: 4),
                    ],
                  )
                : AppBar(
                    backgroundColor: Colors.white,
                    elevation: 0.5,
                    title: Text(
                      'Messages & Coordination',
                      style: GoogleFonts.nunito(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: _navy,
                      ),
                    ),
                  ),
            body: Column(
              children: [
                if (_isDeleting)
                  const LinearProgressIndicator(
                    color: Color(0xFF673AB7),
                    backgroundColor: Color(0xFFEDE7F6),
                    minHeight: 3,
                  ),
                Expanded(
                  child: snapshot.connectionState == ConnectionState.waiting
                      ? const Center(
                          child: CircularProgressIndicator(
                              color: _lavender, strokeWidth: 2),
                        )
                      : chats.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F0F5),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: _navy.withValues(alpha: 0.08),
                                          width: 1.0,
                                        ),
                                      ),
                                      child: Image.asset(
                                        'assets/images/cattalking.png',
                                        width: 76,
                                        height: 76,
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'No Messages Yet',
                                      style: GoogleFonts.nunito(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w900,
                                        color: _navy,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'When you coordinate a foster handover or rescue with another member, your 1-on-1 chats will appear here.',
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
                            )
                          : ListView.separated(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              itemCount: chats.length,
                              separatorBuilder: (context, index) =>
                                  Divider(height: 1, color: _navy.withValues(alpha: 0.06)),
                              itemBuilder: (context, index) {
                                final chat = chats[index];
                                final chatId = chat['chatId']?.toString() ?? '';
                                final sightingId = chat['sightingId']?.toString() ?? '';
                                final lastMsg = chat['lastMessage']?.toString() ?? 'Active Chat';
                                final lastSender =
                                    chat['lastSenderName']?.toString() ?? 'Member';
                                final participants =
                                    (chat['participants'] as List<dynamic>?)?.cast<String>() ?? [];
                                final otherUid = participants.firstWhere(
                                  (p) => p != currentUid,
                                  orElse: () => '',
                                );
                                final blockedBy =
                                    (chat['blockedBy'] as List<dynamic>?)?.cast<String>() ?? [];
                                final isBlocked = blockedBy.isNotEmpty;

                                final isUnread = FirebaseService.isChatUnread(chat, currentUid);
                                final timeStr = _formatChatTime(chat['lastUpdatedAt']);
                                final isSelected = _selectedChatIds.contains(chatId);

                                return StreamBuilder<Sighting?>(
                                  stream: FirebaseService.instance.streamSightingById(sightingId),
                                  builder: (context, sSnap) {
                                    final s = sSnap.data;
                                    final sightingTitle =
                                        s?.displayTitle ?? chat['sightingTitle'] ?? 'Rescue Sighting';
                                    final otherName = s != null
                                        ? (s.reporterId == currentUid
                                            ? (s.careTakerName ?? s.pendingHandoverRescuerName ?? 'Volunteer')
                                            : s.reporterName)
                                        : (chat['otherUserName'] ?? 'Member');
                                    final photo = s?.photoUrls.isNotEmpty == true
                                        ? s!.photoUrls.first
                                        : (chat['sightingPhoto']?.toString() ?? '');

                                    return ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                      tileColor: isSelected
                                          ? const Color(0xFF673AB7).withValues(alpha: 0.1)
                                          : (isUnread
                                              ? const Color(0xFF673AB7).withValues(alpha: 0.04)
                                              : Colors.transparent),
                                      shape: isSelected
                                          ? const Border(
                                              left: BorderSide(
                                                  color: Color(0xFF673AB7), width: 4),
                                            )
                                          : (isUnread
                                              ? const Border(
                                                  left: BorderSide(
                                                      color: Color(0xFF673AB7), width: 3.5),
                                                )
                                              : null),
                                      leading: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_isSelectionMode)
                                            Padding(
                                              padding: const EdgeInsets.only(right: 12),
                                              child: AnimatedContainer(
                                                duration: const Duration(milliseconds: 180),
                                                width: 22,
                                                height: 22,
                                                decoration: BoxDecoration(
                                                  color: isSelected
                                                      ? const Color(0xFF673AB7)
                                                      : Colors.white,
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: isSelected
                                                        ? const Color(0xFF673AB7)
                                                        : _navy.withValues(alpha: 0.35),
                                                    width: 2,
                                                  ),
                                                  boxShadow: isSelected
                                                      ? [
                                                          BoxShadow(
                                                            color: const Color(0xFF673AB7)
                                                                .withValues(alpha: 0.35),
                                                            blurRadius: 4,
                                                            offset: const Offset(0, 1),
                                                          ),
                                                        ]
                                                      : null,
                                                ),
                                                child: isSelected
                                                    ? const Icon(Icons.check_rounded,
                                                        size: 14, color: Colors.white)
                                                    : null,
                                              ),
                                            ),
                                          Stack(
                                            clipBehavior: Clip.none,
                                            children: [
                                              Container(
                                                width: 46,
                                                height: 46,
                                                decoration: BoxDecoration(
                                                  color: isSelected
                                                      ? const Color(0xFF673AB7)
                                                          .withValues(alpha: 0.2)
                                                      : (isUnread
                                                          ? const Color(0xFF673AB7)
                                                              .withValues(alpha: 0.14)
                                                          : _lavLight),
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: isSelected || isUnread
                                                        ? const Color(0xFF673AB7)
                                                        : _lavender.withValues(alpha: 0.3),
                                                    width: isSelected || isUnread ? 2 : 1,
                                                  ),
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    otherName.isNotEmpty
                                                        ? otherName.substring(0, 1).toUpperCase()
                                                        : '🐾',
                                                    style: GoogleFonts.nunito(
                                                      fontSize: 18,
                                                      fontWeight: FontWeight.w900,
                                                      color: const Color(0xFF673AB7),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              if (photo.isNotEmpty)
                                                Positioned(
                                                  bottom: 0,
                                                  right: 0,
                                                  child: Container(
                                                    width: 16,
                                                    height: 16,
                                                    decoration: const BoxDecoration(
                                                      color: Colors.white,
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: const Icon(Icons.pets,
                                                        size: 11, color: _lavender),
                                                  ),
                                                ),
                                              if (isUnread && !_isSelectionMode)
                                                Positioned(
                                                  top: -1,
                                                  right: -1,
                                                  child: Container(
                                                    width: 13,
                                                    height: 13,
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF673AB7),
                                                      shape: BoxShape.circle,
                                                      border: Border.all(color: Colors.white, width: 2),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: const Color(0xFF673AB7)
                                                              .withValues(alpha: 0.4),
                                                          blurRadius: 4,
                                                          offset: const Offset(0, 1),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    otherName,
                                                    style: GoogleFonts.nunito(
                                                      fontSize: 14.5,
                                                      fontWeight: isUnread
                                                          ? FontWeight.w900
                                                          : FontWeight.w700,
                                                      color: _navy,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                if (isUnread) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    width: 8,
                                                    height: 8,
                                                    decoration: const BoxDecoration(
                                                      color: Color(0xFF673AB7),
                                                      shape: BoxShape.circle,
                                                    ),
                                                  ),
                                                ],
                                                if (isBlocked) ...[
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 6, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: Colors.red.withValues(alpha: 0.12),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      'Blocked',
                                                      style: GoogleFonts.nunito(
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.w800,
                                                        color: Colors.red.shade800,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          Text(
                                            'Re: $sightingTitle',
                                            style: GoogleFonts.nunito(
                                              fontSize: 11,
                                              fontWeight:
                                                  isUnread ? FontWeight.w800 : FontWeight.w700,
                                              color: isUnread
                                                  ? const Color(0xFF673AB7)
                                                  : const Color(0xFF673AB7)
                                                      .withValues(alpha: 0.8),
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: Text(
                                          '$lastSender: $lastMsg',
                                          style: GoogleFonts.nunito(
                                            fontSize: 12.5,
                                            color: isUnread
                                                ? _navy.withValues(alpha: 0.95)
                                                : _navy.withValues(alpha: 0.6),
                                            fontWeight:
                                                isUnread ? FontWeight.w800 : FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      trailing: _isSelectionMode
                                          ? (timeStr.isNotEmpty
                                              ? Text(
                                                  timeStr,
                                                  style: GoogleFonts.nunito(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w600,
                                                    color: _navy.withValues(alpha: 0.45),
                                                  ),
                                                )
                                              : null)
                                          : Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                  children: [
                                                    if (timeStr.isNotEmpty)
                                                      Text(
                                                        timeStr,
                                                        style: GoogleFonts.nunito(
                                                          fontSize: 11,
                                                          fontWeight: isUnread
                                                              ? FontWeight.w900
                                                              : FontWeight.w600,
                                                          color: isUnread
                                                              ? const Color(0xFF673AB7)
                                                              : _navy.withValues(alpha: 0.45),
                                                        ),
                                                      ),
                                                    const SizedBox(height: 4),
                                                    if (isUnread)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(
                                                            horizontal: 6, vertical: 2),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFF673AB7),
                                                          borderRadius: BorderRadius.circular(10),
                                                          boxShadow: [
                                                            BoxShadow(
                                                              color: const Color(0xFF673AB7)
                                                                  .withValues(alpha: 0.35),
                                                              blurRadius: 4,
                                                              offset: const Offset(0, 1),
                                                            ),
                                                          ],
                                                        ),
                                                        child: Text(
                                                          'NEW',
                                                          style: GoogleFonts.nunito(
                                                            fontSize: 9,
                                                            fontWeight: FontWeight.w900,
                                                            color: Colors.white,
                                                            letterSpacing: 0.5,
                                                          ),
                                                        ),
                                                      )
                                                    else
                                                      const SizedBox(height: 14),
                                                  ],
                                                ),
                                                PopupMenuButton<String>(
                                                  icon: const Icon(Icons.more_vert,
                                                      size: 20, color: Colors.grey),
                                                  shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(12)),
                                                  onSelected: (val) {
                                                    if (val == 'mark_read') {
                                                      FirebaseService.instance.markChatAsRead(
                                                        chatId: chatId,
                                                        userId: currentUid,
                                                      );
                                                    } else if (val == 'delete') {
                                                      _confirmDeleteChat(context, chatId, otherName);
                                                    }
                                                  },
                                                  itemBuilder: (ctx) => [
                                                    if (isUnread)
                                                      PopupMenuItem(
                                                        value: 'mark_read',
                                                        child: Row(
                                                          children: [
                                                            const Icon(Icons.done_all_rounded,
                                                                color: Color(0xFF673AB7), size: 18),
                                                            const SizedBox(width: 8),
                                                            Text(
                                                              'Mark as Read',
                                                              style: GoogleFonts.nunito(
                                                                fontWeight: FontWeight.w700,
                                                                color: const Color(0xFF673AB7),
                                                                fontSize: 13,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    PopupMenuItem(
                                                      value: 'delete',
                                                      child: Row(
                                                        children: [
                                                          const Icon(Icons.delete_outline_rounded,
                                                              color: Colors.red, size: 18),
                                                          const SizedBox(width: 8),
                                                          Text(
                                                            'Delete Conversation',
                                                            style: GoogleFonts.nunito(
                                                              fontWeight: FontWeight.w700,
                                                              color: Colors.red,
                                                              fontSize: 13,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                      onLongPress: () {
                                        _toggleSelection(chatId);
                                      },
                                      onTap: () {
                                        if (_isSelectionMode) {
                                          _toggleSelection(chatId);
                                          return;
                                        }

                                        FirebaseService.instance.markChatAsRead(
                                          chatId: chatId,
                                          userId: currentUid,
                                        );
                                        if (s != null) {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => CoordinationChatScreen(
                                                sighting: s,
                                                otherUserId: otherUid,
                                                otherUserName: otherName,
                                                otherUserRole: s.reporterId == currentUid
                                                    ? 'Foster Caretaker'
                                                    : 'Reporter',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
