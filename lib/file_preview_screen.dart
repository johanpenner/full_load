// lib/file_preview_screen.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'widgets/main_menu_button.dart';

class FilePreviewScreen extends StatefulWidget {
  final String url;
  final String? fileName; // e.g., "BOL_1234.pdf"
  final String? contentType; // e.g., "application/pdf"
  final Map<String, String>? headers; // optional: auth headers

  const FilePreviewScreen({
    super.key,
    required this.url,
    this.fileName,
    this.contentType,
    this.headers,
  });

  @override
  State<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends State<FilePreviewScreen> {
  String? _localPath;
  Uint8List? _bytes;
  bool _loading = true;
  String? _error;
  double? _progress; // 0..1

  // PDF nav
  int _pages = 0;
  int _currentPage = 0;
  PDFViewController? _pdfController;

  // Type detection (mutable so we can refine after HTTP headers)
  _Type _type = _Type.external;
  String? _resolvedContentType; // from HTTP headers if available

  @override
  void initState() {
    super.initState();
    _type = _detectType(widget.contentType, widget.fileName, widget.url);
    _prepare();
  }

  // ---------- Type detection ----------
  _Type _detectType(String? contentType, String? name, String url,
      {String? headerCt}) {
    final ct = (headerCt ?? contentType ?? '').toLowerCase();
    final ext = p.extension(name ?? Uri.parse(url).path).toLowerCase();

    final isPdf = ct.contains('pdf') || ext == '.pdf';
    final isImage = ct.startsWith('image/') ||
        [
          '.jpg',
          '.jpeg',
          '.png',
          '.webp',
          '.gif',
          '.bmp',
          '.heic',
          '.tif',
          '.tiff'
        ].contains(ext);
    final isText = ct.startsWith('text/') ||
        ['.txt', '.csv', '.json', '.md', '.log'].contains(ext);

    if (isPdf) return _Type.pdf;
    if (isImage) return _Type.image;
    if (isText) return _Type.text;
    return _Type.external; // office/video/audio/archives -> external
  }

  String get _title =>
      widget.fileName ??
      p.basename(Uri.parse(widget.url).path).split('?').first;

  String _cacheNameFor(String url) {
    final digest = md5.convert(utf8.encode(url)).toString();
    final ext = p.extension(_title).isEmpty ? '' : p.extension(_title);
    return 'cache_$digest$ext';
  }

  // ---------- Download + cache ----------
  Future<void> _prepare() async {
    final supportedPlatform = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux;

    if (kIsWeb || !supportedPlatform) {
      setState(() {
        _loading = false;
        _error = 'Inline preview not supported on this platform.';
      });
      return;
    }

    try {
      final tmp = await getTemporaryDirectory();
      final cachePath = p.join(tmp.path, _cacheNameFor(widget.url));
      final file = File(cachePath);

      if (await file.exists()) {
        _localPath = cachePath;
        _bytes = await file.readAsBytes();
        setState(() => _loading = false);
        return;
      }

      final client = http.Client();
      try {
        final req = http.Request('GET', Uri.parse(widget.url));
        if (widget.headers != null) req.headers.addAll(widget.headers!);
        final resp = await client.send(req);
        if (resp.statusCode != 200) {
          throw Exception('HTTP ${resp.statusCode}');
        }

        // Refine type from Content-Type header if provided
        _resolvedContentType = resp.headers['content-type'];
        final refined = _detectType(
            widget.contentType, widget.fileName, widget.url,
            headerCt: _resolvedContentType);
        if (refined != _type) setState(() => _type = refined);

        final total = resp.contentLength ?? 0;
        final sink = file.openWrite();
        int received = 0;

        resp.stream.listen(
          (chunk) {
            sink.add(chunk);
            received += chunk.length;
            setState(() => _progress = total > 0 ? received / total : null);
          },
          onDone: () async {
            await sink.flush();
            await sink.close();
            _localPath = file.path;
            _bytes = await file.readAsBytes();
            setState(() => _loading = false);
          },
          onError: (e) async {
            await sink.close();
            if (await file.exists()) {
              try {
                await file.delete();
              } catch (_) {}
            }
            throw e;
          },
          cancelOnError: true,
        );
      } finally {
        client.close();
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Download error: $e';
      });
    }
  }

