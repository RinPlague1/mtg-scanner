import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'data/name_index.dart';
import 'data/scryfall.dart';
import 'ocr/card_text_parser.dart';
import 'vision/bmp.dart';
import 'vision/frame.dart';
import 'vision/geometry.dart';
import 'vision/scan_pipeline.dart';

enum ScanHint { none, glare, tooDark, noEdges, lookingUp, offline }

class ScanHit {
  final CardPrint card;
  final bool exactPrinting; // matched via set code + collector number
  ScanHit(this.card, this.exactPrinting);
}

class _Read {
  final String name;
  final SetInfo? set;
  _Read(this.name, this.set);
}

/// Owns the camera stream, runs analysis off the UI thread, OCRs the crops,
/// votes across frames, and resolves the card on Scryfall.
class ScanController extends ChangeNotifier {
  final ScryfallClient scryfall;

  /// False = don't download the card-name list; every scan's text is sent to
  /// Scryfall's fuzzy search instead (needs a connection).
  bool useNameList;
  ScanController(this.scryfall, {this.useNameList = true});

  /// Switch name matching without restarting the camera.
  void setUseNameList(bool v) {
    if (v == useNameList) return;
    useNameList = v;
    _reads.clear();
    if (v) {
      unawaited(_loadIndex());
    } else {
      _index = null;
      if (hint == ScanHint.offline) hint = ScanHint.none;
    }
    notifyListeners();
  }

  CameraController? camera;
  TextRecognizer _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  bool _recognizerRecreated = false;
  NameIndex? _index;

  // live state for the UI
  Quad? quadNorm;
  int sidesFound = 0;
  ScanHint hint = ScanHint.none;
  String status = 'Starting camera…';
  String? lastRawName;
  ScanHit? hit;
  bool torchOn = false;
  bool autoAdd = false;
  int lastFrameMs = 0;

  /// Debug info for "Show what the scanner reads".
  List<String> lastNameLines = const [];
  List<String> lastSetLines = const [];
  SetInfo? lastSetInfo;
  String? lastMatch;

  /// Last text-recognition error (e.g. the model is still downloading), shown
  /// in the status line instead of failing silently.
  String? ocrProblem;
  int framesAnalysed = 0;

  bool _busy = false;
  bool _paused = false;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  final List<_Read?> _reads = [];
  int _glareFrames = 0;
  int _darkFrames = 0;
  String? _suppressName; // in auto-add mode, ignore the card just added

  bool get paused => _paused;

  // Static so the isolate closures capture nothing but their argument.
  static Future<FrameAnalysis> _analyse(YuvFrame f) => Isolate.run(() => analyseFrame(f));
  static Future<NameIndex> _buildIndex(List<String> names) => Isolate.run(() => NameIndex(names));

