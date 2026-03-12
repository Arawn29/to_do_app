import 'package:cloud_firestore/cloud_firestore.dart';
import 'main.dart'; // Item modeline erişmek için
import 'package:firebase_auth/firebase_auth.dart';
class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  // Şimdilik test için sabit bir user id kullanıyoruz
  String get userId => FirebaseAuth.instance.currentUser?.uid ?? "misafir";
  // Notu veya Klasörü Buluta Gönder
Future<void> syncItem(Item item) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  // Veriyi giriş yapan güncel kullanıcının altına yaz
  await FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid) // "AyhanTestUser" gibi statik isimleri sil!
      .collection('items')
      .doc(item.id)
      .set(item.toMap());
}
  // Notu Buluttan Sil
Future<void> deleteItem(String? id) async {
    if (id == null) return; // Eğer id null ise işlemi iptal et
    await _db
        .collection('users')
        .doc(userId)
        .collection('items')
        .doc(id.toString())
        .delete();
  }
}