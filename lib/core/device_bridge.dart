import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class PickedLogoImage {
  const PickedLogoImage({
    required this.bytes,
    required this.mimeType,
    required this.fileName,
  });

  final Uint8List bytes;
  final String mimeType;
  final String fileName;
}

class SavedDownloadResult {
  const SavedDownloadResult({
    required this.savedPath,
    this.uri = '',
  });

  final String savedPath;
  final String uri;
}

/// Native device bridge (`MethodChannel('jewellery_erp/device')`) for:
/// 1. Picking a showroom/company logo directly from **Device Photos / Gallery** or **Files**.
/// 2. Downloading any Invoice, Payment Receipt, Voucher, Statement, or Report `.pdf`
///    straight into `Downloads/JewelleryERP/` and opening/sharing it on the phone.
class DeviceBridge {
  DeviceBridge._();

  static const MethodChannel _ch = MethodChannel('jewellery_erp/device');

  /// Opens the native Android Device Photos / Gallery (`mode = 'photos'`) or
  /// system file browser (`mode = 'files'`) and returns normalized PNG/JPEG/WebP bytes.
  static Future<PickedLogoImage?> pickLogoImage({
    String mode = 'photos',
    int maxBytes = 500 * 1024,
  }) async {
    if (kIsWeb) {
      throw PlatformException(
        code: 'WEB_UNSUPPORTED',
        message: 'Use file path or URL on web browser.',
      );
    }
    final res = await _ch.invokeMethod<dynamic>('pickImage', {
      'mode': mode,
      'maxBytes': maxBytes,
    });
    if (res == null) return null;
    if (res is Map) {
      final rawBytes = res['bytes'];
      final bytes = rawBytes is Uint8List
          ? rawBytes
          : (rawBytes is List<int> ? Uint8List.fromList(rawBytes) : null);
      if (bytes == null || bytes.isEmpty) return null;
      final mime = '${res['mimeType'] ?? 'image/jpeg'}';
      final name = '${res['fileName'] ?? 'showroom-logo.jpg'}';
      return PickedLogoImage(bytes: bytes, mimeType: mime, fileName: name);
    }
    return null;
  }

  /// Writes [bytes] into `Downloads/JewelleryERP/[fileName]` on Android (via
  /// `MediaStore.Downloads`) and on Windows/macOS/Linux desktop `Downloads`.
  static Future<SavedDownloadResult> saveToDownloads({
    required Uint8List bytes,
    required String fileName,
    String mimeType = 'application/pdf',
  }) async {
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

    if (!kIsWeb && Platform.isAndroid) {
      try {
        final res = await _ch.invokeMethod<dynamic>('saveFileToDownloads', {
          'bytes': bytes,
          'fileName': safeName,
          'mimeType': mimeType,
        });
        if (res is Map) {
          return SavedDownloadResult(
            savedPath: '${res['savedPath'] ?? 'Downloads/JewelleryERP/$safeName'}',
            uri: '${res['uri'] ?? ''}',
          );
        }
      } on MissingPluginException {
        // Fallback below if running in widget test / headless VM.
      }
    }

    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      final home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
      if (home.isNotEmpty) {
        final sep = Platform.pathSeparator;
        final dir = Directory('$home${sep}Downloads${sep}JewelleryERP');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final outFile = File('${dir.path}$sep$safeName');
        await outFile.writeAsBytes(bytes, flush: true);
        return SavedDownloadResult(savedPath: outFile.path, uri: outFile.uri.toString());
      }
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${docsDir.path}${Platform.pathSeparator}JewelleryERP');
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }
    final outFile = File('${outDir.path}${Platform.pathSeparator}$safeName');
    await outFile.writeAsBytes(bytes, flush: true);
    return SavedDownloadResult(savedPath: outFile.path, uri: outFile.uri.toString());
  }

  /// Opens a saved document URI in the device's default PDF / document viewer.
  static Future<void> openSavedUri(
    String uri, {
    String mimeType = 'application/pdf',
  }) async {
    if (uri.isEmpty || kIsWeb) return;
    if (Platform.isAndroid) {
      await _ch.invokeMethod<dynamic>('openUri', {
        'uri': uri,
        'mimeType': mimeType,
      });
    } else if (Platform.isWindows) {
      final path = Uri.tryParse(uri)?.toFilePath() ?? uri;
      await Process.run('explorer.exe', [path]);
    } else if (Platform.isMacOS) {
      final path = Uri.tryParse(uri)?.toFilePath() ?? uri;
      await Process.run('open', [path]);
    }
  }

  /// Opens the native Android Share sheet (`WhatsApp`, `Gmail`, `Drive`, `Files`) for [uri].
  static Future<void> shareSavedUri(
    String uri, {
    String mimeType = 'application/pdf',
    String title = 'Share ERP Document',
  }) async {
    if (uri.isEmpty || kIsWeb) return;
    if (Platform.isAndroid) {
      await _ch.invokeMethod<dynamic>('shareUri', {
        'uri': uri,
        'mimeType': mimeType,
        'title': title,
      });
    }
  }

  /// Opens Android's native Print / Save-as-PDF spooler for server-rendered HTML.
  static Future<void> printHtmlDocument({
    required String html,
    required String jobName,
  }) async {
    if (html.isEmpty || kIsWeb) return;
    if (Platform.isAndroid) {
      await _ch.invokeMethod<dynamic>('printHtml', {
        'html': html,
        'jobName': jobName,
      });
    }
  }
}
