import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audio_session/audio_session.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const LimpopoVoiceApp());
}

enum VoiceState { idle, recording, processing }

class LimpopoVoiceApp extends StatelessWidget {
  const LimpopoVoiceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: LimpopoHome(),
    );
  }
}

class LimpopoHome extends StatefulWidget {
  const LimpopoHome({super.key});

  @override
  State<LimpopoHome> createState() => _LimpopoHomeState();
}

class _LimpopoHomeState extends State<LimpopoHome> {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterTts _tts = FlutterTts();

  final List<int> _pcmBuffer = [];
  StreamController<Uint8List>? _recordingController;
  StreamSubscription? _recordingSubscription;

  static const int sampleRate = 16000;
  static const int channels = 1;

  bool _ready = false;
  bool _busy = false;
  int _credits = 0;

  VoiceState state = VoiceState.idle;

  bool get _hasCredits => _credits > 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await FirebaseAuth.instance.signInAnonymously();
    await Permission.microphone.request();

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
      avAudioSessionMode: AVAudioSessionMode.spokenAudio,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.voiceCommunication,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
    ));

    await _recorder.openRecorder();
    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5);

    await _initializeUserCredits();

    setState(() {
      _ready = true;
    });
  }

  Future<void> _initializeUserCredits() async {
    final callable =
        FirebaseFunctions.instanceFor(region: 'africa-south1')
            .httpsCallable('initializeUser');

    final response = await callable.call();
    final data = Map<String, dynamic>.from(response.data);

    setState(() {
      _credits = data['credits'] ?? 0;
    });
  }

  @override
  void dispose() {
    _recordingSubscription?.cancel();
    _recordingController?.close();
    _recorder.closeRecorder();
    _tts.stop();
    super.dispose();
  }

  Future<void> startRecording() async {
    if (!_ready || _busy || !_hasCredits) return;

    _pcmBuffer.clear();

    _recordingController = StreamController<Uint8List>();
    _recordingSubscription =
        _recordingController!.stream.listen((data) {
      _pcmBuffer.addAll(data);
    });

    await _recorder.startRecorder(
      codec: Codec.pcm16,
      sampleRate: sampleRate,
      numChannels: channels,
      toStream: _recordingController!.sink,
    );

    setState(() => state = VoiceState.recording);

    Future.delayed(const Duration(seconds: 10), () async {
      if (state == VoiceState.recording) {
        await stopRecording();
      }
    });
  }

  Future<void> stopRecording() async {
    if (!_recorder.isRecording || _busy) return;

    _busy = true;
    await _recorder.stopRecorder();

    await _recordingSubscription?.cancel();
    await _recordingController?.close();

    setState(() => state = VoiceState.processing);

    if (_pcmBuffer.length < 4000) {
      _reset();
      return;
    }

    if (!_hasCredits) {
      _reset();
      return;
    }

    final wavBytes = _buildWav(Uint8List.fromList(_pcmBuffer));

    try {
      final callable =
          FirebaseFunctions.instanceFor(region: 'africa-south1')
              .httpsCallable('processSpeech');

      final response = await callable.call({
        "audio": base64Encode(wavBytes),
        "targetLang": "en",
      });

      final data = Map<String, dynamic>.from(response.data);

      setState(() {
        _credits = data['remainingCredits'] ?? _credits;
      });

      final text = data['translatedText'];

      if (text != null && text.isNotEmpty) {
        await _tts.speak(text);
      }

    } catch (e) {
      setState(() {
        _credits = 0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No credits remaining.")),
      );
    }

    _reset();
  }

  Uint8List _buildWav(Uint8List pcmData) {
    final int byteRate = sampleRate * channels * 2;
    final int blockAlign = channels * 2;
    final int dataLength = pcmData.length;
    final int fileLength = 44 + dataLength;

    final buffer = BytesBuilder();

    buffer.add(ascii.encode('RIFF'));
    buffer.add(_intToBytes(fileLength - 8, 4));
    buffer.add(ascii.encode('WAVE'));
    buffer.add(ascii.encode('fmt '));
    buffer.add(_intToBytes(16, 4));
    buffer.add(_intToBytes(1, 2));
    buffer.add(_intToBytes(channels, 2));
    buffer.add(_intToBytes(sampleRate, 4));
    buffer.add(_intToBytes(byteRate, 4));
    buffer.add(_intToBytes(blockAlign, 2));
    buffer.add(_intToBytes(16, 2));
    buffer.add(ascii.encode('data'));
    buffer.add(_intToBytes(dataLength, 4));
    buffer.add(pcmData);

    return buffer.toBytes();
  }

  Uint8List _intToBytes(int value, int byteCount) {
    final bytes = ByteData(byteCount);
    if (byteCount == 2) {
      bytes.setUint16(0, value, Endian.little);
    } else {
      bytes.setUint32(0, value, Endian.little);
    }
    return bytes.buffer.asUint8List();
  }

  void _reset() {
    setState(() {
      state = VoiceState.idle;
      _busy = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool locked = !_hasCredits;

    return Scaffold(
      backgroundColor: locked ? Colors.grey : Colors.green,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Credits: $_credits",
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            if (locked)
              const Text(
                "No credits remaining",
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            const SizedBox(height: 40),
            GestureDetector(
              onLongPressStart:
                  locked ? null : (_) => startRecording(),
              onLongPressEnd:
                  locked ? null : (_) => stopRecording(),
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  color: locked ? Colors.grey[400] : Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    locked ? "LOCKED" : "HOLD",
                    style: const TextStyle(fontSize: 24),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
