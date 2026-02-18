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

  bool _ready = false;
  bool _busy = false;

  static const int sampleRate = 16000;
  static const int channels = 1;

  VoiceState state = VoiceState.idle;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    await FirebaseAuth.instance.signInAnonymously();
    await Permission.microphone.request();

    await _recorder.openRecorder();

    await _tts.setLanguage("en-US");
    await _tts.setSpeechRate(0.5);

    _ready = true;
    print("✅ Enterprise recorder ready");
  }

  @override
  void dispose() {
    _recordingSubscription?.cancel();
    _recordingController?.close();
    _recorder.closeRecorder();
    _tts.stop();
    super.dispose();
  }

  Color get backgroundColor {
    switch (state) {
      case VoiceState.idle:
        return Colors.green;
      case VoiceState.recording:
        return Colors.red;
      case VoiceState.processing:
        return Colors.blue;
    }
  }

  Future<void> startRecording() async {
    if (!_ready || _busy) return;

    _pcmBuffer.clear();

    _recordingController = StreamController<Uint8List>();

    _recordingSubscription =
        _recordingController!.stream.listen((data) {
      _pcmBuffer.addAll(data);
    });

    print("🎙 START RAW PCM RECORDING");

    await _recorder.startRecorder(
      codec: Codec.pcm16,
      sampleRate: sampleRate,
      numChannels: channels,
      toStream: _recordingController!.sink,
    );

    setState(() => state = VoiceState.recording);
  }

  Future<void> stopRecording() async {
    if (!_recorder.isRecording || _busy) return;

    _busy = true;

    print("🛑 STOP RECORDING");

    await _recorder.stopRecorder();

    await _recordingSubscription?.cancel();
    await _recordingController?.close();

    setState(() => state = VoiceState.processing);

    if (_pcmBuffer.length < 4000) {
      print("⚠ Audio too small");
      _reset();
      return;
    }

    final wavBytes = _buildWav(Uint8List.fromList(_pcmBuffer));

    print("📁 FINAL WAV SIZE: ${wavBytes.length}");

    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'africa-south1',
      ).httpsCallable('processSpeech');

      final response = await callable.call({
        "audio": base64Encode(wavBytes),
        "targetLang": "en",
      });

      print("🔥 Cloud response: ${response.data}");

      final text = response.data['translatedText'];

      if (text != null && text is String && text.isNotEmpty) {
        await _tts.speak(text);
      }
    } catch (e) {
      print("🔥 Cloud Error: $e");
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
    setState(() => state = VoiceState.idle);
    _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: GestureDetector(
            onLongPressStart: (_) => startRecording(),
            onLongPressEnd: (_) => stopRecording(),
            child: Container(
              width: 160,
              height: 160,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text(
                  "HOLD",
                  style: TextStyle(fontSize: 24),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
