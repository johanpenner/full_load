// lib/util/storage_upload.dart
// Utility for uploading to Firebase Storage with metadata/progress.
// Updates: Added try-catch, optional progress callback, MIME from 'mime' package for better type detection.

import 'dart:typed_data';
import 'dart:io' show File;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:mime/mime.dart'; // Add to pubspec: mime: ^1.0.0

/// Upload raw bytes with uploader metadata; returns download URL.
/// [onProgress] callback for upload progress (bytes sent / total).
Future<String> uploadBytesWithMeta({
  required String refPath,
  required Uint8List bytes,
  String? contentType,
  Map<String, String>? extraMeta,
  void Function(int sent, int total)? onProgress,
}) async {
  try {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseStorage.instance.ref(refPath);
    final meta = SettableMetadata(
      contentType: contentType ?? 'application/octet-stream',
      customMetadata: {
        'uploaderUid': uid,
        if (extraMeta != null) ...extraMeta,
      },
    );
    final uploadTask = ref.putData(bytes, meta);
    if (onProgress != null) {
      uploadTask.snapshotEvents.listen((TaskSnapshot snap) {
        onProgress(snap.bytesTransferred, snap.totalBytes);
      });
    }
    await uploadTask.whenComplete(() {});
    return await ref.getDownloadURL();
  } catch (e) {
    throw 'Upload failed: $e'; // Rethrow for caller handling
  }
}

/// Upload from a file path with metadata; returns download URL.
/// Detects content type from path/extension via mime package.
/// [onProgress] callback for upload progress.
Future<String> uploadFilePathWithMeta({
  required String refPath,
  required String filePath,
  String? contentType,
  Map<String, String>? extraMeta,
  void Function(int sent, int total)? onProgress,
}) async {
  try {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseStorage.instance.ref(refPath);
    final detectedType =
        contentType ?? lookupMimeType(filePath) ?? 'application/octet-stream';
    final meta = SettableMetadata(
      contentType: detectedType,
      customMetadata: {
        'uploaderUid': uid,
        if (extraMeta != null) ...extraMeta,
      },
    );
    final uploadTask = ref.putFile(File(filePath), meta);
    if (onProgress != null) {
      uploadTask.snapshotEvents.listen((TaskSnapshot snap) {
        onProgress(snap.bytesTransferred, snap.totalBytes);
      });
    }
    await uploadTask.whenComplete(() {});
    return await ref.getDownloadURL();
  } catch (e) {
    throw 'Upload failed: $e';
  }
}
