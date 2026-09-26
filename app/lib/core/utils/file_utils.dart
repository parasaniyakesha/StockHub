import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';

import '../network/api_client.dart';

class FileUtils {
  FileUtils._();

  /// Lets the user choose where to save a downloaded export. Returns the saved
  /// path (desktop) or null if cancelled.
  static Future<String?> saveDownload(DownloadedFile file) async {
    final dot = file.fileName.lastIndexOf('.');
    final name = dot > 0 ? file.fileName.substring(0, dot) : file.fileName;
    final ext = dot > 0 ? file.fileName.substring(dot + 1) : '';
    final mime = switch (ext) {
      'csv' => MimeType.csv,
      'xlsx' => MimeType.microsoftExcel,
      'pdf' => MimeType.pdf,
      _ => MimeType.other,
    };
    return FileSaver.instance.saveAs(name: name, bytes: file.bytes, fileExtension: ext, mimeType: mime);
  }

  /// Picks a CSV file and returns its rows as maps keyed by the header row.
  /// Returns null if the user cancelled.
  static Future<List<Map<String, String>>?> pickCsvRows() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['csv'], dialogTitle: 'Select CSV file');
    if (files.isEmpty) return null;
    final Uint8List bytes = await files.first.readAsBytes();
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('﻿')) text = text.substring(1);
    final rows = csv.decode(text);
    if (rows.isEmpty) return const [];
    final headers = rows.first.map((h) => h.toString().trim()).toList();
    return rows
        .skip(1)
        .where((r) => r.any((c) => c.toString().trim().isNotEmpty))
        .map((r) => {for (var i = 0; i < headers.length; i++) headers[i]: i < r.length ? r[i].toString().trim() : ''})
        .toList();
  }
}

/// Idempotency keys for create requests (sales, returns, transfers, requests).
/// A retried submission with the same key is recognised by the server.
String newClientRequestId() {
  final r = Random.secure();
  return List.generate(24, (_) => r.nextInt(16).toRadixString(16)).join();
}
