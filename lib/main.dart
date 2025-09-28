import 'package:flutter/material.dart';
import 'package:vosk_stt/stt/main/stt.dart';

Future<void> main() async {
  // Pastikan Flutter binding sudah diinisialisasi
  WidgetsFlutterBinding.ensureInitialized();

  // REMOVED: Supabase initialization - tidak diperlukan lagi
  // SQLite databases akan diinisialisasi langsung di QuranSQLiteService

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: VoskSTTCorrectionPage(suratId: 36),
    );
  }
}