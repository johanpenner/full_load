import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart'; // If not added, add to pubspec.yaml: webview_flutter: ^4.4.2 (or latest)

class DocumentViewerScreen extends StatefulWidget {
  final String? documentUrl; // Optional URL for the document (e.g., PDF, image)
  final String? filePath; // Optional local file path if not URL

  const DocumentViewerScreen({
    super.key,
    this.documentUrl,
    this.filePath,
  });

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  late WebViewController _controller;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDocument();
  }

  void _loadDocument() {
    if (widget.documentUrl != null) {
      // For web, use WebView to display PDFs or docs via URL
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              // Update loading bar if needed
            },
            onPageStarted: (String url) {
              setState(() => _isLoading = true);
            },
            onPageFinished: (String url) {
              setState(() => _isLoading = false);
            },
            onWebResourceError: (WebResourceError error) {
              setState(() {
                _isLoading = false;
                _error = 'Error loading document: ${error.description}';
              });
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.documentUrl!));
    } else if (widget.filePath != null) {
      // For local files, you might need a different approach, e.g., pdf_viewer package
      // For now, placeholder for local files
      setState(() {
        _error = 'Local file viewing not implemented yet.';
      });
    } else {
      setState(() {
        _error = 'No document provided.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Viewer'),
      ),
      body: _error != null
          ? Center(child: Text(_error!))
          : Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_isLoading)
                  const Center(
                    child: CircularProgressIndicator(),
                  ),
              ],
            ),
    );
  }
}
