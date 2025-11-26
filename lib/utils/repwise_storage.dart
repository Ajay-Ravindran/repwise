import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class RepwiseStorage {
  const RepwiseStorage();

  static const String _stateFileName = 'repwise_state.json';

  Future<File> _stateFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_stateFileName');
  }

  Future<Map<String, dynamic>?> readState() async {
    try {
      final file = await _stateFile();
      if (!await file.exists()) {
        return null;
      }
      final contents = await file.readAsString();
      if (contents.trim().isEmpty) {
        return null;
      }
      return jsonDecode(contents) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeState(Map<String, dynamic> state) async {
    try {
      final file = await _stateFile();
      await file.create(recursive: true);
      await file.writeAsString(jsonEncode(state), flush: true);
    } catch (_) {
      // Swallow persistence errors to avoid crashing the UI.
    }
  }

  Future<File?> createExportFile(Map<String, dynamic> state) async {
    try {
      final directory = await getTemporaryDirectory();
      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${directory.path}/gym-log-export-$timestamp.json');
      await file.writeAsString(jsonEncode(state), flush: true);
      return file;
    } catch (_) {
      return null;
    }
  }
}
