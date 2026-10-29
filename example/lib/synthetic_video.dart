import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:video_trim_timeline/video_trim_timeline.dart';

/// A made-up "video": every frame is drawn from the timestamp (gradient scene
/// that changes every few seconds plus a bouncing ball). No real video, no
/// photos; it only exists so the example needs no assets or player.
class SyntheticVideo {
  const SyntheticVideo({this.duration = const Duration(seconds: 48)});

  final Duration duration;

  static const _scenes = <List<Color>>[
    [Color(0xFF283593), Color(0xFF00ACC1)],
    [Color(0xFFD84315), Color(0xFFFFB300)],
    [Color(0xFF2E7D32), Color(0xFFC0CA33)],
    [Color(0xFF6A1B9A), Color(0xFFEC407A)],
    [Color(0xFF00695C), Color(0xFF4FC3F7)],
    [Color(0xFF37474F), Color(0xFF90A4AE)],
  ];

  /// Paints the frame at [t] into [canvas].
  void paintFrame(Canvas canvas, Size size, Duration t) {
    final sec = t.inMilliseconds / 1000;
    final scene = (sec ~/ 8) % _scenes.length;
    final colors = _scenes[scene];
    final shift = (sec % 8) / 8;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(size.width * shift, 0),
          Offset(size.width * (1 - shift), size.height),
          colors,
        ),
    );
    final ball = Offset(
      size.width * (0.5 + 0.38 * math.sin(sec * 1.7)),
      size.height * (0.5 + 0.3 * math.cos(sec * 2.3)),
    );
    canvas.drawCircle(
      ball,
      size.shortestSide * 0.16,
      Paint()..color = const Color(0xCCFFFFFF),
    );
    canvas.drawRect(
      Rect.fromLTWH(
        0,
        size.height * 0.8,
        size.width * (sec % 8) / 8,
        size.height * 0.04,
      ),
      Paint()..color = const Color(0x66000000),
    );
  }
}

/// Paints one frame of [video] at [position].
class FramePainter extends CustomPainter {
  const FramePainter(this.video, this.position);

  final SyntheticVideo video;
  final Duration position;

  @override
  void paint(Canvas canvas, Size size) =>
      video.paintFrame(canvas, size, position);

  @override
  bool shouldRepaint(FramePainter oldDelegate) => oldDelegate.position != position;
}

/// Renders synthetic frames to PNG and serves them as [MemoryImage]s, like a
/// real extractor would. Results are memoised so repeated requests share
/// one [ImageProvider].
class SyntheticThumbnails implements ThumbnailProvider {
  SyntheticThumbnails(this.video, {this.delay = Duration.zero});

  final SyntheticVideo video;

  /// Artificial latency, to show lazy loading in the example.
  final Duration delay;

  final Map<int, MemoryImage> _memo = {};

  @override
  Future<ImageProvider?> thumbnailAt(Duration position, Size targetSize) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final key = position.inMilliseconds ~/ 100;
    final hit = _memo[key];
    if (hit != null) return hit;
    final w = (targetSize.width * 2).clamp(32, 640).round();
    final h = (targetSize.height * 2).clamp(32, 640).round();
    final rec = ui.PictureRecorder();
    video.paintFrame(Canvas(rec), Size(w.toDouble(), h.toDouble()), position);
    final image = await rec.endRecording().toImage(w, h);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (data == null) return null;
    return _memo[key] = MemoryImage(data.buffer.asUint8List());
  }
}
