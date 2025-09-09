// lib/preview/universal_preview_screen.dart
// Versatile file previewer: downloads/caches bytes, detects type (MIME/extension), renders accordingly.
// Updates: Added download progress, MIME detection (from headers/extension), role gating example,
// temp file cleanup, better error UI, retry button.

import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart'; // Add to pubspec: mime: ^1.0.5
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../auth/current_user_role.dart'; // For role check if gating
import '../auth/roles.dart'; // For RoleGate/AppPerm (e.g., 'viewDocs')

class UniversalPreviewScreen extends StatefulWidget {
  final String urlOrPath;
  final String? fileName;
  const UniversalPreviewScreen(
      {super.key, required this.urlOrPath, this.fileName});

  @override
  State<UniversalPreviewScreen> createState() => _UniversalPreviewScreenState();
}

class _UniversalPreviewScreenState extends State<UniversalPreviewScreen> {
  Uint8List? _bytes;
  String? _localPath;
  bool _loading = true;
  double _progress = 0.0; // For download progress
  bool _isImage = false;
  bool _isPdf = false;
  String? _error;
  AppRole _role = AppRole.viewer; // For gating

  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadFile();
  }

  Future<void> _loadRole() async {
    _role = await currentUserRole();
    setState(() {});
  }

  Future<void> _loadFile() async {
    setState(() {
      _loading = true;
      _progress = 0.0;
      _error = null;
    });
    try {
      if (widget.urlOrPath.startsWith('http')) {
        // Streamed download for progress
        final request = http.Request('GET', Uri.parse(widget.urlOrPath));
        final response = await request.send();
        if (response.statusCode != 200) {
          throw 'HTTP ${response.statusCode}';
        }
        final totalBytes = response.contentLength;
        final bytes = <int>[];
        response.stream.listen(
          (chunk) {
            bytes.addAll(chunk);
            setState(() =>
                _progress = totalBytes != null ? bytes.length / totalBytes : 0);
          },
          onDone: () => _bytes = Uint8List.fromList(bytes),
          onError: (e) => throw e,
          cancelOnError: true,
        );
      } else {
        final file = File(widget.urlOrPath);
        if (await file.exists()) {
          _bytes = await file.readAsBytes();
          _localPath = widget.urlOrPath;
        } else {
          throw 'File not found';
        }
      }

      if (_bytes == null) throw 'No bytes loaded';

      // MIME detection (headers or extension)
      String mime = '';
      if (widget.urlOrPath.startsWith('http')) {
        mime = response.headers['content-type'] ?? '';
      }
      mime = mime.isNotEmpty
          ? mime
          : lookupMimeType(widget.fileName ?? widget.urlOrPath) ?? '';
      _isImage = mime.startsWith('image/');
      _isPdf = mime == 'application/pdf';

      if (!_isImage && !_isPdf && !kIsWeb) {
        final tempDir = await getTemporaryDirectory();
        final ext = mime.split('/').last;
        _localPath =
            '${tempDir.path}/${widget.fileName ?? 'temp'}${ext.isEmpty ? '' : '.$ext'}';
        await File(_localPath!).writeAsBytes(_bytes!);
      }
    } catch (e) {
      setState(() => _error = 'Load failed: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _share() async {
    if (_localPath != null) {
      await Share.shareXFiles([XFile(_localPath!)]);
    } else if (_bytes != null) {
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/${widget.fileName ?? 'share_file'}';
      await File(tempPath).writeAsBytes(_bytes!);
      await Share.shareXFiles([XFile(tempPath)]);
      // Cleanup temp
      await File(tempPath).delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return RoleGate(
      role: _role,
      perm: AppPerm
          .viewDocs, // Example: Gate for 'viewDocs' perm (add to AppPerm if needed)
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.fileName ?? 'Preview'),
          actions: [
            if (_bytes != null) ...[
              IconButton(
                  icon: const Icon(Icons.print),
                  onPressed: () async => await Printing.printPdf(
                      bytes: _bytes!, format: PdfPageFormat.standard)),
              IconButton(icon: const Icon(Icons.share), onPressed: _share),
            ],
          ],
        ),
        body: _loading
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    if (_progress > 0)
                      Text('${(_progress * 100).toStringAsFixed(0)}%'),
                  ],
                ),
              )
            : _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        ElevatedButton(
                            onPressed: _loadFile, child: const Text('Retry')),
                      ],
                    ),
                  )
                : _bytes == null
                    ? const Center(child: Text('No file loaded'))
                    : _isImage
                        ? InteractiveViewer(child: Image.memory(_bytes!))
                        : _isPdf
                            ? Center(
                                child: PdfPreview(
                                    build: (format) async => _bytes!,
                                    canChangePageFormat: false,
                                    canChangeOrientation: false,
                                    allowPrinting: false))
                            : Center(
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                          'Preview not supported in-app'),
                                      if (!kIsWeb)
                                        ElevatedButton(
                                            onPressed: () =>
                                                OpenFilex.open(_localPath!),
                                            child:
                                                const Text('Open Externally')),
                                      ElevatedButton(
                                          onPressed: () => launchUrl(
                                              Uri.parse(widget.urlOrPath)),
                                          child: const Text('Open Link')),
                                    ]),
                              ),
      ),
    );
  }
}
