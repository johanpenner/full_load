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
  const FilePreviewScreen({
    super.key,
    required this.url,
    this.fileName,
    this.contentType,
  });

  @override
  State<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends State<FilePreviewScreen> {
  String? _localPath;
  Uint8List? _bytes; // for images/text printing convenience
  bool _loading = true;
  String? _error;
  double? _progress; // 0..1

  // PDF nav
  int _pages = 0;
  int _currentPage = 0;
  PDFViewController? _pdfController;

  // Type detection
  late final _Type _type;

  @override
  void initState() {
    super.initState();
    _type = _detectType(widget.contentType, widget.fileName, widget.url);
    _prepare();
  }

  // ---------- Type detection ----------
  _Type _detectType(String? contentType, String? name, String url) {
    final ct = (contentType ?? '').toLowerCase();
    final ext = p.extension(name ?? Uri.parse(url).path).toLowerCase();

    bool isPdf = ct.contains('pdf') || ext == '.pdf';
    bool isImage = ct.startsWith('image/') ||
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
    bool isText = ct.startsWith('text/') ||
        ['.txt', '.csv', '.json', '.md', '.log'].contains(ext);

    if (isPdf) return _Type.pdf;
    if (isImage) return _Type.image;
    if (isText) return _Type.text;

    // office/video/audio/archives -> external
    return _Type.external;
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
    // Web or unsupported target → open externally with hint
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

      final req = http.Request('GET', Uri.parse(widget.url));
      final resp = await req.send();
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }

      final total = resp.contentLength ?? 0;
      final sink = file.openWrite();
      int received = 0;

      await resp.stream.listen(
        (chunk) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            setState(() => _progress = received / total);
          } else {
            setState(() => _progress = null);
          }
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

  Future<void> _share() async {
    if (_localPath != null) {
      await Share.shareXFiles([XFile(_localPath!)], text: _title);
    } else {
      await Share.share(widget.url);
    }
  }

  Future<void> _printFile() async {
    // printing for PDFs directly; images/text convert to a one-page PDF
    try {
      if (_type == _Type.pdf && _localPath != null) {
        final data = await File(_localPath!).readAsBytes();
        await Printing.layoutPdf(onLayout: (_) async => data);
        return;
      }

      if (_type == _Type.image && _bytes != null) {
        final doc = pw.Document();
        final img = pw.MemoryImage(_bytes!);
        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (_) => pw.Center(
              child: pw.Image(img, fit: pw.BoxFit.contain),
            ),
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
            build: (_) => [
              pw.Text(txt, style: pw.TextStyle(font: mono, fontSize: 9)),
            ],
          ),
        );
        await Printing.layoutPdf(onLayout: (_) => doc.save());
        return;
      }

      // Fallback for other types: try open in browser
      await _openInBrowser();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Print failed: $e')),
      );
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
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar:
          _type == _Type.pdf && _localPath != null && _pages > 0
              ? _pdfFooter()
              : null,
    );
  }

  Widget _buildBody() {
    if (kIsWeb)
      return _fallback('Preview not supported on Web. Use the browser button.');
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
    if (_localPath == null && _bytes == null)
      return _fallback('Failed to load file.');

    switch (_type) {
      case _Type.pdf:
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
            FilledButton.icon(
              onPressed: _openInBrowser,
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Open in Browser'),
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
        border: Border(top: BorderSide(color: Colors.black12)),
      ),
      child: Row(
        children: [
          Text('Page ${_currentPage + 1} / $_pages',
              style: const TextStyle(fontWeight: FontWeight.w600)),
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

  String _decodeExt(String? name) =>
      (name == null) ? '' : p.extension(name).toLowerCase();

  String _decodeText(Uint8List data) {
    // try utf8; fallback latin1
    try {
      return utf8.decode(data);
    } catch (_) {
      return latin1.decode(data, allowInvalid: true);
    }
  }
}

enum _Type { pdf, image, text, external }
