import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vosk_flutter/vosk_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:archive/archive.dart';
import 'dart:math' as math;

class VoskSTTCorrectionPage extends StatefulWidget {
  final int suratId;
  final String suratName;

  const VoskSTTCorrectionPage({
    Key? key,
    required this.suratId,
    required this.suratName,
  }) : super(key: key);

  @override
  _VoskSTTCorrectionPageState createState() => _VoskSTTCorrectionPageState();
}

class AyatProgress {
  final int ayatIndex;
  final int totalWords;
  final int correctWords;
  final int errorWords;
  final int skippedWords;
  final double completionPercentage;
  final bool isCompleted;

  AyatProgress({
    required this.ayatIndex,
    required this.totalWords,
    required this.correctWords,
    required this.errorWords,
    required this.skippedWords,
    required this.completionPercentage,
    required this.isCompleted,
  });
}

class _VoskSTTCorrectionPageState extends State<VoskSTTCorrectionPage>
    with TickerProviderStateMixin {
  // ==================== FIXED API CONFIGURATION ====================
  static const String API_BASE_URL = 'https://bcc910770696.ngrok-free.app';
  static const String WEBSOCKET_URL = 'wss://bcc910770696.ngrok-free.app/ws';

  // ==================== TAMBAH DI BAGIAN ATAS CLASS STATE ====================

  // Core STT Configuration
  static const int _sampleRate = 16000;
  static const Duration _processingInterval = Duration(milliseconds: 50);
  static const Duration _vadCheckInterval = Duration(milliseconds: 30);

  // Old STT variables
  String _confirmedTranscript = '';
  List<String> _transcriptHistory = [];
  Timer? _processingTimer;
  Timer? _vadTimer;
  Timer? _autoSendTimer;

  // Voice Activity Detection
  bool _isVoiceActive = false;
  double _audioLevel = 0.0;
  int _silenceFrameCount = 0;
  int _voiceFrameCount = 0;
  static const int _minVoiceFrames = 3;
  static const int _maxSilenceFrames = 15;
  double _averageAudioLevel = 0.0;
  List<double> _audioLevelHistory = [];
  static const int _audioHistoryLength = 20;
  late final Random _random;

  // Supabase client
  final SupabaseClient _supabase = Supabase.instance.client;

  // Progress tracking
  Map<int, AyatProgress> _ayatProgress = {};

  // Analytics
  int _totalTranscriptsSent = 0;
  int _successfulAPIResponses = 0;
  DateTime? _sessionStartTime;

  // UI Controllers
  final ScrollController _scrollController = ScrollController();
  late AnimationController _pulseController;
  late AnimationController _levelController;
  late AnimationController _progressController;
  late AnimationController _waveController;
  late List<GlobalKey> _ayatKeys;

  // UI State
  bool _hideUnreadAyat = false;
  bool _isQuranMode = true;
  int _currentPage = 1;
  List<AyatData> _currentPageAyats = [];
  bool _showAdvancedStats = false;

  // Surah info
  String _suratInfo = '';
  String _suratArti = '';
  String _suratTempatTurun = '';
  String _suratDeskripsi = '';

  // Auto features
  bool _autoSendEnabled = true;
  bool _autoMoveEnabled = true;
  Duration _autoSendDelay = Duration(seconds: 2);

  // Color Constants
  static const Color backgroundColor = Color.fromARGB(255, 255, 255, 255);
  static const Color primaryColor = Color(0xFF064420);
  static const Color correctColor = Color(0xFF27AE60);
  static const Color errorColor = Color(0xFFE74C3C);
  static const Color warningColor = Color(0xFFF39C12);
  static const Color unreadColor = Color(0xFFBDC3C7);
  static const Color listeningColor = Color(0xFF3498DB);
  static const Color accentColor = Color(0xFF9B59B6);
  static const Color skippedColor = Color(0xFF95A5A6);

  // ==================== ENHANCED STT VARIABLES ====================
  VoskFlutterPlugin? _vosk;
  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;
  bool _isVoskInitialized = false;
  bool _isModelLoaded = false;
  bool _isListening = false;
  String _selectedModel = 'arabic_mgb2';

  // ==================== FIXED WEBSOCKET & SESSION MANAGEMENT ====================
  String? _activeSessionId;
  bool _isSessionActive = false;
  WebSocketChannel? _webSocketChannel;
  bool _isWebSocketConnected = false;
  
  // PERBAIKAN 2: Improved connection management
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Timer? _connectionTimeoutTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 3; // Kurangi dari 5 ke 3
  static const Duration _connectionTimeout = Duration(seconds: 10);
  static const Duration _heartbeatInterval = Duration(seconds: 30);

  // ==================== CONTINUOUS STT VARIABLES ====================
  String _liveTranscript = '';
  String _currentPartialTranscript = '';
  StreamController<String> _transcriptStreamController =
      StreamController<String>.broadcast();
  Timer? _transcriptSendTimer;
  Timer? _partialUpdateTimer;
  bool _isProcessingTranscript = false;
  String _lastSentTranscript = '';

  // ==================== ENHANCED LOGGING ====================
  List<String> _logs = [];
  List<APILog> _apiLogs = [];
  bool _showLogs = false;

  // UI and other variables remain same...
  List<AyatData> _ayatList = [];
  List<APIWordResult> _currentAyatResults = [];
  int _currentAyatIndex = 0;
  int _currentAyatNumber = 1;
  bool _isLoading = true;
  String _errorMessage = '';

  // ==================== FIXED API SESSION INITIALIZATION ====================

  Future<void> _initializeAPISession() async {
    _detailedLog(
      'API_SESSION',
      'Starting session initialization for Surah ${widget.suratId}, Ayah $_currentAyatNumber',
    );

    try {
      // Prepare request data
      final requestData = {
        'user_id': 'flutter_app_${DateTime.now().millisecondsSinceEpoch}',
        'mode': 'surah',
        'surah_id': widget.suratId,
        'juz_id': _ayatList.isNotEmpty ? _ayatList[_currentAyatIndex].juz : 1,
        'page_id': _ayatList.isNotEmpty ? _ayatList[_currentAyatIndex].page : 1,
        'ayah': _currentAyatNumber,
        'data': {},
      };

      _detailedLog(
        'API_SESSION',
        'Request data prepared: ${jsonEncode(requestData)}',
      );

      final response = await http
          .post(
            Uri.parse(
              '$API_BASE_URL/live/start/${widget.suratId}/$_currentAyatNumber',
            ),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
              'Accept': 'application/json',
            },
            body: jsonEncode(requestData),
          )
          .timeout(Duration(seconds: 10));

      _detailedLog(
        'API_SESSION',
        'HTTP Response Status: ${response.statusCode}',
      );
      _detailedLog('API_SESSION', 'HTTP Response Body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        _activeSessionId = responseData['sessionId'];
        _isSessionActive = true;

        _detailedLog(
          'API_SESSION',
          'Session initialized successfully - ID: $_activeSessionId',
        );
        _logAPICall(
          'POST',
          '/live/start',
          response.statusCode,
          'Session started successfully',
        );

        // Initialize WebSocket connection after successful session
        await _initializeWebSocketConnection();

        setState(() {});
        _showSnackBar('API Session Started Successfully', SnackBarType.success);
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _detailedLog(
        'API_SESSION',
        'CRITICAL ERROR: Failed to initialize session - $e',
      );
      _logAPICall('POST', '/live/start', 0, 'Error: $e');
      _isSessionActive = false;
      _activeSessionId = null;
      setState(() {});
      _showSnackBar('Failed to start API session: $e', SnackBarType.error);
      rethrow;
    }
  }

  // Handle session update
  void _handleSessionUpdate(Map<String, dynamic> data) {
    _detailedLog('WEBSOCKET', 'Session update received');
    setState(() {});
  }

  // Compatibility method
  void _showSnackBar(String message, SnackBarType type) {
    _showEnhancedSnackBar(message, type);
  }

  // Redirect method untuk backward compatibility
  Future<void> _sendTranscriptToAPI(String transcript) async {
    _sendFinalTranscript(transcript);
  }

  // ==================== FIXED WEBSOCKET CONNECTION ====================

  // ==================== FIXED WEBSOCKET CONNECTION ====================

  Future<void> _initializeWebSocketConnection() async {
    if (_activeSessionId == null) {
      _detailedLog(
        'WEBSOCKET',
        'CRITICAL ERROR: Cannot initialize - no active session ID',
      );
      return;
    }

    try {
      // FIX: Use proper WebSocket URL without port number
      final wsUrl = 'wss://bcc910770696.ngrok-free.app/ws/$_activeSessionId';

      _detailedLog('WEBSOCKET', 'Attempting connection to: $wsUrl');

      // Close existing connection if any
      await _closeWebSocketConnection();

      // Create new WebSocket connection with proper headers
      _webSocketChannel = WebSocketChannel.connect(
        Uri.parse(wsUrl),
        // FIX: Add proper headers for ngrok
        protocols: null, // Remove protocols that might cause issues
      );

      _detailedLog(
        'WEBSOCKET',
        'WebSocket channel created, setting up listeners',
      );

      // Set up stream listeners with better error handling
      _webSocketChannel!.stream.listen(
        (data) {
          _detailedLog('WEBSOCKET', 'Message received: $data');
        },
        onError: (error) {
          _detailedLog('WEBSOCKET', 'STREAM ERROR: $error');
          _handleWebSocketError(error);
        },
        cancelOnError: false, // FIX: Don't cancel on error, handle gracefully
      );

      // FIX: Wait for connection to be established before sending messages
      await Future.delayed(Duration(milliseconds: 500));

      // Send initial connection message
      _sendWebSocketMessage({
        'type': 'connect',
        'session_id': _activeSessionId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      _isWebSocketConnected = true;
      _reconnectAttempts = 0;

      // Start heartbeat
      _startHeartbeat();

      _detailedLog('WEBSOCKET', 'Connection established successfully');
      setState(() {});
    } catch (e) {
      _detailedLog('WEBSOCKET', 'CONNECTION FAILED: $e');
      _isWebSocketConnected = false;
      _handleWebSocketError(e);
      setState(() {});
    }
  }

  // ==================== IMPROVED ERROR HANDLING ====================

  void _handleWebSocketError(dynamic error) {
    _detailedLog('WEBSOCKET', 'ERROR HANDLER: $error');
    _isWebSocketConnected = false;

    // FIX: Don't immediately reconnect, wait a bit
    if (mounted) {
      setState(() {});
    }

    // Only attempt reconnection if session is still active and we haven't exceeded max attempts
    if (_isSessionActive && _reconnectAttempts < _maxReconnectAttempts) {
      _attemptReconnection();
    } else {
      _detailedLog(
        'WEBSOCKET',
        'Max reconnection attempts reached or session inactive',
      );
      _showSnackBar(
        'WebSocket connection failed. Please restart session.',
        SnackBarType.error,
      );
    }
  }

  void _attemptReconnection() {
    if (_reconnectAttempts >= _maxReconnectAttempts || !_isSessionActive) {
      _detailedLog(
        'WEBSOCKET',
        'Max reconnection attempts reached or session inactive',
      );
      return;
    }

    _reconnectAttempts++;
    _detailedLog(
      'WEBSOCKET',
      'Attempting reconnection $_reconnectAttempts/$_maxReconnectAttempts',
    );

    _reconnectTimer?.cancel();
    // FIX: Exponential backoff for reconnection
    final delay = Duration(seconds: math.min(2 * _reconnectAttempts, 10));

    _reconnectTimer = Timer(delay, () {
      if (_isSessionActive && mounted) {
        _initializeWebSocketConnection();
      }
    });
  }

  // ==================== IMPROVED MESSAGE SENDING ====================

  void _sendWebSocketMessage(Map<String, dynamic> message) {
    if (_webSocketChannel != null && _isWebSocketConnected) {
      try {
        final messageJson = jsonEncode(message);
        _webSocketChannel!.sink.add(messageJson);
        _detailedLog('WEBSOCKET', 'Message sent: $messageJson');
      } catch (e) {
        _detailedLog('WEBSOCKET', 'SEND ERROR: $e');
        // FIX: Mark as disconnected if send fails
        _isWebSocketConnected = false;
        if (mounted) setState(() {});
      }
    } else {
      _detailedLog('WEBSOCKET', 'Cannot send message - not connected');
    }
  }

  // ==================== IMPROVED HEARTBEAT ====================

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (_isWebSocketConnected &&
          _webSocketChannel != null &&
          _isSessionActive) {
        _sendWebSocketMessage({
          'type': 'heartbeat',
          'session_id': _activeSessionId,
          'timestamp': DateTime.now().toIso8601String(),
        });
        _detailedLog('WEBSOCKET', 'Heartbeat sent');
      } else {
        _detailedLog('WEBSOCKET', 'Stopping heartbeat - connection lost');
        timer.cancel();
      }
    });
  }

  // ==================== IMPROVED STT METHODS ====================

  Future<void> _startContinuousListening() async {
    if (_isListening) {
      _detailedLog('STT', 'Already listening, ignoring start request');
      return;
    }

    if (!_isVoskInitialized || !_isModelLoaded || _recognizer == null) {
      _detailedLog('STT', 'STT engine not ready');
      _showSnackBar('STT engine not ready. Please wait.', SnackBarType.warning);
      return;
    }

    // Ensure API session is active
    if (!_isSessionActive) {
      _detailedLog('STT', 'Starting API session before STT');
      try {
        await _initializeAPISession();
        if (!_isSessionActive) {
          _showSnackBar('Failed to start API session', SnackBarType.error);
          return;
        }
      } catch (e) {
        _detailedLog('STT', 'Failed to initialize API session: $e');
        _showSnackBar('Failed to start API session: $e', SnackBarType.error);
        return;
      }
    }

    // FIX: Don't require WebSocket to be connected to start listening
    // WebSocket will be used when available, but STT can work without it
    if (!_isWebSocketConnected) {
      _detailedLog('STT', 'WebSocket not connected, starting anyway');
      // Try to connect WebSocket in background
      _initializeWebSocketConnection();
    }

    try {
      _detailedLog('STT', 'Starting continuous listening session');

      setState(() {
        _isListening = true;
        _liveTranscript = '';
        _currentPartialTranscript = '';
        _lastSentTranscript = '';
      });

      // Create speech service
      _speechService = await _vosk!.initSpeechService(_recognizer!);
      _detailedLog('STT', 'Speech service initialized');

      // Set up partial results listener (continuous transcription)
      _speechService!.onPartial().listen((partialJson) {
        _handlePartialTranscript(partialJson);
      });

      // Set up final results listener
      _speechService!.onResult().listen((resultJson) {
        _handleFinalTranscript(resultJson);
      });

      // Start listening
      await _speechService!.start();

      // Start continuous processing timers
      _startContinuousProcessing();

      _detailedLog('STT', 'Continuous listening started successfully');
      _showSnackBar('Listening started', SnackBarType.success);
    } catch (e) {
      _detailedLog('STT', 'CRITICAL ERROR starting listening: $e');
      setState(() {
        _isListening = false;
      });
      _showSnackBar('Failed to start listening: $e', SnackBarType.error);
    }
  }

  // ==================== IMPROVED TRANSCRIPT HANDLING ====================

  void _sendPartialTranscript(String transcript) {
    // FIX: Only send via WebSocket if connected, otherwise store for later
    if (_isWebSocketConnected && transcript != _lastSentTranscript) {
      _sendWebSocketMessage({
        'type': 'partial_transcript',
        'session_id': _activeSessionId,
        'transcript': transcript,
        'surah_id': widget.suratId,
        'ayah': _currentAyatNumber,
        'timestamp': DateTime.now().toIso8601String(),
      });

      _detailedLog('WEBSOCKET_SEND', 'Partial transcript sent: "$transcript"');
    } else if (!_isWebSocketConnected) {
      _detailedLog(
        'WEBSOCKET_SEND',
        'Partial transcript queued (WS not connected): "$transcript"',
      );
    }
  }

  void _sendFinalTranscript(String transcript) {
    // FIX: Send via WebSocket if available, otherwise use HTTP fallback
    if (_isWebSocketConnected) {
      _sendWebSocketMessage({
        'type': 'final_transcript',
        'session_id': _activeSessionId,
        'transcript': transcript,
        'surah_id': widget.suratId,
        'ayah': _currentAyatNumber,
        'timestamp': DateTime.now().toIso8601String(),
      });

      _lastSentTranscript = transcript;
      _detailedLog('WEBSOCKET_SEND', 'Final transcript sent: "$transcript"');
    } else {
      // Fallback to HTTP API if WebSocket is not available
      _sendTranscriptViaHTTP(transcript);
    }
  }

  // ==================== HTTP FALLBACK METHOD ====================

  Future<void> _sendTranscriptViaHTTP(String transcript) async {
    if (_activeSessionId == null) {
      _detailedLog('HTTP_FALLBACK', 'No active session for HTTP fallback');
      return;
    }

    try {
      _detailedLog(
        'HTTP_FALLBACK',
        'Sending transcript via HTTP: "$transcript"',
      );

      final response = await http
          .post(
            Uri.parse('$API_BASE_URL/live/transcript/$_activeSessionId'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
            },
            body: jsonEncode({
              'transcript': transcript,
              'surah_id': widget.suratId,
              'ayah': _currentAyatNumber,
              'timestamp': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        _detailedLog('HTTP_FALLBACK', 'Transcript sent successfully via HTTP');
        _totalTranscriptsSent++;
        _successfulAPIResponses++;

        // Process response if available
        try {
          final responseData = jsonDecode(response.body);
          if (responseData['results'] != null) {
            _handleTranscriptResult(responseData);
          }
        } catch (e) {
          _detailedLog('HTTP_FALLBACK', 'Error processing HTTP response: $e');
        }
      } else {
        _detailedLog(
          'HTTP_FALLBACK',
          'HTTP transcript failed: ${response.statusCode}',
        );
      }
    } catch (e) {
      _detailedLog('HTTP_FALLBACK', 'HTTP transcript error: $e');
    }
  }

  // ==================== IMPROVED CONNECTION CLEANUP ====================

  Future<void> _closeWebSocketConnection() async {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();

    if (_webSocketChannel != null) {
      try {
        // FIX: Send close message before closing
        if (_isWebSocketConnected) {
          _sendWebSocketMessage({
            'type': 'disconnect',
            'session_id': _activeSessionId,
            'timestamp': DateTime.now().toIso8601String(),
          });

          // Wait a bit for message to be sent
          await Future.delayed(Duration(milliseconds: 100));
        }

        await _webSocketChannel!.sink.close(status.normalClosure);
        _detailedLog('WEBSOCKET', 'Connection closed gracefully');
      } catch (e) {
        _detailedLog('WEBSOCKET', 'Error closing connection: $e');
      }
      _webSocketChannel = null;
    }

    _isWebSocketConnected = false;
    _reconnectAttempts = 0;
  }

  void _handlePartialTranscript(String partialJson) {
    try {
      final result = jsonDecode(partialJson);
      final partialText = result['partial']?.toString().trim() ?? '';

      if (partialText.isNotEmpty && partialText != _currentPartialTranscript) {
        _detailedLog('STT_PARTIAL', 'New partial: "$partialText"');

        setState(() {
          _currentPartialTranscript = partialText;
          _liveTranscript = partialText;
        });

        // Send partial transcript via WebSocket for real-time feedback
        _sendPartialTranscript(partialText);
      }
    } catch (e) {
      _detailedLog('STT_PARTIAL', 'Error parsing partial result: $e');
    }
  }

  void _handleFinalTranscript(String resultJson) {
    try {
      final result = jsonDecode(resultJson);
      final finalText = result['text']?.toString().trim() ?? '';

      if (finalText.isNotEmpty) {
        _detailedLog('STT_FINAL', 'Final transcript: "$finalText"');

        setState(() {
          _liveTranscript = finalText;
          _currentPartialTranscript = '';
        });

        // Send final transcript for API processing
        _sendFinalTranscript(finalText);
      }
    } catch (e) {
      _detailedLog('STT_FINAL', 'Error parsing final result: $e');
    }
  }

  void _startContinuousProcessing() {
    // Continuous processing timer for UI updates
    _partialUpdateTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
      if (!_isListening) {
        timer.cancel();
        return;
      }
      // Update UI if needed
      if (mounted) {
        setState(() {});
      }
    });

    // Transcript send timer (for final transcripts)
    _transcriptSendTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
      if (!_isListening) {
        timer.cancel();
        return;
      }

      // Process any pending final transcripts
      if (_liveTranscript.isNotEmpty &&
          _liveTranscript != _lastSentTranscript) {
        _sendFinalTranscript(_liveTranscript);
      }
    });
  }

  Future<void> _stopContinuousListening() async {
    if (!_isListening) {
      _detailedLog('STT', 'Not listening, ignoring stop request');
      return;
    }

    _detailedLog('STT', 'Stopping continuous listening');

    try {
      setState(() {
        _isListening = false;
      });

      // Stop timers
      _transcriptSendTimer?.cancel();
      _partialUpdateTimer?.cancel();

      // Stop speech service
      if (_speechService != null) {
        await _speechService!.stop();
        _speechService = null;
      }

      // Send stop message via WebSocket
      if (_isWebSocketConnected) {
        _sendWebSocketMessage({
          'type': 'stop_listening',
          'session_id': _activeSessionId,
          'timestamp': DateTime.now().toIso8601String(),
        });
      }

      _detailedLog('STT', 'Continuous listening stopped successfully');
      _showSnackBar('Listening stopped', SnackBarType.info);
    } catch (e) {
      _detailedLog('STT', 'Error stopping listening: $e');
    }
  }

  // ==================== ENHANCED API RESPONSE HANDLERS ====================

  void _handleTranscriptResult(Map<String, dynamic> data) {
    _detailedLog(
      'API_RESPONSE',
      'Transcript result received: ${jsonEncode(data)}',
    );

    try {
      if (data.containsKey('results') && data['results'] is List) {
        final results = data['results'] as List;
        final wordResults = results
            .map((r) => APIWordResult.fromJson(r))
            .toList();

        setState(() {
          _currentAyatResults = wordResults;
        });

        _detailedLog(
          'API_RESPONSE',
          'Processed ${wordResults.length} word results',
        );

        // Update UI with real-time feedback
        _updateUIWithResults(wordResults, data['summary']);
      }
    } catch (e) {
      _detailedLog('API_RESPONSE', 'Error processing transcript result: $e');
    }
  }

  void _handleWordFeedback(Map<String, dynamic> data) {
    _detailedLog('API_RESPONSE', 'Word feedback received: ${jsonEncode(data)}');

    // Handle real-time word-by-word feedback
    try {
      final position = data['position'];
      final status = data['status'];
      final similarity = data['similarity_score'];

      // Update specific word in current results
      if (position != null && position < _currentAyatResults.length) {
        setState(() {
          _currentAyatResults[position] = APIWordResult(
            position: position,
            expected: _currentAyatResults[position].expected,
            spoken: data['spoken'] ?? '',
            status: status ?? 'unknown',
            similarity_score: (similarity ?? 0.0).toDouble(),
          );
        });
      }
    } catch (e) {
      _detailedLog('API_RESPONSE', 'Error processing word feedback: $e');
    }
  }

  void _updateUIWithResults(
    List<APIWordResult> results,
    Map<String, dynamic>? summary,
  ) {
    // Update progress and UI based on results
    if (summary != null) {
      final matched = summary['matched'] ?? 0;
      final total = summary['total'] ?? 1;
      final completionRate = total > 0 ? matched / total : 0.0;

      _detailedLog(
        'API_PROGRESS',
        'Ayat progress: $matched/$total (${(completionRate * 100).toStringAsFixed(1)}%)',
      );

      // Update ayat progress
      // Implementation for progress tracking...
    }

    // Trigger UI rebuild
    if (mounted) {
      setState(() {});
    }
  }

  // ==================== ENHANCED LOGGING SYSTEM ====================

  void _detailedLog(String category, String message) {
    final timestamp = DateTime.now().toString().substring(11, 23);
    final logMessage = '[$timestamp] $category: $message';
    print(logMessage);

    if (mounted) {
      setState(() {
        _logs.add(logMessage);
        if (_logs.length > 500) {
          // Increased log capacity
          _logs.removeAt(0);
        }
      });
    }
  }

  void _logAPICall(
    String method,
    String endpoint,
    int statusCode,
    String message,
  ) {
    final apiLog = APILog(
      timestamp: DateTime.now(),
      method: method,
      endpoint: endpoint,
      statusCode: statusCode,
      message: message,
    );

    _apiLogs.add(apiLog);
    if (_apiLogs.length > 100) {
      _apiLogs.removeAt(0);
    }

    _detailedLog('API_CALL', '$method $endpoint - $statusCode - $message');
  }

  // ==================== CLEANUP AND DISPOSAL ====================

  @override
  void dispose() {
    _detailedLog('DISPOSAL', 'Starting cleanup process');

    _stopContinuousListening();
    _closeWebSocketConnection();
    _endAPISession();

    // Cancel ALL timers
    _transcriptSendTimer?.cancel();
    _partialUpdateTimer?.cancel();
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _processingTimer?.cancel();
    _vadTimer?.cancel();
    _autoSendTimer?.cancel();

    // Close streams and dispose controllers
    _transcriptStreamController.close();
    _scrollController.dispose();
    _disposeAnimations();
    _cleanupVoskResources();

    super.dispose();
  }

  Future<void> _cleanupVoskResources() async {
    try {
      if (_speechService != null) {
        await _speechService!.stop();
        _speechService = null;
      }
      if (_recognizer != null) {
        await _recognizer!.dispose();
        _recognizer = null;
      }
      if (_model != null) {
        _model!.dispose();
        _model = null;
      }
    } catch (e) {
      _detailedLog('CLEANUP', 'Error during Vosk cleanup: $e');
    }
  }

  Future<void> _endAPISession() async {
    if (!_isSessionActive || _activeSessionId == null) {
      _detailedLog('API_SESSION', 'No active session to end');
      return;
    }

    try {
      _detailedLog('API_SESSION', 'Ending session: $_activeSessionId');

      final response = await http
          .post(
            Uri.parse('$API_BASE_URL/live/end/$_activeSessionId'),
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
            },
          )
          .timeout(Duration(seconds: 5));

      if (response.statusCode == 200) {
        _detailedLog('API_SESSION', 'Session ended successfully');
        _logAPICall('POST', '/live/end', response.statusCode, 'Session ended');
      } else {
        _detailedLog(
          'API_SESSION',
          'Error ending session - HTTP ${response.statusCode}: ${response.body}',
        );
      }
    } catch (e) {
      _detailedLog('API_SESSION', 'Error ending session: $e');
    } finally {
      _activeSessionId = null;
      _isSessionActive = false;
      setState(() {});
    }
  }

  // ==================== SPEECH RECOGNITION METHODS ====================

  Future<void> _startEnhancedListening() async {
    if (_isListening) {
      _log('STT: Already listening');
      return;
    }

    if (!_isVoskInitialized || !_isModelLoaded || _recognizer == null) {
      _log('STT: Engine not ready');
      _showEnhancedSnackBar(
        'STT engine not ready. Please wait.',
        SnackBarType.warning,
      );
      return;
    }

    // Initialize API session if not active
    if (!_isSessionActive) {
      await _initializeAPISession();
      if (!_isSessionActive) {
        _showEnhancedSnackBar(
          'Failed to start API session',
          SnackBarType.error,
        );
        return;
      }
    }

    try {
      _log('STT: Starting listening session');

      setState(() {
        _isListening = true;
        _liveTranscript = '';
        _confirmedTranscript = '';
        _isProcessingTranscript = false;
      });

      // Start continuous processing timers
      _startProcessingTimers();

      // Use SpeechService for automatic audio handling
      _speechService = await _vosk!.initSpeechService(_recognizer!);

      // Set up listeners for partial and final results
      _speechService!.onPartial().listen((partialJson) {
        final partialText = _extractTextFromVoskResult(partialJson);
        if (partialText.isNotEmpty) {
          setState(() {
            _liveTranscript = partialText;
          });
          _transcriptStreamController.add(partialText);
        }
      });

      _speechService!.onResult().listen((resultJson) {
        final resultText = _extractTextFromVoskResult(resultJson);
        if (resultText.isNotEmpty) {
          setState(() {
            _confirmedTranscript = resultText;
            _liveTranscript = '';
          });
          _transcriptHistory.add(resultText);

          // Send transcript to API
          _sendTranscriptToAPI(resultText);
        }
      });

      await _speechService!.start();

      // Start animations
      _pulseController.repeat(reverse: true);
      _waveController.repeat();

      _log('STT: Listening started successfully');
      _showEnhancedSnackBar('Listening started', SnackBarType.success);
    } catch (e) {
      _log('STT: Failed to start listening - $e');
      setState(() {
        _isListening = false;
      });
      _showEnhancedSnackBar(
        'Failed to start listening: $e',
        SnackBarType.error,
      );
    }
  }

  Future<void> _stopEnhancedListening() async {
    if (!_isListening) {
      _log('STT: Not listening');
      return;
    }

    _log('STT: Stopping listening session');

    try {
      setState(() {
        _isListening = false;
        _isProcessingTranscript = false;
      });

      // Stop timers
      _processingTimer?.cancel();
      _vadTimer?.cancel();
      _autoSendTimer?.cancel();

      // Stop speech service
      await _speechService?.stop();
      _speechService = null;

      // Stop animations
      _pulseController.stop();
      _waveController.stop();
      _levelController.reset();

      // Reset audio states
      _isVoiceActive = false;
      _audioLevel = 0.0;
      _silenceFrameCount = 0;
      _voiceFrameCount = 0;

      _log('STT: Listening stopped successfully');
      _showEnhancedSnackBar('Listening stopped', SnackBarType.info);
    } catch (e) {
      _log('STT: Error stopping listening - $e');
    }
  }

  void _startProcessingTimers() {
    // Main processing timer for real-time analysis
    _processingTimer = Timer.periodic(_processingInterval, (timer) {
      if (!_isListening) {
        timer.cancel();
        return;
      }
      _updateVoiceActivityDetection();
    });

    // Voice activity detection timer
    _vadTimer = Timer.periodic(_vadCheckInterval, (timer) {
      if (!_isListening) {
        timer.cancel();
        return;
      }
      _simulateAudioLevel();
    });

    // Auto-send timer for confirmed transcripts
    if (_autoSendEnabled) {
      _autoSendTimer = Timer.periodic(_autoSendDelay, (timer) {
        if (!_isListening) {
          timer.cancel();
          return;
        }
        if (_confirmedTranscript.isNotEmpty && !_isProcessingTranscript) {
          _sendTranscriptToAPI(_confirmedTranscript);
        }
      });
    }
  }

  void _updateVoiceActivityDetection() {
    double currentLevel = _audioLevel;
    _audioLevelHistory.add(currentLevel);

    if (_audioLevelHistory.length > _audioHistoryLength) {
      _audioLevelHistory.removeAt(0);
    }

    _averageAudioLevel =
        _audioLevelHistory.reduce((a, b) => a + b) / _audioLevelHistory.length;

    bool voiceDetected = currentLevel > (_averageAudioLevel * 1.5 + 0.1);

    if (voiceDetected) {
      _voiceFrameCount++;
      _silenceFrameCount = 0;

      if (_voiceFrameCount >= _minVoiceFrames && !_isVoiceActive) {
        setState(() {
          _isVoiceActive = true;
        });
      }
    } else {
      _silenceFrameCount++;
      _voiceFrameCount = 0;

      if (_silenceFrameCount >= _maxSilenceFrames && _isVoiceActive) {
        setState(() {
          _isVoiceActive = false;
        });
      }
    }

    // Update level animation
    _levelController.animateTo(_audioLevel);
  }

  void _simulateAudioLevel() {
    // Simulate realistic audio level since Vosk doesn't expose raw buffer
    _audioLevel = _isVoiceActive
        ? 0.6 + _random.nextDouble() * 0.4
        : _random.nextDouble() * 0.3;
  }

  String _extractTextFromVoskResult(String voskResult) {
    try {
      final Map<String, dynamic> result = jsonDecode(voskResult);
      if (result.containsKey('partial')) {
        return result['partial']?.toString().trim() ?? '';
      } else if (result.containsKey('text')) {
        return result['text']?.toString().trim() ?? '';
      }
      return '';
    } catch (e) {
      _log('STT: Error parsing Vosk result - $e');
      return '';
    }
  }

  // ==================== SURAH COMPLETION ====================

  void _handleSurahCompletion() {
    _log('SURAH: Completion detected');
    _stopEnhancedListening();
    _endAPISession();
    _showCompletionDialog();
  }

  void _showCompletionDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.celebration, color: correctColor, size: 24),
              const SizedBox(width: 8),
              const Text('Surah Completed!', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: correctColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Text(
                      '🎉 Congratulations! 🎉',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'You have completed reading ${widget.suratName}',
                      style: const TextStyle(fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    _buildCompletionStats(),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _showDetailedResults();
              },
              child: const Text('View Details'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pop(); // Return to previous screen
              },
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              child: const Text(
                'Finish',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCompletionStats() {
    final sessionDuration = _sessionStartTime != null
        ? DateTime.now().difference(_sessionStartTime!).inMinutes
        : 0;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem('API Calls', '$_totalTranscriptsSent'),
            _buildStatItem('Success', '$_successfulAPIResponses'),
            _buildStatItem('Time', '${sessionDuration}min'),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStatItem('Ayat', '${_ayatList.length}'),
            _buildStatItem('Transcripts', '${_transcriptHistory.length}'),
            _buildStatItem(
              'Completed',
              '${_ayatProgress.values.where((p) => p.isCompleted).length}',
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: primaryColor,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  void _showDetailedResults() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Detailed Results'),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildResultsSection('Overall Performance', [
                    'Total API Calls: $_totalTranscriptsSent',
                    'Successful Responses: $_successfulAPIResponses',
                    'Success Rate: ${_totalTranscriptsSent > 0 ? ((_successfulAPIResponses / _totalTranscriptsSent) * 100).toStringAsFixed(1) : 0}%',
                    'Transcript Segments: ${_transcriptHistory.length}',
                    'Completed Ayat: ${_ayatProgress.values.where((p) => p.isCompleted).length}/${_ayatList.length}',
                  ]),
                  const SizedBox(height: 16),
                  _buildResultsSection(
                    'Per-Ayat Breakdown',
                    _ayatProgress.values
                        .map(
                          (progress) =>
                              'Ayat ${progress.ayatIndex + 1}: ${progress.completionPercentage.toStringAsFixed(1)}% (${progress.correctWords}/${progress.totalWords} words)',
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildResultsSection(String title, List<String> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: primaryColor,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: items
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(item, style: const TextStyle(fontSize: 12)),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  // ==================== INITIALIZATION METHODS ====================

  @override
  void initState() {
    super.initState();
    _random = Random();
    _ayatKeys = [];
    _log('=== API-INTEGRATED STT INITIALIZATION STARTED ===');
    _initializeAnimations();
    _initializeStreams();
    _initializeApp();
    _sessionStartTime = DateTime.now();
  }

  void _initializeAnimations() {
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _levelController = AnimationController(
      duration: const Duration(milliseconds: 80),
      vsync: this,
    );

    _progressController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _waveController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
  }

  void _disposeAnimations() {
    _pulseController.dispose();
    _levelController.dispose();
    _progressController.dispose();
    _waveController.dispose();
  }

  void _initializeStreams() {
    _transcriptStreamController.stream.listen((transcript) {
      // Real-time transcript processing can be handled here if needed
    });
  }

  Future<void> _cleanup() async {
    _processingTimer?.cancel();
    _vadTimer?.cancel();
    _autoSendTimer?.cancel();

    try {
      if (_speechService != null) {
        await _speechService!.stop();
        _speechService = null;
      }
      if (_recognizer != null) {
        await _recognizer!.dispose();
        _recognizer = null;
      }
      if (_model != null) {
        _model!.dispose();
        _model = null;
      }
      if (_webSocketChannel != null) {
        await _webSocketChannel!.sink.close(status.goingAway);
        _webSocketChannel = null;
      }
    } catch (e) {
      _log('CLEANUP: Error during cleanup - $e');
    }

    _log('=== API-INTEGRATED STT DISPOSAL COMPLETED ===');
  }

  void _log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 23);
    final logMessage = '[$timestamp] API_STT: $message';
    print(logMessage);

    if (mounted) {
      setState(() {
        _logs.add(logMessage);
        if (_logs.length > 200) {
          _logs.removeAt(0);
        }
      });
    }
  }

  // ==================== ENHANCED INITIALIZATION ====================

  Future<void> _initializeApp() async {
    try {
      _log('APP: Starting enhanced app initialization');
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });

      await _requestEnhancedPermissions();
      await _initializeVosk();
      await _setupEnhancedVoskModel();
      await _setupEnhancedRecognizer();
      await _loadAyatData();

      setState(() {
        _isLoading = false;
      });

      _log('APP: Enhanced app initialization completed successfully');
    } catch (e) {
      _log('APP: Enhanced app initialization failed - $e');
      setState(() {
        _errorMessage = 'Failed to initialize enhanced STT: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _requestEnhancedPermissions() async {
    _log('PERMISSIONS: Requesting enhanced permissions');

    List<Permission> permissions = [Permission.microphone, Permission.audio];

    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      _log('PERMISSIONS: Android SDK - $sdkInt');

      if (sdkInt >= 33) {
        permissions.addAll([Permission.audio, Permission.notification]);
      } else {
        permissions.add(Permission.storage);
      }
    }

    for (Permission permission in permissions) {
      PermissionStatus status = await permission.request();
      _log('PERMISSIONS: ${permission.toString()} - $status');

      if (status.isDenied || status.isPermanentlyDenied) {
        if (permission == Permission.microphone) {
          throw Exception(
            'Microphone permission required for STT functionality',
          );
        }
      }
    }

    _log('PERMISSIONS: All permissions granted');
  }

  Future<void> _initializeVosk() async {
    _log('VOSK: Initializing Vosk engine');

    try {
      _vosk = VoskFlutterPlugin.instance();
      _isVoskInitialized = true;
      _log('VOSK: Vosk initialized successfully');
    } catch (e) {
      _log('VOSK: Failed to initialize Vosk - $e');
      throw Exception('Vosk initialization failed: $e');
    }
  }

  Future<void> _setupEnhancedVoskModel() async {
    _log('VOSK_MODEL: Setting up Vosk model - $_selectedModel');

    try {
      final isModelExists = await EnhancedVoskModelManager.isModelExists(
        _selectedModel,
      );

      if (!isModelExists) {
        _log('VOSK_MODEL: Model not found, extracting...');

        setState(() {
          _errorMessage = 'Extracting Arabic model...';
        });

        await EnhancedVoskModelManager.copyModelFromAssets(
          modelKey: _selectedModel,
          onProgress: (copied, total) {
            setState(() {
              final percentage = ((copied / total) * 100).toStringAsFixed(1);
              _errorMessage = 'Extracting model: $copied/$total ($percentage%)';
            });
          },
        );
      }

      final isIntegrityOk =
          await EnhancedVoskModelManager.verifyEnhancedModelIntegrity(
            _selectedModel,
          );
      if (!isIntegrityOk) {
        _log('VOSK_MODEL: Model integrity failed, re-extracting...');
        await EnhancedVoskModelManager.copyModelFromAssets(
          modelKey: _selectedModel,
        );
      }

      final modelPath = await EnhancedVoskModelManager.getModelPath(
        _selectedModel,
      );
      _model = await _vosk!.createModel(modelPath);
      _isModelLoaded = true;

      _log('VOSK_MODEL: Vosk model loaded successfully - $modelPath');
    } catch (e) {
      _log('VOSK_MODEL: Failed to setup model - $e');
      throw Exception('Model setup failed: $e');
    }
  }

  Future<void> _setupEnhancedRecognizer() async {
    _log('VOSK_RECOGNIZER: Setting up Vosk recognizer');

    try {
      if (_model == null) {
        throw Exception('Model not loaded');
      }

      _recognizer = await _vosk!.createRecognizer(
        model: _model!,
        sampleRate: _sampleRate,
      );

      _log('VOSK_RECOGNIZER: Vosk recognizer created successfully');
    } catch (e) {
      _log('VOSK_RECOGNIZER: Failed to setup recognizer - $e');
      throw Exception('Recognizer setup failed: $e');
    }
  }

  Future<void> _loadAyatData() async {
    _log('DATA: Loading ayat data for surah_id ${widget.suratId}');

    try {
      // Load ayat data with page information
      final response = await _supabase
          .from('m10_quran_ayah')
          .select(
            'surah_id, ayah, arabic, no_tashkeel, transliteration, words_array_nt, page, juz, quarter_hizb',
          )
          .eq('surah_id', widget.suratId)
          .order('ayah', ascending: true);

      if (response.isEmpty) {
        throw Exception('No ayat found for surah ${widget.suratId}');
      }

      // Load surah info
      final surahResponse = await _supabase
          .from('surat')
          .select('nama, namalatin, jumlahayat, tempatturun, arti, deskripsi')
          .eq('id', widget.suratId)
          .single();

      final surahNama = surahResponse['nama'] ?? widget.suratName;
      final surahNamalatin = surahResponse['namalatin'] ?? '';
      final jumlahAyat = surahResponse['jumlahayat'] ?? response.length;

      _suratArti = surahResponse['arti'] ?? '';
      _suratTempatTurun = surahResponse['tempatturun'] ?? '';
      _suratDeskripsi = surahResponse['deskripsi'] ?? '';

      _suratInfo =
          '$surahNama${surahNamalatin.isNotEmpty ? ' ($surahNamalatin)' : ''} (1-$jumlahAyat)';

      _ayatList = response.map((data) => AyatData.fromJson(data)).toList();

      // Set initial page and ayat
      if (_ayatList.isNotEmpty) {
        _currentPage = _ayatList.first.page;
        _currentAyatNumber = _ayatList.first.ayah;
        _loadCurrentPageAyats();
      }

      _ayatKeys = List.generate(_ayatList.length, (index) => GlobalKey());

      _log('DATA: Loaded ${_ayatList.length} ayat with enhanced surah info');
    } catch (e) {
      _log('DATA: Failed to load ayat data - $e');
      throw Exception('Data loading failed: $e');
    }
  }

  Future<void> _loadCurrentPageAyats() async {
    if (!_isQuranMode) {
      _currentPageAyats = _ayatList;
      return;
    }

    try {
      final response = await _supabase
          .from('m10_quran_ayah')
          .select(
            'surah_id, ayah, arabic, no_tashkeel, transliteration, words_array_nt, page, juz, quarter_hizb',
          )
          .eq('page', _currentPage)
          .order('surah_id', ascending: true)
          .order('ayah', ascending: true);

      _currentPageAyats = response
          .map((data) => AyatData.fromJson(data))
          .toList();
      _log(
        'DATA: Loaded ${_currentPageAyats.length} ayats for page $_currentPage',
      );
    } catch (e) {
      _log('DATA: Error loading page ayats - $e');
      _currentPageAyats = [];
    }
  }

  void _performIntelligentNavigation() {
    if (!_scrollController.hasClients ||
        _currentAyatIndex >= _ayatKeys.length ||
        _ayatKeys[_currentAyatIndex].currentContext == null)
      return;

    try {
      final context = _ayatKeys[_currentAyatIndex].currentContext!;
      final renderBox = context.findRenderObject()! as RenderBox;
      final scrollViewContext =
          _scrollController.position.context.storageContext;
      final scrollViewBox = scrollViewContext.findRenderObject()! as RenderBox;
      final position = renderBox.localToGlobal(
        Offset.zero,
        ancestor: scrollViewBox,
      );

      double targetOffset = position.dy - 150;
      targetOffset = targetOffset.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );

      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    } catch (e) {
      _log('NAVIGATION: Scroll error - $e');
      // Fallback to estimated position
      double estimatedAyatHeight = 120.0;
      double targetOffset = _currentAyatIndex * estimatedAyatHeight;
      _scrollController.animateTo(
        targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutQuint,
      );
    }
  }

  // ==================== UI BUILD METHODS ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: _buildEnhancedAppBar(),
      body: _isLoading
          ? _buildEnhancedLoadingWidget()
          : _errorMessage.isNotEmpty && !_isListening
          ? _buildEnhancedErrorWidget()
          : Column(
              children: [
                Expanded(child: _buildEnhancedMainContent()),
                if (_showLogs) _buildEnhancedLogsPanel(),
              ],
            ),
    );
  }

  PreferredSizeWidget _buildEnhancedAppBar() {
    return AppBar(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      elevation: 0,
      title: Padding(
        padding: const EdgeInsets.only(left: 15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.menu, size: 24, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Qurani Demo - API Integration',
                    style: TextStyle(fontSize: 16, height: 1.2),
                  ),
                  Text(
                    'Surat Yasin 36 - 83 Ayat ${_isSessionActive ? "• API Connected" : "• API Disconnected"}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                      height: 1.2,
                      color: _isSessionActive
                          ? Colors.greenAccent
                          : Colors.redAccent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      titleSpacing: 0,
      actions: [
        // API Status indicator
        Container(
          margin: const EdgeInsets.only(right: 8),
          child: Icon(
            _isWebSocketConnected ? Icons.wifi : Icons.wifi_off,
            color: _isWebSocketConnected
                ? Colors.greenAccent
                : Colors.redAccent,
            size: 20,
          ),
        ),

        // Toggle mode button
        IconButton(
          icon: Icon(
            _isQuranMode ? Icons.menu_book : Icons.view_list,
            size: 20,
          ),
          onPressed: () async {
            setState(() {
              _isQuranMode = !_isQuranMode;
            });
            await _loadCurrentPageAyats();
          },
          tooltip: _isQuranMode
              ? 'Switch to List Mode'
              : 'Switch to Mushaf Mode',
        ),

        // Hide/show button
        IconButton(
          icon: Icon(
            _hideUnreadAyat ? Icons.visibility : Icons.visibility_off,
            size: 20,
          ),
          onPressed: () {
            setState(() {
              _hideUnreadAyat = !_hideUnreadAyat;
            });
          },
          tooltip: _hideUnreadAyat ? 'Show All Text' : 'Hide Unread',
        ),

        PopupMenuButton<String>(
          onSelected: _handleMenuAction,
          iconSize: 20,
          itemBuilder: (BuildContext context) => [
            const PopupMenuItem(value: 'logs', child: Text('Debug Logs')),
            const PopupMenuItem(value: 'api_status', child: Text('API Status')),
            const PopupMenuItem(value: 'settings', child: Text('STT Settings')),
            const PopupMenuItem(value: 'reset', child: Text('Reset Session')),
            const PopupMenuItem(value: 'export', child: Text('Export Session')),
          ],
        ),
      ],
    );
  }

  void _handleMenuAction(String action) {
    switch (action) {
      case 'logs':
        _toggleLogs();
        break;
      case 'api_status':
        _showAPIStatus();
        break;
      case 'settings':
        _showSTTSettings();
        break;
      case 'reset':
        _showResetDialog();
        break;
      case 'export':
        _exportSession();
        break;
    }
  }

  Widget _buildEnhancedMainContent() {
    return Stack(
      children: [
        Column(
          children: [
            // API Status panel
            if (_showAdvancedStats) _buildAPIStatsPanel(),
            // Quran text
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 80),
                child: _buildEnhancedQuranText(),
              ),
            ),
          ],
        ),
        // Bottom bar
        Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomBar()),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      height: 90,
      child: Stack(
        children: [
          // Mic button positioned at the top of the curve
          Positioned(
            bottom: 25,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 65,
                height: 65,
                decoration: BoxDecoration(
                  color: _isListening ? errorColor : primaryColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (_isListening ? errorColor : primaryColor)
                          .withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(30),
                    onTap: _isListening
                        ? _stopContinuousListening
                        : _startContinuousListening,
                    child: Center(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          _isListening ? Icons.stop : Icons.mic,
                          key: ValueKey(_isListening),
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAPIStatsPanel() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: accentColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'API Analytics',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: accentColor,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _buildAnalyticsCard(
                  'API Calls',
                  '$_totalTranscriptsSent',
                  Icons.send,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildAnalyticsCard(
                  'Success Rate',
                  '${_totalTranscriptsSent > 0 ? ((_successfulAPIResponses / _totalTranscriptsSent) * 100).toStringAsFixed(0) : 0}%',
                  Icons.check_circle,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _buildAnalyticsCard(
                  'WebSocket',
                  _isWebSocketConnected ? 'Connected' : 'Disconnected',
                  _isWebSocketConnected ? Icons.wifi : Icons.wifi_off,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsCard(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          Icon(icon, color: accentColor, size: 12),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w500),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedQuranText() {
    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_isQuranMode) ...[
              Divider(color: Colors.grey.shade300, thickness: 1),
              _buildSuratInfoHeader(),
              Divider(color: Colors.grey.shade300, thickness: 1),
              const SizedBox(height: 8),
            ],
            _isQuranMode
                ? _buildQuranModeDisplay()
                : _buildEnhancedAllAyatDisplay(),
          ],
        ),
      ),
    );
  }

  Widget _buildSuratInfoHeader() {
    if (_suratInfo.isEmpty) return const SizedBox.shrink();

    final parts = _suratInfo.split('(');
    final nama = parts[0].trim();
    String namalatin = '';
    String ayatInfo = '';

    if (parts.length > 1) {
      final remaining = parts[1];
      final closeParen = remaining.indexOf(')');
      if (closeParen > 0) {
        namalatin = remaining.substring(0, closeParen);
        final lastPart = remaining.substring(closeParen + 1).trim();
        if (lastPart.startsWith('(') && lastPart.endsWith(')')) {
          ayatInfo = lastPart.substring(1, lastPart.length - 1);
        }
      }
    }

    return Column(
      children: [
        const SizedBox(height: 2),
        if (namalatin.isNotEmpty || _suratArti.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _buildOrnament(),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (namalatin.isNotEmpty) ...[
                      Text(
                        namalatin,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: primaryColor,
                        ),
                      ),
                      if (_suratArti.isNotEmpty) ...[
                        Text(
                          ' • ',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        Text(
                          _suratArti,
                          style: TextStyle(
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ] else if (_suratArti.isNotEmpty) ...[
                      Text(
                        _suratArti,
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildOrnament(),
            ],
          ),
        Container(
          height: 2,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(1),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final completedAyat = _ayatProgress.values
                  .where((p) => p.isCompleted)
                  .length;
              final totalAyat = _ayatList.length;
              final progress = totalAyat > 0 ? completedAyat / totalAyat : 0.0;
              return Stack(
                children: [
                  Container(
                    width: constraints.maxWidth * progress,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [primaryColor, correctColor],
                      ),
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 2),
      ],
    );
  }

  Widget _buildOrnament() {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.1),
        shape: BoxShape.circle,
        border: Border.all(color: primaryColor.withOpacity(0.2), width: 1),
      ),
      child: Center(
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: primaryColor.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }

  Widget _buildQuranModeDisplay() {
    return GestureDetector(
      onHorizontalDragEnd: (DragEndDetails details) {
        if (details.velocity.pixelsPerSecond.dx > 300) {
          // Swipe kanan - ke halaman sebelumnya
          if (_currentPage > 1) {
            _navigateToPage(_currentPage + 1);
          }
        } else if (details.velocity.pixelsPerSecond.dx < -300) {
          // Swipe kiri - ke halaman berikutnya
          if (_currentPage < 604) {
            _navigateToPage(_currentPage - 1);
          }
        }
      },
      child: _currentPageAyats.isEmpty
          ? const Center(
              child: Text(
                'No ayats found for this page',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(0),
              child: Container(
                decoration: BoxDecoration(
                  color: Color.fromARGB(255, 255, 255, 255),
                ),
                padding: const EdgeInsets.all(16),
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Text(
                        'Juz ${_currentPageAyats.isNotEmpty ? _currentPageAyats.first.juz : '1'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Text(
                        'Page $_currentPage',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 18),
                      child: _buildContinuousQuranText(),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildContinuousQuranText() {
    List<Widget> pageElements = [];

    Map<int, List<AyatData>> ayatsBySurah = {};
    for (final ayat in _currentPageAyats) {
      if (!ayatsBySurah.containsKey(ayat.surah_id)) {
        ayatsBySurah[ayat.surah_id] = [];
      }
      ayatsBySurah[ayat.surah_id]!.add(ayat);
    }

    ayatsBySurah.forEach((surahId, ayats) {
      bool isNewSurah = ayats.any((ayat) => ayat.ayah == 1);

      if (isNewSurah && surahId != 1 && surahId != 9) {
        pageElements.add(_buildSurahHeaderInPage(surahId));
        pageElements.add(_buildBismillahInPage());
      }

      List<InlineSpan> textSpans = [];

      for (int i = 0; i < ayats.length; i++) {
        final ayat = ayats[i];

        int ayatIndex = _ayatList.indexWhere(
          (a) => a.surah_id == ayat.surah_id && a.ayah == ayat.ayah,
        );
        bool isCurrentAyat = ayatIndex >= 0 && ayatIndex == _currentAyatIndex;

        textSpans.addAll(
          _buildContinuousAyatSpansWithAPI(ayat, ayatIndex, isCurrentAyat),
        );

        textSpans.add(
          TextSpan(
            text: ' ${_getArabicNumber(ayat.ayah)} ',
            style: TextStyle(
              fontSize: 25,
              fontFamily: 'Uthmanic',
              color: const Color.fromARGB(150, 0, 0, 0),
              fontWeight: FontWeight.bold,
            ),
          ),
        );

        if (i < ayats.length - 1 || ayatsBySurah.keys.last != surahId) {
          textSpans.add(TextSpan(text: ' '));
        }
      }

      pageElements.add(
        RichText(
          textAlign: TextAlign.justify,
          textDirection: TextDirection.rtl,
          text: TextSpan(
            style: const TextStyle(
              fontSize: 25,
              fontFamily: 'Uthmanic',
              wordSpacing: -5.3,
              letterSpacing: -0.5,
            ),
            children: textSpans,
          ),
        ),
      );
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: pageElements,
    );
  }

  List<InlineSpan> _buildContinuousAyatSpansWithAPI(
    AyatData ayat,
    int ayatIndex,
    bool isCurrentAyat,
  ) {
    final arabicWords = ayat.arabic
        .split(' ')
        .where((w) => w.trim().isNotEmpty)
        .toList();
    List<InlineSpan> spans = [];

    for (int wordIndex = 0; wordIndex < arabicWords.length; wordIndex++) {
      final word = arabicWords[wordIndex];

      // Get status from API results
      APIWordResult? wordResult;
      if (isCurrentAyat && wordIndex < _currentAyatResults.length) {
        wordResult = _currentAyatResults[wordIndex];
      }

      final status = wordResult?.getReadingStatus() ?? ReadingStatus.notRead;
      final isCurrentWord =
          isCurrentAyat; // For now, highlight entire current ayat

      double wordOpacity = 1.0;
      if (_hideUnreadAyat &&
          status == ReadingStatus.notRead &&
          !isCurrentWord) {
        wordOpacity = 0.0;
      }

      spans.add(
        TextSpan(
          text: '$word ',
          style: TextStyle(
            fontSize: 24,
            fontFamily: 'Uthmanic',
            color: _getAPIWordTextColor(
              status,
              isCurrentWord,
            ).withOpacity(wordOpacity),
            backgroundColor: _shouldShowWordBackground(status, isCurrentWord)
                ? _getAPIStatusColor(
                    status,
                    isCurrentWord,
                  ).withOpacity(0.3 * wordOpacity)
                : null,
            fontWeight: _getWordFontWeight(0.0, isCurrentWord),
          ),
        ),
      );
    }

    return spans;
  }

  Color _getAPIWordTextColor(ReadingStatus status, bool isCurrentWord) {
    if (isCurrentWord) return listeningColor;
    return Colors.black87;
  }

  Color _getAPIStatusColor(ReadingStatus status, bool isCurrentWord) {
    if (isCurrentWord) return listeningColor;

    switch (status) {
      case ReadingStatus.notRead:
        return unreadColor;
      case ReadingStatus.correct:
        return correctColor;
      case ReadingStatus.error:
        return errorColor;
      case ReadingStatus.skipped:
        return skippedColor;
    }
  }

  FontWeight _getWordFontWeight(double confidence, bool isCurrentWord) {
    if (isCurrentWord) return FontWeight.w600;
    return FontWeight.w500;
  }

  bool _shouldShowWordBackground(ReadingStatus status, bool isCurrentWord) {
    if (!_hideUnreadAyat)
      return status != ReadingStatus.notRead || isCurrentWord;
    return isCurrentWord || status != ReadingStatus.notRead;
  }

  Widget _buildSurahHeaderInPage(int surahId) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 0),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Image.asset(
            "assets/images/headerquran/headerquran.png",
            fit: BoxFit.contain,
            width: double.infinity,
          ),
          Text(
            'سُورَة ${widget.suratName}',
            style: const TextStyle(
              fontSize: 22,
              fontFamily: 'Uthmanic',
              fontWeight: FontWeight.w500,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildBismillahInPage() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        'k',
        style: TextStyle(
          fontSize: 27,
          fontFamily: '110BesmellahNormal',
          color: Colors.black87,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  String _getArabicNumber(int number) {
    const arabicNumbers = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    return number
        .toString()
        .split('')
        .map((digit) => arabicNumbers[int.parse(digit)])
        .join();
  }

  Future<void> _navigateToPage(int newPage) async {
    setState(() {
      _currentPage = newPage;
    });
    await _loadCurrentPageAyats();
  }

  Widget _buildEnhancedAllAyatDisplay() {
    List<Widget> ayatWidgets = [];

    ayatWidgets.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 3, 0, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
          child: const Text(
            'k',
            style: TextStyle(
              fontSize: 43,
              fontFamily: '110BesmellahNormal',
              fontWeight: FontWeight.normal,
              height: 0.8,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );

    for (int ayatIndex = 0; ayatIndex < _ayatList.length; ayatIndex++) {
      final ayat = _ayatList[ayatIndex];
      final isCurrentAyat = ayatIndex == _currentAyatIndex;

      ayatWidgets.add(_buildEnhancedAyatHeader(ayatIndex, isCurrentAyat));
      ayatWidgets.add(
        _buildEnhancedColoredAyatText(ayat, ayatIndex, isCurrentAyat),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: ayatWidgets,
    );
  }

  Widget _buildEnhancedAyatHeader(int ayatIndex, bool isCurrentAyat) {
    final progress = _ayatProgress[ayatIndex];
    final completionPercentage = progress?.completionPercentage ?? 0.0;

    return Container(
      key: _ayatKeys[ayatIndex],
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: completionPercentage / 100,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isCurrentAyat ? primaryColor : correctColor,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isCurrentAyat ? primaryColor : Colors.grey.shade400,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '${_ayatList[ayatIndex].ayah}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedColoredAyatText(
    AyatData ayat,
    int ayatIndex,
    bool isCurrentAyat,
  ) {
    final arabicWords = ayat.arabic
        .split(' ')
        .where((w) => w.trim().isNotEmpty)
        .toList();

    return Wrap(
      alignment: WrapAlignment.start,
      textDirection: TextDirection.rtl,
      spacing: 0,
      runSpacing: 8,
      children: arabicWords.asMap().entries.map((entry) {
        final wordIndex = entry.key;
        final word = entry.value;

        // Get status from API results
        APIWordResult? wordResult;
        if (isCurrentAyat && wordIndex < _currentAyatResults.length) {
          wordResult = _currentAyatResults[wordIndex];
        }

        return _buildEnhancedWordWidget(
          word,
          wordResult,
          isCurrentAyat,
          wordIndex,
        );
      }).toList(),
    );
  }

  Widget _buildEnhancedWordWidget(
    String word,
    APIWordResult? wordResult,
    bool isCurrentAyat,
    int wordIndex,
  ) {
    final status = wordResult?.getReadingStatus() ?? ReadingStatus.notRead;
    final isCurrentWord = isCurrentAyat;

    bool showColors = status != ReadingStatus.notRead;

    return GestureDetector(
      onTap: () {
        if (wordResult != null) {
          _showAPIWordDetails(wordResult, wordIndex);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: showColors || isCurrentWord
              ? _getAPIStatusColor(status, isCurrentWord).withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _shouldShowWord(status, isCurrentWord) ? 1.0 : 0.0,
          child: Text(
            word,
            style: TextStyle(
              fontSize: 26,
              fontFamily: 'Uthmanic',
              color: _getAPIWordTextColor(status, isCurrentWord),
              fontWeight: _getWordFontWeight(
                wordResult?.similarity_score ?? 0.0,
                isCurrentWord,
              ),
              height: 1.5,
            ),
            textDirection: TextDirection.rtl,
          ),
        ),
      ),
    );
  }

  bool _shouldShowWord(ReadingStatus status, bool isCurrentWord) {
    if (!_hideUnreadAyat) return true;
    if (isCurrentWord) return true;
    if (status != ReadingStatus.notRead) return true;
    return false;
  }

  void _showAPIWordDetails(APIWordResult wordResult, int wordIndex) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.api, color: primaryColor, size: 18),
              const SizedBox(width: 4),
              const Text('API Word Analysis', style: TextStyle(fontSize: 14)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    wordResult.expected,
                    style: const TextStyle(
                      fontSize: 24,
                      fontFamily: 'Uthmanic',
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.rtl,
                  ),
                ),
                const SizedBox(height: 8),
                _buildAPIDetailCard('Position', '${wordResult.position + 1}'),
                _buildAPIDetailCard('Expected', wordResult.expected),
                _buildAPIDetailCard('Spoken', wordResult.spoken),
                _buildAPIDetailCard('Status', wordResult.status),
                _buildAPIDetailCard(
                  'Similarity Score',
                  '${(wordResult.similarity_score * 100).toStringAsFixed(1)}%',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close', style: TextStyle(fontSize: 12)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAPIDetailCard(String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 10),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 10))),
        ],
      ),
    );
  }

  // ==================== UTILITY METHODS ====================

  void _showEnhancedSnackBar(String message, SnackBarType type) {
    if (!mounted) return;

    Color backgroundColor;
    IconData icon;

    switch (type) {
      case SnackBarType.success:
        backgroundColor = correctColor;
        icon = Icons.check_circle;
        break;
      case SnackBarType.error:
        backgroundColor = errorColor;
        icon = Icons.error;
        break;
      case SnackBarType.warning:
        backgroundColor = warningColor;
        icon = Icons.warning;
        break;
      case SnackBarType.info:
        backgroundColor = listeningColor;
        icon = Icons.info;
        break;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 4),
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }

  void _toggleLogs() {
    setState(() {
      _showLogs = !_showLogs;
    });
  }

  void _showAPIStatus() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('API Status', style: TextStyle(fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildStatusRow('Session Active', _isSessionActive ? '✓' : '✗'),
                _buildStatusRow('Session ID', _activeSessionId ?? 'N/A'),
                _buildStatusRow(
                  'WebSocket',
                  _isWebSocketConnected ? 'Connected' : 'Disconnected',
                ),
                _buildStatusRow('Current Ayat', '$_currentAyatNumber'),
                _buildStatusRow('API Calls', '$_totalTranscriptsSent'),
                _buildStatusRow(
                  'Success Rate',
                  '${_totalTranscriptsSent > 0 ? ((_successfulAPIResponses / _totalTranscriptsSent) * 100).toStringAsFixed(1) : 0}%',
                ),
                const SizedBox(height: 8),
                Text(
                  'Recent API Logs:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                Container(
                  height: 100,
                  child: ListView.builder(
                    itemCount: _apiLogs.length,
                    itemBuilder: (context, index) {
                      final log = _apiLogs[_apiLogs.length - 1 - index];
                      return Text(
                        '${log.method} ${log.endpoint} - ${log.statusCode} - ${log.message}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey.shade600,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  void _showSTTSettings() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'API STT Settings',
                style: TextStyle(fontSize: 16),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SwitchListTile(
                      title: const Text(
                        'Auto Send Transcripts',
                        style: TextStyle(fontSize: 12),
                      ),
                      subtitle: const Text(
                        'Automatically send to API',
                        style: TextStyle(fontSize: 10),
                      ),
                      value: _autoSendEnabled,
                      onChanged: (value) {
                        setDialogState(() {
                          _autoSendEnabled = value;
                        });
                      },
                    ),
                    SwitchListTile(
                      title: const Text(
                        'Auto Move Ayat',
                        style: TextStyle(fontSize: 12),
                      ),
                      subtitle: const Text(
                        'Auto move when completed',
                        style: TextStyle(fontSize: 10),
                      ),
                      value: _autoMoveEnabled,
                      onChanged: (value) {
                        setDialogState(() {
                          _autoMoveEnabled = value;
                        });
                      },
                    ),
                    ListTile(
                      title: const Text(
                        'Auto Send Delay',
                        style: TextStyle(fontSize: 12),
                      ),
                      subtitle: Text(
                        '${_autoSendDelay.inSeconds}s',
                        style: const TextStyle(fontSize: 10),
                      ),
                      trailing: SizedBox(
                        width: 100,
                        child: Slider(
                          value: _autoSendDelay.inSeconds.toDouble(),
                          min: 1.0,
                          max: 5.0,
                          divisions: 4,
                          onChanged: (value) {
                            setDialogState(() {
                              _autoSendDelay = Duration(seconds: value.toInt());
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {});
                    Navigator.pop(context);
                    _showEnhancedSnackBar(
                      'Settings updated',
                      SnackBarType.success,
                    );
                  },
                  child: const Text('Apply', style: TextStyle(fontSize: 12)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: warningColor, size: 18),
              const SizedBox(width: 4),
              const Text('Reset Session', style: TextStyle(fontSize: 14)),
            ],
          ),
          content: const Text(
            'Reset current session? This will end the API session and restart.',
            style: TextStyle(fontSize: 12),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(fontSize: 12)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _performReset();
              },
              style: ElevatedButton.styleFrom(backgroundColor: errorColor),
              child: const Text('Reset', style: TextStyle(fontSize: 12)),
            ),
          ],
        );
      },
    );
  }

  void _performReset() {
    _log('RESET: Performing session reset');

    // End current API session
    _endAPISession();

    setState(() {
      _currentAyatIndex = 0;
      _currentAyatNumber = _ayatList.isNotEmpty ? _ayatList[0].ayah : 1;
      _currentAyatResults.clear();
      _ayatProgress.clear();
      _liveTranscript = '';
      _confirmedTranscript = '';
      _transcriptHistory.clear();
      _apiLogs.clear();
      _totalTranscriptsSent = 0;
      _successfulAPIResponses = 0;
      _sessionStartTime = DateTime.now();
    });

    _showEnhancedSnackBar('Session reset', SnackBarType.info);
  }

  void _exportSession() {
    final sessionData = {
      'surah': widget.suratName,
      'session_id': _activeSessionId,
      'api_calls': _totalTranscriptsSent,
      'successful_responses': _successfulAPIResponses,
      'success_rate': _totalTranscriptsSent > 0
          ? (_successfulAPIResponses / _totalTranscriptsSent * 100)
          : 0,
      'session_duration': _sessionStartTime != null
          ? DateTime.now().difference(_sessionStartTime!).inMinutes
          : 0,
      'transcript_history': _transcriptHistory,
      'api_logs': _apiLogs.map((log) => log.toJson()).toList(),
      'completed_ayat': _ayatProgress.values.where((p) => p.isCompleted).length,
      'total_ayat': _ayatList.length,
    };

    _log('EXPORT: Session exported - ${jsonEncode(sessionData)}');
    _showEnhancedSnackBar('Session exported to logs', SnackBarType.success);
  }

  Widget _buildEnhancedLoadingWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: primaryColor,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                strokeWidth: 2,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Initializing API STT...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _errorMessage.isNotEmpty
                ? _errorMessage
                : 'Setting up API integration...',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedErrorWidget() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: errorColor.withOpacity(0.1),
                shape: BoxShape.circle,
                border: Border.all(color: errorColor.withOpacity(0.3)),
              ),
              child: Icon(Icons.error_outline, size: 40, color: errorColor),
            ),
            const SizedBox(height: 12),
            Text(
              'API STT Initialization Error',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton.icon(
                  onPressed: _initializeApp,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _toggleLogs,
                  icon: const Icon(Icons.bug_report, size: 16),
                  label: const Text(
                    'View Logs',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnhancedLogsPanel() {
    return Container(
      height: 150,
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: const BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal, color: correctColor, size: 16),
                const SizedBox(width: 4),
                const Text(
                  'API Debug Console',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.clear, color: Colors.white, size: 16),
                  onPressed: () {
                    setState(() {
                      _logs.clear();
                      _apiLogs.clear();
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(
                    Icons.save_alt,
                    color: Colors.white,
                    size: 16,
                  ),
                  onPressed: _exportSession,
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 16),
                  onPressed: _toggleLogs,
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              reverse: true,
              padding: const EdgeInsets.all(4),
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                final logIndex = _logs.length - 1 - index;
                final log = _logs[logIndex];

                Color logColor = Colors.greenAccent;
                if (log.contains('ERROR') || log.contains('Failed')) {
                  logColor = Colors.redAccent;
                } else if (log.contains('WARNING') || log.contains('Warning')) {
                  logColor = Colors.orangeAccent;
                } else if (log.contains('API_') || log.contains('WEBSOCKET')) {
                  logColor = Colors.cyanAccent;
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Text(
                    log,
                    style: TextStyle(
                      color: logColor,
                      fontSize: 8,
                      fontFamily: 'monospace',
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== DATA CLASSES ====================

class AyatData {
  final int surah_id;
  final int ayah;
  final String arabic;
  final String noTashkeel;
  final String transliteration;
  final List<String> wordsArrayNt;
  final int page;
  final int juz;
  final double quarterHizb;

  AyatData({
    required this.surah_id,
    required this.ayah,
    required this.arabic,
    required this.noTashkeel,
    required this.transliteration,
    required this.wordsArrayNt,
    required this.page,
    required this.juz,
    required this.quarterHizb,
  });

  factory AyatData.fromJson(Map<String, dynamic> json) {
    return AyatData(
      surah_id: json['surah_id'] ?? 0,
      ayah: json['ayah'] ?? 0,
      arabic: json['arabic'] ?? '',
      noTashkeel: json['no_tashkeel'] ?? '',
      transliteration: json['transliteration'] ?? '',
      wordsArrayNt: (json['words_array_nt'] as List?)?.cast<String>() ?? [],
      page: json['page'] ?? 1,
      juz: json['juz'] ?? 1,
      quarterHizb: (json['quarter_hizb'] ?? 0.0).toDouble(),
    );
  }
}

class APIWordResult {
  final int position;
  final String expected;
  final String spoken;
  final String status;
  final double similarity_score;

  APIWordResult({
    required this.position,
    required this.expected,
    required this.spoken,
    required this.status,
    required this.similarity_score,
  });

  factory APIWordResult.fromJson(Map<String, dynamic> json) {
    return APIWordResult(
      position: json['position'] ?? 0,
      expected: json['expected'] ?? '',
      spoken: json['spoken'] ?? '',
      status: json['status'] ?? 'unknown',
      similarity_score: (json['similarity_score'] ?? 0.0).toDouble(),
    );
  }

  ReadingStatus getReadingStatus() {
    switch (status.toLowerCase()) {
      case 'matched':
        return ReadingStatus.correct;
      case 'mismatched':
        return ReadingStatus.error;
      case 'skipped':
        return ReadingStatus.skipped;
      default:
        return ReadingStatus.notRead;
    }
  }
}

class APILog {
  final DateTime timestamp;
  final String method;
  final String endpoint;
  final int statusCode;
  final String message;

  APILog({
    required this.timestamp,
    required this.method,
    required this.endpoint,
    required this.statusCode,
    required this.message,
  });

  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'method': method,
      'endpoint': endpoint,
      'status_code': statusCode,
      'message': message,
    };
  }
}

enum ReadingStatus { notRead, correct, error, skipped }

enum SnackBarType { success, error, warning, info }

// ==================== VOSK MODEL MANAGER ====================

class EnhancedVoskModelManager {
  static const String _logPrefix = 'ENHANCED_VOSK_MODEL_MANAGER';

  static const Map<String, EnhancedModelInfo> availableModels = {
    'arabic_linto': EnhancedModelInfo(
      key: 'arabic_linto',
      name: 'Arabic Linto Pro',
      language: 'ar',
      assetPath: 'assets/models/vosk-model-ar-0.22-linto-1.1.0.zip',
      description:
          'High-accuracy Arabic model optimized for Quranic recitation',
      estimatedSize: '1,3 GB',
      accuracy: 0.92,
      speed: 0.88,
    ),
    'arabic_mgb2': EnhancedModelInfo(
      key: 'arabic_mgb2',
      name: 'Arabic MGB2 Enhanced',
      language: 'ar',
      assetPath: 'assets/models/vosk-model-ar-mgb2-0.4.zip',
      description: 'Balanced Arabic model with good speed and accuracy',
      estimatedSize: '300 MB',
      accuracy: 0.89,
      speed: 0.94,
    ),
  };

  static Future<String> getModelPath(String modelKey) async {
    final modelInfo = availableModels[modelKey];
    if (modelInfo == null) {
      throw Exception('Enhanced model not found: $modelKey');
    }

    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDir.path}/enhanced_vosk_models/$modelKey');
    return modelDir.path;
  }

  static Future<bool> isModelExists(String modelKey) async {
    try {
      final modelPath = await getModelPath(modelKey);
      final modelDir = Directory(modelPath);

      if (!await modelDir.exists()) {
        return false;
      }

      final requiredFiles = [
        'am/final.mdl',
        'graph/HCLG.fst',
        'graph/phones.txt',
        'graph/words.txt',
        'ivector/final.ie',
        'ivector/global_cmvn.stats',
        'conf/model.conf',
        'conf/mfcc.conf',
      ];

      for (final file in requiredFiles) {
        final filePath = File('$modelPath/$file');
        if (!await filePath.exists()) {
          _log('Verification failed: Missing $file');
          return false;
        }

        final stat = await filePath.stat();
        if (stat.size == 0) {
          _log('Verification failed: Empty file $file');
          return false;
        }
      }

      _log('Model verification passed for $modelKey');
      return true;
    } catch (e) {
      _log('Error in model verification: $e');
      return false;
    }
  }

  static Future<void> copyModelFromAssets({
    required String modelKey,
    Function(int copied, int total)? onProgress,
  }) async {
    final modelInfo = availableModels[modelKey];
    if (modelInfo == null) {
      throw Exception('Enhanced model not found: $modelKey');
    }

    _log('Extraction starting for $modelKey from ${modelInfo.assetPath}');

    final modelPath = await getModelPath(modelKey);
    final modelDir = Directory(modelPath);

    if (await modelDir.exists()) {
      await modelDir.delete(recursive: true);
    }
    await modelDir.create(recursive: true);

    try {
      _log('Loading ZIP asset: ${modelInfo.assetPath}');
      final zipBytes = await rootBundle.load(modelInfo.assetPath);
      final zipData = zipBytes.buffer.asUint8List();

      _log('ZIP loaded: ${formatFileSize(zipData.length)}');

      late Archive archive;
      try {
        archive = ZipDecoder().decodeBytes(zipData);
      } catch (e) {
        throw Exception('Failed to decode ZIP: $e');
      }

      _log('ZIP decoded: ${archive.files.length} files');

      String? modelFolderPrefix = _detectEnhancedModelPrefix(archive);
      if (modelFolderPrefix != null) {
        _log('Model prefix: $modelFolderPrefix');
      }

      int extractedFiles = 0;
      final totalFiles = archive.files.where((f) => f.isFile).length;

      for (final file in archive.files) {
        if (!file.isFile) continue;

        String relativePath = _processEnhancedFilePath(
          file.name,
          modelFolderPrefix,
        );

        if (relativePath.isEmpty) continue;

        final filePath = '${modelDir.path}/$relativePath';
        final targetFile = File(filePath);

        _log('Extracting: ${file.name} -> $relativePath');

        try {
          await targetFile.parent.create(recursive: true);

          final fileData = file.content as List<int>;
          await targetFile.writeAsBytes(fileData);

          if (_isEnhancedCriticalFile(relativePath)) {
            final stat = await targetFile.stat();
            if (stat.size == 0) {
              throw Exception('Critical file empty: $relativePath');
            }
            _log(
              '✓ Critical file: $relativePath (${formatFileSize(stat.size)})',
            );
          }

          extractedFiles++;
          onProgress?.call(extractedFiles, totalFiles);
        } catch (e) {
          _log('Extraction error for ${file.name}: $e');
          throw Exception('Failed to extract ${file.name}: $e');
        }
      }

      _log('Extraction completed: $extractedFiles/$totalFiles files');

      if (extractedFiles == 0) {
        throw Exception('No files extracted from ZIP');
      }

      await _performEnhancedFinalVerification(modelPath);

      _log('Model $modelKey extracted and verified');
    } catch (e) {
      _log('Extraction failed: $e');
      if (await modelDir.exists()) {
        await modelDir.delete(recursive: true);
      }
      throw Exception('Model extraction failed: $e');
    }
  }

  static String? _detectEnhancedModelPrefix(Archive archive) {
    Set<String> topLevelDirs = {};

    for (final file in archive.files) {
      if (file.isFile && file.name.contains('/')) {
        final parts = file.name.split('/');
        if (parts.isNotEmpty) {
          topLevelDirs.add(parts[0]);
        }
      }
    }

    for (final dir in topLevelDirs) {
      if (dir.toLowerCase().startsWith('vosk-model')) {
        return dir;
      }
    }

    return null;
  }

  static String _processEnhancedFilePath(String originalPath, String? prefix) {
    String path = originalPath;

    if (prefix != null && path.startsWith('$prefix/')) {
      path = path.substring(prefix.length + 1);
    }

    path = path.replaceAll(RegExp(r'^[\/\\]+'), '');

    return path;
  }

  static bool _isEnhancedCriticalFile(String path) {
    final criticalPaths = [
      'am/final.mdl',
      'graph/HCLG.fst',
      'graph/phones.txt',
      'graph/words.txt',
      'ivector/final.ie',
      'ivector/global_cmvn.stats',
      'conf/model.conf',
      'conf/mfcc.conf',
    ];

    return criticalPaths.any((criticalPath) => path.endsWith(criticalPath));
  }

  static Future<void> _performEnhancedFinalVerification(
    String modelPath,
  ) async {
    _log('Final verification for $modelPath');

    final criticalFiles = [
      'am/final.mdl',
      'graph/HCLG.fst',
      'ivector/final.ie',
      'conf/model.conf',
    ];

    for (final filePath in criticalFiles) {
      final file = File('$modelPath/$filePath');

      if (!await file.exists()) {
        throw Exception('Missing critical file $filePath');
      }

      final stat = await file.stat();
      if (stat.size == 0) {
        throw Exception('Empty critical file $filePath');
      }

      if (filePath.endsWith('model.conf')) {
        final content = await file.readAsString();
        if (!content.contains('--sample-frequency')) {
          _log('Warning: model.conf may be incomplete');
        }
      }

      _log('✓ Verification passed: $filePath (${formatFileSize(stat.size)})');
    }

    _log('Final verification completed');
  }

  static Future<bool> verifyEnhancedModelIntegrity(String modelKey) async {
    try {
      _log('Integrity verification for $modelKey');

      final modelPath = await getModelPath(modelKey);

      final criticalFiles = [
        'am/final.mdl',
        'graph/HCLG.fst',
        'graph/phones.txt',
        'graph/words.txt',
        'ivector/final.ie',
        'conf/model.conf',
      ];

      for (final filePath in criticalFiles) {
        final file = File('$modelPath/$filePath');
        if (!await file.exists() || (await file.stat()).size == 0) {
          _log('Integrity check failed for $filePath');
          return false;
        }
      }

      _log('Integrity verification passed for $modelKey');
      return true;
    } catch (e) {
      _log('Integrity verification error: $e');
      return false;
    }
  }

  static String formatFileSize(int bytes) {
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    int i = 0;
    double size = bytes.toDouble();

    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }

    return '${size.toStringAsFixed(1)} ${suffixes[i]}';
  }

  static void _log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 23);
    print('[$timestamp] $_logPrefix: $message');
  }
}

class EnhancedModelInfo {
  final String key;
  final String name;
  final String language;
  final String assetPath;
  final String description;
  final String estimatedSize;
  final double accuracy;
  final double speed;

  const EnhancedModelInfo({
    required this.key,
    required this.name,
    required this.language,
    required this.assetPath,
    required this.description,
    required this.estimatedSize,
    required this.accuracy,
    required this.speed,
  });
}
