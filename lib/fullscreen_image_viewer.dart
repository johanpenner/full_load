import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:photo_view/photo_view.dart';
// not required, but handy if you extend later
import 'package:share_plus/share_plus.dart';

class FullscreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final String? heroTag;
  final Map<String, String>? headers; // e.g., auth headers
  final double minScale;
  final double maxScale;
  final bool enableRotation;

  const FullscreenImageViewer({
    super.key,
    required this.imageUrl,
    this.heroTag,
    this.headers,
    this.minScale = PhotoViewComputedScale.contained,
    this.maxScale = 4.0,
    this.enableRotation = true,
  });

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  bool _busy = false;

  ImageProvider get _provider =>
      NetworkImage(widget.imageUrl, headers: widget.headers);

  Future<Uint8List?> _fetchBytes() async {
    try {
      final resp =
          await http.get(Uri.parse(widget.imageUrl), headers: widget.headers);
      if (resp.statusCode == 200) return resp.bodyBytes;
    } catch (_) {}
    return null;
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _fetchBytes();
      if (bytes == null) throw 'Download failed';
      final tmpDir = await getTemporaryDirectory();
      final fileName =
          p.basename(Uri.parse(widget.imageUrl).path).split('?').first;
      final out =
          File(p.join(tmpDir.path, fileName.isEmpty ? 'image.jpg' : fileName));
      await out.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([XFile(out.path)], text: fileName);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Share failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _fetchBytes();
      if (bytes == null) throw 'Download failed';
      String outPath;
      if (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS) {
        final home = Platform.environment['USERPROFILE'] ??
            Platform.environment['HOME'] ??
            Directory.current.path;
        final downloads = Directory(p.join(home, 'Downloads'));
        if (!downloads.existsSync()) downloads.createSync(recursive: true);
        final fileName =
            p.basename(Uri.parse(widget.imageUrl).path).split('?').first;
        outPath =
            p.join(downloads.path, fileName.isEmpty ? 'image.jpg' : fileName);
      } else {
        final docs = await getApplicationDocumentsDirectory();
        final fileName =
            p.basename(Uri.parse(widget.imageUrl).path).split('?').first;
        outPath = p.join(docs.path, fileName.isEmpty ? 'image.jpg' : fileName);
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
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pv = PhotoView(
      imageProvider: _provider,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      heroAttributes: widget.heroTag != null
          ? PhotoViewHeroAttributes(tag: widget.heroTag!)
          : null,
      minScale: widget.minScale,
      maxScale: PhotoViewComputedScale.covered * widget.maxScale,
      enableRotation: widget.enableRotation,
      loadingBuilder: (ctx, event) {
        final total = (event?.expectedTotalBytes ?? 0);
        final loaded = (event?.cumulativeBytesLoaded ?? 0);
        final percent = (total > 0) ? (loaded / total) : null;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              if (percent != null) ...[
                const SizedBox(height: 8),
                Text('${(percent * 100).toStringAsFixed(0)}%'),
              ],
            ],
          ),
        );
      },
      errorBuilder: (ctx, err, stack) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.broken_image_outlined,
                color: Colors.white70, size: 42),
            const SizedBox(height: 8),
            const Text('Failed to load image',
                style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => setState(() {}),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined),
            onPressed: _busy ? null : _share,
          ),
          IconButton(
            tooltip: 'Download',
            icon: const Icon(Icons.download_outlined),
            onPressed: _busy ? null : _download,
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: pv,
    );
  }
}
