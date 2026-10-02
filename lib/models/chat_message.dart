import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime createdAt;
  final String? photoUrl;
  final bool isSystemMessage;
  final bool isReported;
  final String? reportedBy;
  final String? reportReason;
  final bool isEdited;
  final DateTime? editedAt;
  final bool isDeleted;
  final String? replyToId;
  final String? replyToSenderName;
  final String? replyToText;

  const ChatMessage({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.createdAt,
    this.photoUrl,
    this.isSystemMessage = false,
    this.isReported = false,
    this.reportedBy,
    this.reportReason,
    this.isEdited = false,
    this.editedAt,
    this.isDeleted = false,
    this.replyToId,
    this.replyToSenderName,
    this.replyToText,
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    DateTime parsedDate = DateTime.now();
    if (data['createdAt'] is Timestamp) {
      parsedDate = (data['createdAt'] as Timestamp).toDate();
    } else if (data['createdAt'] is String) {
      parsedDate = DateTime.tryParse(data['createdAt']) ?? DateTime.now();
    }

    DateTime? parsedEditedAt;
    if (data['editedAt'] is Timestamp) {
      parsedEditedAt = (data['editedAt'] as Timestamp).toDate();
    } else if (data['editedAt'] is String) {
      parsedEditedAt = DateTime.tryParse(data['editedAt']);
    }

    return ChatMessage(
      id: doc.id,
      senderId: data['senderId']?.toString() ?? '',
      senderName: data['senderName']?.toString() ?? 'User',
      text: data['text']?.toString() ?? '',
      createdAt: parsedDate,
      photoUrl: data['photoUrl']?.toString(),
      isSystemMessage: data['isSystemMessage'] == true,
      isReported: data['isReported'] == true,
      reportedBy: data['reportedBy']?.toString(),
      reportReason: data['reportReason']?.toString(),
      isEdited: data['isEdited'] == true,
      editedAt: parsedEditedAt,
      isDeleted: data['isDeleted'] == true,
      replyToId: data['replyToId']?.toString(),
      replyToSenderName: data['replyToSenderName']?.toString(),
      replyToText: data['replyToText']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'createdAt': Timestamp.fromDate(createdAt),
      'photoUrl': photoUrl,
      'isSystemMessage': isSystemMessage,
      'isReported': isReported,
      'reportedBy': reportedBy,
      'reportReason': reportReason,
      'isEdited': isEdited,
      'editedAt': editedAt != null ? Timestamp.fromDate(editedAt!) : null,
      'isDeleted': isDeleted,
      if (replyToId != null) 'replyToId': replyToId,
      if (replyToSenderName != null) 'replyToSenderName': replyToSenderName,
      if (replyToText != null) 'replyToText': replyToText,
    };
  }
}

