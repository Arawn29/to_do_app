import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // O anki giriş yapmış kullanıcının UID'sini verir
  String? get currentUserUid => _auth.currentUser?.uid;

  // Kayıt Olma
  Future<User?> signUp(String email, String password) async {
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      return result.user;
    } catch (e) {
      print("Kayıt hatası: $e");
      return null;
    }
  }

  // Giriş Yapma
  Future<User?> signIn(String email, String password) async {
    try {
      UserCredential result = await _auth.signInWithEmailAndPassword(
          email: email, password: password);
      return result.user;
    } catch (e) {
      print("Giriş hatası: $e");
      return null;
    }
  }

  // Çıkış Yapma
  Future<void> signOut() async {
    await _auth.signOut();
  }
}