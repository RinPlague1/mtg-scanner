import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Tiny helper for stores persisted as one JSON file in the app's documents
/// folder. Writes go to a temp file first, then rename, so a crash mid-write
/// can't corrupt the data.
class JsonFile {
  final String name;
  File? _file;
  Future<void> _pending = Future.value();

  JsonFile(this.name);

  bool get isOpen => _file != null;

  Future<Object?> open() async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File('${dir.path}/$name');
    _file = f;
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  /// Serialised writes; a no-op until [open] has been called (e.g. in tests).
  Future<void> write(Object? data) {
    final f = _file;
    if (f == null) return Future.value();
    final text = jsonEncode(data);
    _pending = _pending.then((_) async {
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(f.path);
    }).catchError((_) {});
    return _pending;
  }
}
