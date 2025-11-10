import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'firebase_options.dart';
import 'app.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  final status = await _verifyFirestoreConnection();
  runApp(MyApp(status: status));
}

/// Firestore への接続確認を起動時に一度だけ行い、結果を返す。
Future<FirebaseStatus> _verifyFirestoreConnection() async {
  try {
    final snapshot =
        await FirebaseFirestore.instance.collection('users').limit(1).get();
    final message = snapshot.docs.isEmpty
        ? 'Firestore 接続成功: users コレクションは空です。'
        : 'Firestore 接続成功: sample userId=${snapshot.docs.first.data()['userId'] ?? 'unknown'}.';
    debugPrint(message);
    return FirebaseStatus(success: true, message: message);
  } catch (error, stackTrace) {
    debugPrint('Firestore 接続に失敗しました: $error');
    debugPrintStack(stackTrace: stackTrace);
    return FirebaseStatus(success: false, message: 'Firestore 接続に失敗: $error');
  }
}

class FirebaseStatus {
  const FirebaseStatus({required this.success, required this.message});

  final bool success;
  final String message;
}

/// Firestore 接続結果をエミュレータ起動時に表示するためのラッパー。
class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.status});

  final FirebaseStatus status;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tag Game',
      debugShowCheckedModeBanner: false,
      home: FirebaseStatusScreen(status: status),
    );
  }
}

class FirebaseStatusScreen extends StatelessWidget {
  const FirebaseStatusScreen({super.key, required this.status});

  final FirebaseStatus status;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Firebase 接続確認')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              status.success ? '✅ 接続成功' : '⚠️ 接続失敗',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(status.message),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => const TagGameApp(),
                  ),
                );
              },
              child: const Text('アプリを開始'),
            ),
          ],
        ),
      ),
    );
  }
}
