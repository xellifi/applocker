import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String email;
  final String role;
  final String plan;
  final DateTime? createdAt;
  final DateTime? expiryDate;

  UserModel({
    required this.uid,
    required this.email,
    required this.role,
    required this.plan,
    this.createdAt,
    this.expiryDate,
  });

  factory UserModel.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    return UserModel(
      uid: doc.id,
      email: data['email'] ?? '',
      role: data['role'] ?? 'parent',
      plan: data['plan'] ?? 'trial',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      expiryDate: (data['expiryDate'] as Timestamp?)?.toDate(),
    );
  }
}
