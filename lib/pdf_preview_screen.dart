// lib/pdf_preview_screen.dart
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'widgets/main_menu_button.dart';

class PDFPreviewScreen extends StatefulWidget {
  final String pdfUrl;
  const PDFPreviewScreen({super.key, required this.pdfUrl});

  @override
  State<PDFPreviewScreen> createState() => _PDFPreviewScreenState();
}

class _PDFPreviewScreenState extends State<PDFPreviewScreen> {
  String? _localPath;
  bool _loading = true;
  String? _error;

  // progress
  double? _progress; // 0..1
  int _pages = 0;
  int _currentPage = 0;
  PDFViewController? _pdfController;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    // For web, or if not mobile/desktop, open externally
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.macOS &&
            defaultTargetPlatform != TargetPlatform.windows &&
            defaultTargetPlatform != TargetPlatform.linux)) {
      setState(() {
        _loading = false;
        _error = 'PDF inline preview is not supported on this platform.';
      });
      return;
    }

    await _downloadWithCache();
  }

  String _cacheNameFor(String url) {
    final digest = md5.convert(utf8.encode(url)).toString();
    return 'pdfcache_$digest.pdf';
  }

  Future<void> _downloadWithCache() async {
    try {
      final tmpDir = await getTemporaryDirectory();
      final filePath = '${tmpDir.path}/${_cacheNameFor(widget.pdfUrl)}';
      final cached = File(filePath);

      if (await cached.exists()) {
        setState(() {
          _localPath = filePath;
          _loading = false;
        });
        return;
      }

      // Streamed download for progress
      final req = http.Request('GET', Uri.parse(widget.pdfUrl));
      final resp = await req.send();
      if (resp.statusCode != 200) {
        throw Exception('HTTP ${resp.statusCode}');
      }

      final total = resp.contentLength ?? 0;
      final sink = cached.openWrite();
      int received = 0;

      resp.stream.listen(
        (chunk) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) {
            setState(() => _progress = received / total);
          } else {
            setState(() => _progress = null); // indeterminate
          }
        },
        onDone: () async {
          await sink.flush();
          await sink.close();
          setState(() {
            _localPath = filePath;
            _loading = false;
          });
        },
        onError: (e) async {
          await sink.close();
          if (await cached.exists()) {
            try {
              await cached.delete();
            } catch (_) {}
          }
          throw e;
        },
        cancelOnError: true,
      );
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Error downloading PDF: $e';
      });
    }
  }

  Future<void> _refresh() async {
    // Force re-download: delete cached file first
    final tmpDir = await getTemporaryDirectory();
    final filePath = '${tmpDir.path}/${_cacheNameFor(widget.pdfUrl)}';
    final cached = File(filePath);
    if (await cached.exists()) {
      try {
        await cached.delete();
      } catch (_) {}
    }
    setState(() {
      _localPath = null;
      _loading = true;
      _error = null;
      _progress = 0;
      _pages = 0;
      _currentPage = 0;
      _pdfController = null;
    });
    await _downloadWithCache();
  }

  Future<void> _share() async {
    if (_localPath == null) return;
    try {
      await Share.shareXFiles([XFile(_localPath!)], text: 'PDF document');
    } catch (_) {
      // Fallback share link
      await Share.share(widget.pdfUrl);
    }
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(widget.pdfUrl);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _jumpToPage() async {
    if (_pdfController == null || _pages <= 1) return;
    final ctrl = TextEditingController(text: '${_currentPage + 1}');
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Go to page'),
            content: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                helperText: '1 – $_pages',
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Go')),
            ],
          ),
        ) ??
        false;
    if (!ok) return;

    final page = int.tryParse(ctrl.text.trim());
    if (page == null) return;
    final target = page.clamp(1, _pages) - 1;
    await _pdfController!.setPage(target);
  }

  @override
  Widget build(BuildContext context) {
    final title = 'PDF Preview';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
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
            onPressed: _localPath == null ? null : _share,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _refresh,
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildFooter(),
    );
  }

  Widget _buildBody() {
    if (kIsWeb) {
      return _fallbackBody(
          'Preview not supported on Web. Tap the browser button in the top-right.');
    }
    if (_error != null) {
      return _fallbackBody(_error!);
    }
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            if (_progress != null)
              Text('${(_progress! * 100).toStringAsFixed(0)}%'),
          ],
        ),
      );
    }
    if (_localPath == null) {
      return _fallbackBody('Failed to load PDF.');
    }
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
  }

  Widget _fallbackBody(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
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

  Widget _buildFooter() {
    if (_localPath == null || _pages <= 0) return const SizedBox.shrink();
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
}
