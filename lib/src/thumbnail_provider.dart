import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';

/// Supplies preview frames for the timeline. Implement it with whatever you
/// have: a native frame extractor, an FFmpeg build, pre-rendered sprites.
///
/// Return null when no frame is available. The timeline then draws a
/// placeholder instead of failing.
abstract interface class ThumbnailProvider {
  /// Returns the frame at [position], ideally about [targetSize] logical
  /// pixels (multiply by the device pixel ratio if you want sharper frames).
  Future<ImageProvider?> thumbnailAt(Duration position, Size targetSize);
}

/// A [ThumbnailProvider] built from a function.
class FunctionThumbnailProvider implements ThumbnailProvider {
  /// Wraps [load].
  const FunctionThumbnailProvider(this.load);

  /// The loader.
  final Future<ImageProvider?> Function(Duration position, Size targetSize)
      load;

  @override
  Future<ImageProvider?> thumbnailAt(Duration position, Size targetSize) =>
      load(position, targetSize);
}

/// Caches frames from a [ThumbnailProvider] with an LRU policy, de-duplicates
/// concurrent requests and turns errors into null results.
class ThumbnailCache {
  /// Creates a cache for [provider] holding at most [capacity] frames.
  ///
  /// Requests are rounded to [quantum] so nearby positions share one frame.
  ThumbnailCache(
    this.provider, {
    this.capacity = 120,
    this.quantum = const Duration(milliseconds: 100),
  }) : assert(capacity > 0);

  /// The wrapped provider.
  final ThumbnailProvider provider;

  /// Maximum number of cached frames.
  final int capacity;

  /// Positions are rounded to a multiple of this.
  final Duration quantum;

  final LinkedHashMap<int, ImageProvider?> _done = LinkedHashMap();
  final Map<int, Future<ImageProvider?>> _pending = {};

  /// Number of frames currently cached (including known-missing ones).
  int get length => _done.length;

  /// Number of provider calls currently running.
  int get pendingCount => _pending.length;

  int _key(Duration p) {
    final q = quantum.inMicroseconds;
    return (p.inMicroseconds / q).round() * q;
  }

  /// The frame if already loaded. A hit refreshes its LRU position.
  ImageProvider? peek(Duration position) {
    final k = _key(position);
    if (!_done.containsKey(k)) return null;
    final v = _done.remove(k);
    _done[k] = v;
    return v;
  }

  /// Whether [position] has been resolved (even if the result was null).
  bool isResolved(Duration position) => _done.containsKey(_key(position));

  /// Loads the frame at [position]. Never throws: provider errors and null
  /// results both yield null.
  Future<ImageProvider?> load(Duration position, Size size) {
    final k = _key(position);
    if (_done.containsKey(k)) return Future.value(peek(position));
    return _pending[k] ??= _fetch(k, size);
  }

  Future<ImageProvider?> _fetch(int key, Size size) async {
    ImageProvider? result;
    try {
      result = await provider.thumbnailAt(Duration(microseconds: key), size);
    } catch (e, st) {
      developer.log('Thumbnail provider failed for $key us: $e',
          name: 'video_trim_timeline', error: e, stackTrace: st);
    } finally {
      _pending.remove(key);
    }
    _done[key] = result;
    while (_done.length > capacity) {
      _done.remove(_done.keys.first);
    }
    return result;
  }

  /// Forgets everything (e.g. when the video changes).
  void clear() {
    _done.clear();
    _pending.clear();
  }
}
