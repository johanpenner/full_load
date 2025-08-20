import 'dart:io';
body: _loading
? const Center(child: CircularProgressIndicator())
: _bytes == null
? _ErrorView(url: widget.urlOrPath)
: _isImage
? InteractiveViewer(child: Image.memory(_bytes!))
: _isPdf
? Center(
child: PdfPreview(
build: (format) async => _bytes!,
canChangePageFormat: false,
canChangeOrientation: false,
allowPrinting: false, // we already have a Print button
),
)
: _OtherFileView(localPath: _localPath!, url: widget.urlOrPath),
);
}
}


class _OtherFileView extends StatelessWidget {
final String localPath;
final String url;
const _OtherFileView({required this.localPath, required this.url});


@override
Widget build(BuildContext context) {
return Center(
child: Padding(
padding: const EdgeInsets.all(24),
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
const Icon(Icons.insert_drive_file, size: 56),
const SizedBox(height: 12),
const Text('Preview not supported in-app for this file type.'),
const SizedBox(height: 8),
FilledButton.icon(
onPressed: () async => OpenFilex.open(localPath),
icon: const Icon(Icons.open_in_new),
label: const Text('Open in External App'),
),
const SizedBox(height: 8),
TextButton.icon(
onPressed: () async => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
icon: const Icon(Icons.link),
label: const Text('Open Source Link'),
),
],
),
),
);
}
}


class _ErrorView extends StatelessWidget {
final String url;
const _ErrorView({required this.url});
@override
Widget build(BuildContext context) {
return Center(
child: Padding(
padding: const EdgeInsets.all(24),
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
const Icon(Icons.error_outline, size: 56),
const SizedBox(height: 12),
const Text('Failed to load file'),
const SizedBox(height: 8),
Text(url, textAlign: TextAlign.center),
],
),
),
);
}
}