// lib/util/storage_upload.dart
import 'dart:typed_data';
import 'dart:io' show File;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

String _contentTypeFromPath(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
  if (p.endsWith('.png')) return 'image/png';
  if (p.endsWith('.pdf')) return 'application/pdf';
  if (p.endsWith('.webp')) return 'image/webp';
  return 'application/octet-stream';
}

/// Upload raw bytes with uploader metadata; returns download URL.
Future<String> uploadBytesWithMeta({
  required String refPath,
  required Uint8List bytes,
  String? contentType,
  Map<String, String>? extraMeta,
}) async {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final ref = FirebaseStorage.instance.ref(refPath);
  final meta = SettableMetadata(
    contentType: contentType ?? 'application/octet-stream',
    customMetadata: {
      'uploaderUid': uid,
      if (extraMeta != null) ...extraMeta,
    },
  );
  await ref.putData(bytes, meta);
  return ref.getDownloadURL();
}

/// Upload from a file path with metadata; returns download URL.
Future<String> uploadFilePathWithMeta({
  required String refPath,
  required String filePath,
  String? contentType,
  Map<String, String>? extraMeta,
}) async {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final ref = FirebaseStorage.instance.ref(refPath);
  final meta = SettableMetadata(
    contentType: contentType ?? _contentTypeFromPath(filePath),
    customMetadata: {
      'uploaderUid': uid,
      if (extraMeta != null) ...extraMeta,
    },
  );
  await ref.putFile(File(filePath), meta);
  return ref.getDownloadURL();
}