  Future<void> _refresh() async {
    final tmp = await getTemporaryDirectory();
    final cachePath = p.join(tmp.path, _cacheNameFor(widget.url));
    final file = File(cachePath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }

    setState(() {
      _localPath = null;
      _bytes = null;
      _loading = true;
      _error = null;
      _progress = 0;
      _pages = 0;
      _currentPage = 0;
      _pdfController = null;
    });
    await _prepare();
  }

  // ---------- Actions ----------
  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(widget.url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openLocalExternally() async {
    if (_localPath == null) return;
    final uri = Uri.file(_localPath!);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _share() async {
    if (_localPath != null) {
      final x = XFile(_localPath!, name: _title.isEmpty ? null : _title);
      await Share.shareXFiles([x], text: _title);
    } else {
      await Share.share(widget.url);
    }
  }

  Future<void> _printFile() async {
    try {
      if (_type == _Type.pdf && (_localPath != null || _bytes != null)) {
        final data = _bytes ?? await File(_localPath!).readAsBytes();
        await Printing.layoutPdf(onLayout: (_) async => data);
        return;
      }
      if (_type == _Type.image && _bytes != null) {
        final doc = pw.Document();
        final img = pw.MemoryImage(_bytes!);
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (_) =>
                pw.Center(child: pw.Image(img, fit: pw.BoxFit.contain)),
          ),
        );
        await Printing.layoutPdf(onLayout: (_) => doc.save());
        return;
      }
      if (_type == _Type.text && _bytes != null) {
        final txt = _decodeText(_bytes!);
        final doc = pw.Document();
        final mono = pw.Font.courier();
        doc.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            build: (_) =>
                [pw.Text(txt, style: pw.TextStyle(font: mono, fontSize: 9))],
          ),
        );
        await Printing.layoutPdf(onLayout: (_) => doc.save());
        return;
      }
      await _openInBrowser();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
    }
  }

  Future<void> _saveToDownloads() async {
    try {
      if (_bytes == null && _localPath == null) return;
      final bytes = _bytes ?? await File(_localPath!).readAsBytes();
      // Heuristic Downloads path for desktop + app-docs for mobile
      String outPath;
      if (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        final home = Platform.environment['USERPROFILE'] ??
            Platform.environment['HOME'] ??
            Directory.current.path;
        final downloads = Directory(p.join(home, 'Downloads'));
        if (!downloads.existsSync()) downloads.createSync(recursive: true);
        outPath =
            p.join(downloads.path, _title.isEmpty ? 'downloaded_file' : _title);
      } else {
        final dir = await getApplicationDocumentsDirectory();
        outPath = p.join(dir.path, _title.isEmpty ? 'downloaded_file' : _title);
      }
      final f = File(outPath);
      await f.parent.create(recursive: true);
      await f.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Saved to: $outPath')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  // ---------- Rendering ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title.isEmpty ? 'File Preview' : _title),
        actions: [
          const MainMenuButton(),
          IconButton(
            tooltip: 'Open in browser',
            icon: const Icon(Icons.open_in_new),
            onPressed: _openInBrowser,
          ),
          IconButton(
            tooltip: 'Open externally',
            icon: const Icon(Icons.open_in_browser_outlined),
            onPressed: _openLocalExternally,
          ),
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined),
            onPressed: _share,
          ),
          IconButton(
            tooltip: 'Print',
            icon: const Icon(Icons.print_outlined),
            onPressed: (_type == _Type.external && _localPath == null)
                ? null
                : _printFile,
          ),
          IconButton(
            tooltip: 'Download',
            icon: const Icon(Icons.download_outlined),
            onPressed: (_bytes == null && _localPath == null)
                ? null
                : _saveToDownloads,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: (_type == _Type.pdf &&
              (_localPath != null || _bytes != null) &&
              _pages > 0)
          ? _pdfFooter()
          : null,
    );
  }

  Widget _buildBody() {
    if (kIsWeb) {
      return _fallback('Preview not supported on Web. Use the browser button.');
    }
    if (_error != null) return _fallback(_error!);
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            if (_progress != null) ...[
              const SizedBox(height: 8),
              Text('${(_progress! * 100).toStringAsFixed(0)}%'),
            ],
          ],
        ),
      );
    }
    if (_localPath == null && _bytes == null) {
      return _fallback('Failed to load file.');
    }

    switch (_type) {
      case _Type.pdf:
        // On mobile, flutter_pdfview; on desktop, PdfPreview from printing
        final isMobile = defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS;
        if (isMobile) {
          if (_localPath == null) return _fallback('PDF not available.');
          return PDFView(
            filePath: _localPath!,
            enableSwipe: true,
            swipeHorizontal: false,
            autoSpacing: true,
            pageSnap: true,
            nightMode: false,
            onRender: (pages) => setState(() => _pages = pages ?? 0),
            onViewCreated: (c) => _pdfController = c,
            onPageChanged: (page, total) {
              if (page != null && total != null) {
                setState(() {
                  _currentPage = page;
                  _pages = total;
                });
              }
            },
            onError: (e) => setState(() => _error = 'PDF error: $e'),
          );
        } else {
          final data = _bytes ?? File(_localPath!).readAsBytesSync();
          return PdfPreview(
            build: (_) async => data,
            allowPrinting: false,
            allowSharing: false,
            canChangeOrientation: true,
            canChangePageFormat: true,
            onError: (context, error) {
              setState(() => _error = 'PDF preview error: $error');
              return Text('Error: $error');
            },
          );
        }

      case _Type.image:
        return InteractiveViewer(
          minScale: 0.5,
          maxScale: 4,
          child: _bytes != null
              ? Image.memory(_bytes!, fit: BoxFit.contain)
              : Image.file(File(_localPath!), fit: BoxFit.contain),
        );

      case _Type.text:
        final body = _bytes != null
            ? _decodeText(_bytes!)
            : File(_localPath!).readAsStringSync();
        return Padding(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            body,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        );

      case _Type.external:
      default:
        return _fallback(
          'Inline preview not supported for this file.\nUse the browser button to open it in an external app.',
        );
    }
  }

  Widget _fallback(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(msg, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _openInBrowser,
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('Open in Browser'),
                ),
                if (_localPath != null)
                  OutlinedButton.icon(
                    onPressed: _openLocalExternally,
                    icon: const Icon(Icons.launch),
                    label: const Text('Open App'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pdfFooter() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: const Border(top: BorderSide(color: Colors.black12)),
      ),
      child: Row(
        children: [
          Text(
            'Page ${_currentPage + 1} / $_pages',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Previous page',
            icon: const Icon(Icons.chevron_left),
            onPressed: _pdfController == null || _currentPage <= 0
                ? null
                : () => _pdfController!.setPage(_currentPage - 1),
          ),
          IconButton(
            tooltip: 'Jump to page',
            icon: const Icon(Icons.keyboard),
            onPressed: _pdfController == null ? null : _jumpToPage,
          ),
          IconButton(
            tooltip: 'Next page',
            icon: const Icon(Icons.chevron_right),
            onPressed: _pdfController == null || _currentPage >= _pages - 1
                ? null
                : () => _pdfController!.setPage(_currentPage + 1),
          ),
        ],
      ),
    );
  }

  Future<void> _jumpToPage() async {
    if (_pages <= 1) return;
    final ctrl = TextEditingController(text: '${_currentPage + 1}');
    final go = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Go to page'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Page #',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(ctrl.text.trim());
              if (n != null) Navigator.pop(ctx, n);
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
    if (go == null) return;
    final idx = go.clamp(1, _pages) - 1;
    if (_pdfController != null) _pdfController!.setPage(idx);
  }

  String _decodeText(Uint8List data) {
    try {
      return utf8.decode(data);
    } catch (_) {
      return latin1.decode(data, allowInvalid: true);
    }
  }
}

enum _Type { pdf, image, text, external }
