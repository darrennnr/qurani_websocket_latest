import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vosk_stt/stt/main/stt.dart';

Future<void> main() async {
  // Pastikan Flutter binding sudah diinisialisasi
  WidgetsFlutterBinding.ensureInitialized();

  // Inisialisasi koneksi Supabase
  await Supabase.initialize(
    url: 'https://xqguweftjklmzmrwtqet.supabase.co', // Ganti dengan URL Supabase kamu
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhxZ3V3ZWZ0amtsbXptcnd0cWV0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQzNzYxNjgsImV4cCI6MjA2OTk1MjE2OH0.JckKnoCcns114jhSUfycEmrnUWiUTySR2P0xfzBhkDU', // Ganti dengan anon key dari Supabase Project Settings
  );

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: VoskSTTCorrectionPage(suratId: 36, suratName: 'يٰسۤ',),
    );
  }
}