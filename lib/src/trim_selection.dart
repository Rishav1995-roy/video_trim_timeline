import 'package:flutter/foundation.dart';

/// Formats [d] as `m:ss` (or `h:mm:ss`), with tenths when [tenths] is true.
String formatTrimDuration(Duration d, {bool tenths = false}) {
  final ms = d.inMilliseconds < 0 ? 0 : d.inMilliseconds;
  final h = ms ~/ 3600000;
  final m = (ms ~/ 60000) % 60;
  final s = (ms ~/ 1000) % 60;
  final t = (ms % 1000) ~/ 100;
  final ss = s.toString().padLeft(2, '0');
  final base = h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
  return tenths ? '$base.$t' : base;
}

/// The plain result of a trim session: which part of the video to keep and
/// which frame to use as cover.
///
/// Hand it to whatever engine you use. It has no dependency on one.
///
/// ```dart
/// final args = selection.toFfmpegArguments(input: 'in.mp4', output: 'out.mp4');
/// // run: ffmpeg <args>   (any FFmpeg build, or your native editor)
/// ```
@immutable
class TrimSelection {
  /// Creates a selection. [start] must not be after [end].
  const TrimSelection({required this.start, required this.end, this.cover})
      : assert(start <= end, 'start must not be after end');

  /// Start of the kept range.
  final Duration start;

  /// End of the kept range.
  final Duration end;

  /// Position of the chosen cover frame, or null when none was picked.
  final Duration? cover;

  /// Length of the kept range.
  Duration get duration => end - start;

  /// Returns a copy with the given fields replaced.
  TrimSelection copyWith({Duration? start, Duration? end, Duration? cover}) =>
      TrimSelection(
        start: start ?? this.start,
        end: end ?? this.end,
        cover: cover ?? this.cover,
      );

  static String _secs(Duration d) =>
      (d.inMicroseconds / Duration.microsecondsPerSecond).toStringAsFixed(3);

  /// FFmpeg arguments (without the `ffmpeg` executable) that cut this range.
  ///
  /// `-ss` is placed before `-i` for fast seeking. With [copyStreams] true the
  /// streams are copied (fast, but cuts snap to key frames); false re-encodes
  /// for frame-accurate cuts.
  List<String> toFfmpegArguments({
    required String input,
    required String output,
    bool copyStreams = false,
  }) =>
      [
        '-y',
        '-ss',
        _secs(start),
        '-i',
        input,
        '-t',
        _secs(duration),
        if (copyStreams) ...['-c', 'copy'],
        output,
      ];

  /// FFmpeg arguments that extract the [cover] frame as one image.
  ///
  /// Uses [start] when no cover was picked.
  List<String> toCoverFfmpegArguments({
    required String input,
    required String output,
  }) =>
      [
        '-y',
        '-ss',
        _secs(cover ?? start),
        '-i',
        input,
        '-frames:v',
        '1',
        '-q:v',
        '2',
        output,
      ];

  /// A JSON-friendly map (microseconds), e.g. for a platform channel.
  Map<String, Object?> toJson() => {
        'startUs': start.inMicroseconds,
        'endUs': end.inMicroseconds,
        'coverUs': cover?.inMicroseconds,
      };

  /// Reads the map written by [toJson].
  factory TrimSelection.fromJson(Map<String, Object?> json) {
    final cover = json['coverUs'] as int?;
    return TrimSelection(
      start: Duration(microseconds: json['startUs']! as int),
      end: Duration(microseconds: json['endUs']! as int),
      cover: cover == null ? null : Duration(microseconds: cover),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TrimSelection &&
      other.start == start &&
      other.end == end &&
      other.cover == cover;

  @override
  int get hashCode => Object.hash(start, end, cover);

  @override
  String toString() =>
      'TrimSelection(${formatTrimDuration(start, tenths: true)} - '
      '${formatTrimDuration(end, tenths: true)}, cover: $cover)';
}
