import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
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

    return Scaffold(
      backgroundColor: const Color(0xFFF8F7FC),
      appBar: AppBar(
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
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: FirebaseService.instance.streamUserChatThreads(currentUid),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _lavender, strokeWidth: 2),
            );
          }

          final chats = snapshot.data ?? [];

          if (chats.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: _lavender.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.forum_outlined,
                        size: 40,
                        color: _lavender,
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
            );
          }

          return ListView.separated(
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
                    leading: Stack(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: _lavLight,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: _lavender.withValues(alpha: 0.3)),
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
                                    fontWeight: FontWeight.w800,
                                    color: _navy,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
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
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF673AB7),
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
                          color: _navy.withValues(alpha: 0.65),
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    trailing: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert,
                          size: 20, color: Colors.grey),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      onSelected: (val) {
                        if (val == 'delete') {
                          _confirmDeleteChat(context, chatId, otherName);
                        }
                      },
                      itemBuilder: (ctx) => [
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
                    onTap: () {
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
          );
        },
      ),
    );
  }
}
