import 'dart:async';
import 'dart:math';

import 'package:flutter/services.dart';

import '../core/media/format_plan.dart';
import '../core/media/prepare.dart';

/// Dart side of `crossdrop/export` (ios/Runner/ExportChannel.swift):
/// exports photo-library items to staged files (D-038).
class IosMedia implements MediaPlatform {
  IosMedia([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('crossdrop/export') {
    _channel.setMethodCallHandler(_onNative);
  }

  final MethodChannel _channel;
  final Map<String, void Function(double)> _progress = {};

  Future<Object?> _onNative(MethodCall call) async {
    if (call.method == 'progress') {
      final args = call.arguments as Map<Object?, Object?>;
      final fraction = (args['fraction'] as num?)?.toDouble();
      if (fraction != null) _progress[args['token']]?.call(fraction);
    }
    return null;
  }

  /// Names, kinds and dates for library ids. Missing ids are left out.
  Future<List<LibraryAsset>> describe(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final list = await _channel.invokeListMethod<Object?>('describe', {
      'ids': ids,
    });
    return [
      for (final m in (list ?? const []).cast<Map<Object?, Object?>>())
        LibraryAsset(
          id: m['id']! as String,
          kind: m['kind']! as String,
          originalName: m['originalName'] as String?,
          isLivePhoto: m['isLivePhoto'] as bool? ?? false,
        ),
    ];
  }

  @override
  Future<List<ResolvedFile>> resolveAsset(
    LibraryAsset asset,
    ExportPlan plan,
    String dir,
    PrepareControl control,
    void Function(double fraction) onProgress,
  ) async {
    final token = _token();
    _progress[token] = onProgress;
    final remove = control.onCancel(
      () => _channel.invokeMethod<void>('cancel', {'token': token}),
    );
    try {
      final m = (await _channel.invokeMapMethod<String, Object?>('export', {
        'id': asset.id,
        'dir': dir,
        'token': token,
        'jpeg': plan.convertToJpeg,
        'pairedVideo': plan.includePairedVideo,
      }))!;
      final createdMs = m['createdMs'] as num?;
      final created = createdMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(createdMs.toInt(), isUtc: true);
      final original = m['originalName'] as String?;
      return [
        for (final f in (m['files']! as List).cast<Map<Object?, Object?>>())
          ResolvedFile(
            ref: f['path']! as String,
            size: (f['size']! as num).toInt(),
            role: f['role']! as String,
            resourceName: f['resourceName'] as String?,
            originalName: original,
            created: created,
            converted: f['converted'] as bool? ?? false,
          ),
      ];
    } on PlatformException catch (e) {
      throw MediaUnavailable(e.code);
    } finally {
      remove();
      _progress.remove(token);
    }
  }

  /// One `describe` call for all of them (PHAssetResource names, no
  /// export).
  @override
  Future<Map<String, String>> originalNames(List<String> ids) async {
    try {
      return {
        for (final a in await describe(ids))
          if (a.originalName case final name? when name.isNotEmpty) a.id: name,
      };
    } on PlatformException {
      return const {};
    }
  }

  /// iOS documents are already local copies (D-041).
  @override
  Future<int> copyIntoStaging(
    String ref,
    String dest,
    PrepareControl control,
  ) => throw const MediaUnavailable('unreadable');

  static String _token() {
    final r = Random();
    return '${DateTime.now().microsecondsSinceEpoch}-${r.nextInt(1 << 32)}';
  }
}
