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
  });

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    DateTime parsedDate = DateTime.now();
    if (data['createdAt'] is Timestamp) {
      parsedDate = (data['createdAt'] as Timestamp).toDate();
    } else if (data['createdAt'] is String) {
      parsedDate = DateTime.tryParse(data['createdAt']) ?? DateTime.now();
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
    };
  }
}
