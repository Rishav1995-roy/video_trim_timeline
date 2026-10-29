import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:video_trim_timeline/video_trim_timeline.dart';

// 1x1 transparent PNG.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

class FakeProvider implements ThumbnailProvider {
  FakeProvider({this.mode = 'ok'});
  final String mode; // ok | null | throw
  int calls = 0;

  @override
  Future<ImageProvider?> thumbnailAt(Duration position, Size targetSize) async {
    calls++;
    if (mode == 'throw') throw StateError('decoder failed');
    if (mode == 'null') return null;
    return MemoryImage(_png);
  }
}