  Future<void> init() async {
    if (useNameList) unawaited(_loadIndex());
    final cams = await availableCameras();
    final back = cams.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cams.first,
    );
    final c = CameraController(
      back,
      ResolutionPreset.veryHigh, // 1080p: the collector line is tiny text
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );
    camera = c;
    await c.initialize();
    if (_disposed) return;
    await c.setFlashMode(FlashMode.off);
    try {
      await c.setFocusMode(FocusMode.auto);
    } catch (_) {}
    await c.startImageStream(_onFrame);
    status = 'Line the card up with the frame';
    notifyListeners();
  }

  Future<void> _loadIndex() async {
    try {
      final names = await scryfall.cardNames();
      final index = await _buildIndex(names);
      if (useNameList) _index = index; // ignore if switched to online meanwhile
    } catch (_) {
      hint = ScanHint.offline; // falls back to Scryfall fuzzy search per scan
      notifyListeners();
    }
  }

  Future<void> toggleTorch() async {
    final c = camera;
    if (c == null) return;
    torchOn = !torchOn;
    await c.setFlashMode(torchOn ? FlashMode.torch : FlashMode.off);
    notifyListeners();
  }

  void setAutoAdd(bool v) {
    autoAdd = v;
    notifyListeners();
  }

  /// Resume after a hit has been handled (added or dismissed).
  void resume({bool suppressCurrent = false}) {
    final current = hit?.card.name;
    _suppressName = suppressCurrent && current != null ? _voteKey(current) : null;
    hit = null;
    _reads.clear();
    _paused = false;
    status = 'Line the card up with the frame';
    notifyListeners();
  }

  void _onFrame(CameraImage image) {
    if (_busy || _paused) return;
    final now = DateTime.now();
    if (now.difference(_lastFrame).inMilliseconds < 200) return;
    _lastFrame = now;
    _busy = true;
    final rotation = camera?.description.sensorOrientation ?? 90;
    final frame = _toYuv(image, rotation); // copies planes synchronously
    _process(frame).whenComplete(() => _busy = false);
  }

  static YuvFrame _toYuv(CameraImage img, int rotation) {
    if (img.planes.length == 1) {
      return YuvFrame.nv21(Uint8List.fromList(img.planes[0].bytes), img.width, img.height, rotation);
    }
    final y = img.planes[0], u = img.planes[1], v = img.planes[2];
    return YuvFrame(
      sensorWidth: img.width,
      sensorHeight: img.height,
      rotation: rotation,
      y: Uint8List.fromList(y.bytes),
      yRowStride: y.bytesPerRow,
      u: Uint8List.fromList(u.bytes),
      v: Uint8List.fromList(v.bytes),
      uvRowStride: u.bytesPerRow,
      uvPixelStride: u.bytesPerPixel ?? 1,
    );
  }

  Future<void> _process(YuvFrame frame) async {
    final FrameAnalysis a;
    try {
      a = await _analyse(frame);
    } catch (e) {
      debugPrint('analysis failed: $e');
      return;
    }
    if (_paused) return;
    quadNorm = a.quadNorm;
    sidesFound = a.sidesFound;
    lastFrameMs = a.elapsedMs;

    _glareFrames = a.nameGlare > 0.02 ? _glareFrames + 1 : 0;
    _darkFrames = a.cardBrightness < 35 ? _darkFrames + 1 : 0;

    final nameLines = await _ocr(a.name, 'name');
    final setLines = await _ocr(a.setLine, 'set');
    final candidates = CardTextParser.nameCandidates(nameLines);
    final setInfo = CardTextParser.setInfo(setLines);
    lastRawName = candidates.isEmpty ? null : candidates.first;
    lastNameLines = nameLines;
    lastSetLines = setLines;
    lastSetInfo = setInfo;
    framesAnalysed++;

    _Read? read;
    for (final cand in candidates) {
      final idx = _index;
      if (idx != null) {
        final m = idx.match(cand);
        if (m != null) {
          read = _Read(m.name, setInfo);
          break;
        }
      } else {
        // No name list (online mode, or it couldn't download): vote on the
        // cleaned-up OCR text and let Scryfall's fuzzy search resolve it.
        final clean = _cleanOcrName(cand);
        if (clean.length >= 3) {
          read = _Read(clean, setInfo);
          break;
        }
      }
    }
    lastMatch = read?.name;
    if (read != null && _voteKey(read.name) == _suppressName) read = null;
    if (read == null && candidates.isEmpty) _suppressName = null; // card removed

    _reads.add(read);
    if (_reads.length > 4) _reads.removeAt(0);

    hint = _glareFrames >= 2
        ? ScanHint.glare
        : _darkFrames >= 3 && !torchOn
            ? ScanHint.tooDark
            : (read == null && a.sidesFound < 2)
                ? ScanHint.noEdges
                : (_index == null && useNameList ? ScanHint.offline : ScanHint.none);

    final winner = _vote();
    if (winner != null) {
      _paused = true;
      status = 'Found ${winner.name} — looking up…';
      hint = ScanHint.lookingUp;
      notifyListeners();
      await _resolve(winner);
    } else {
      status = read != null
          ? 'Reading: ${read.name}'
          : ocrProblem != null
              ? 'Text reader not working. Full error: ⚙ → Show what the scanner reads'
              : (candidates.isNotEmpty && _index != null)
                  ? 'Read "${candidates.first}" but it doesn\'t match a card name'
                  : (a.sidesFound >= 3 ? 'Card found, reading the name…' : 'Line the card up with the frame');
      notifyListeners();
    }
  }

  /// How crops are handed to ML Kit. Some phones' plugin builds fail on raw
  /// NV21 bytes (InputImageConverterError) or on file paths (a native
  /// NullPointerException), so on an error we move to the next way and retry.
  static const ocrInputModes = ['bytes', 'bitmap', 'file'];
  int _ocrMode = 0;
  String get ocrInputMode => ocrInputModes[_ocrMode];
  String? _cacheDir;

  Future<InputImage> _inputFor(OcrCrop crop, String tag) async {
    final gray = Uint8List.sublistView(crop.nv21, 0, crop.width * crop.height);
    switch (ocrInputMode) {
      case 'bitmap':
        final rgba = Uint8List(crop.width * crop.height * 4);
        for (var i = 0, j = 0; i < gray.length; i++, j += 4) {
          final v = gray[i];
          rgba[j] = v;
          rgba[j + 1] = v;
          rgba[j + 2] = v;
          rgba[j + 3] = 255;
        }
        return InputImage.fromBitmap(bitmap: rgba, width: crop.width, height: crop.height);
      case 'file':
        _cacheDir ??= (await getTemporaryDirectory()).path;
        final path = '$_cacheDir/ocr_$tag.bmp';
        await File(path).writeAsBytes(grayToBmp(gray, crop.width, crop.height), flush: true);
        return InputImage.fromFilePath(path);
      default:
        return InputImage.fromBytes(
          bytes: crop.nv21,
          metadata: InputImageMetadata(
            size: Size(crop.width.toDouble(), crop.height.toDouble()),
            rotation: InputImageRotation.rotation0deg,
            format: InputImageFormat.nv21,
            bytesPerRow: crop.width,
          ),
        );
    }
  }

  /// Errors seen per input mode, for the troubleshooting panel.
  final Map<String, String> ocrErrors = {};

  Future<List<String>> _ocr(OcrCrop crop, String tag) async {
    try {
      final r = await _recognizer.processImage(await _inputFor(crop, tag));
      ocrProblem = null;
      return [
        for (final b in r.blocks)
          for (final l in b.lines) l.text,
      ];
    } catch (e) {
      debugPrint('OCR failed ($ocrInputMode): $e');
      final msg = e.toString();
      ocrErrors[ocrInputMode] = msg.length > 300 ? '${msg.substring(0, 300)}…' : msg;
      if (msg.toLowerCase().contains('download')) {
        ocrProblem = 'the text model is still downloading. Stay online for a minute and try again.';
        return const [];
      }
      if (_ocrMode < ocrInputModes.length - 1) {
        _ocrMode++;
        return _ocr(crop, tag); // retry this crop the next way
      }
      if (!_recognizerRecreated) {
        // Every way failed: start a fresh recognizer once and go round again.
        _recognizerRecreated = true;
        unawaited(_recognizer.close());
        _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
        _ocrMode = 0;
        return _ocr(crop, tag);
      }
      ocrProblem = msg;
      return const [];
    }
  }



  /// Raw OCR text varies a little between frames ("Sol Ring" / "Sol Rinq"
  /// stays distinct, but case, spacing and stray punctuation shouldn't).
  static String _voteKey(String name) =>
      name.toLowerCase().replaceAll(RegExp(r"[^a-z0-9' ,\-/]"), '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _cleanOcrName(String raw) => raw
      .replaceAll(RegExp(r"[^A-Za-z0-9À-ÿ' ,\-/]"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Two agreeing reads out of the last four frames.
  _Read? _vote() {
    final counts = <String, int>{};
    final display = <String, String>{};
    for (final r in _reads) {
      if (r == null) continue;
      final k = _voteKey(r.name);
      counts[k] = (counts[k] ?? 0) + 1;
      display.putIfAbsent(k, () => r.name);
    }
    String? best;
    var bestN = 0;
    counts.forEach((k, n) {
      if (n > bestN) {
        best = k;
        bestN = n;
      }
    });
    if (best == null || bestN < 2) return null;
    // Most common complete set/number among the agreeing reads.
    final sets = <SetInfo, int>{};
    SetInfo? partial;
    for (final r in _reads) {
      if (r == null || _voteKey(r.name) != best || r.set == null) continue;
      if (r.set!.complete) {
        sets[r.set!] = (sets[r.set!] ?? 0) + 1;
      } else {
        partial ??= r.set;
      }
    }
    SetInfo? chosen;
    var setN = 0;
    sets.forEach((k, n) {
      if (n > setN) {
        chosen = k;
        setN = n;
      }
    });
    return _Read(display[best]!, chosen ?? partial);
  }

  Future<void> _resolve(_Read r) async {
    try {
      CardPrint? card;
      var exact = false;
      final s = r.set;
      if (s != null && s.complete) {
        final c = await scryfall.bySetAndNumber(s.setCode!, s.collectorNumber!);
        if (c != null && c.hasName(r.name)) {
          card = c;
          exact = true;
        }
      }
      if (card == null && _index != null) {
        card = await scryfall.named(r.name, set: s?.setCode);
        card ??= await scryfall.named(r.name);
      }
      if (card == null && _index == null && s?.setCode != null) {
        card = await scryfall.named(r.name, set: s!.setCode, fuzzy: true);
      }
      card ??= await scryfall.named(r.name, fuzzy: true);
      if (card == null) {
        status = 'Couldn\'t find "${r.name}" — try again';
        _paused = false;
        _reads.clear();
        hint = ScanHint.none;
        notifyListeners();
        return;
      }
      hit = ScanHit(card, exact);
      status = card.name;
      hint = ScanHint.none;
      notifyListeners();
    } catch (e) {
      status = 'Lookup failed (offline?) — tap to retry';
      hint = ScanHint.offline;
      _paused = false;
      _reads.clear();
      notifyListeners();
    }
  }

  /// Swap the current hit for a different printing chosen by the user.
  void choosePrinting(CardPrint p) {
    hit = ScanHit(p, true);
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _paused = true;
    final c = camera;
    camera = null;
    c?.dispose();
    _recognizer.close();
    super.dispose();
  }
}
