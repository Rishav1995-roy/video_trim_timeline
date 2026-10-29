import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'thumbnail_provider.dart';
import 'thumbnail_strip.dart';
import 'trim_controller.dart';
import 'trim_selection.dart';
import 'trim_style.dart';

/// Lets the user pick the cover frame from inside the trimmed range.
///
/// Shows a strip of frames between [TrimController.start] and
/// [TrimController.end] with a draggable marker, and optionally a larger
/// preview of the chosen frame. The pick is stored in [TrimController.cover]
/// and follows the selection (it is clamped when the range shrinks).
class CoverPicker extends StatefulWidget {
  /// Creates a cover picker for [controller].
  const CoverPicker({
    super.key,
    required this.controller,
    this.thumbnails,
    this.style,
    this.showPreview = true,
    this.previewHeight = 140,
    this.mirrorInRtl = true,
    this.keyboardStep = const Duration(milliseconds: 500),
    this.label = 'Cover frame',
  });

  /// The state holder.
  final TrimController controller;

  /// Frames; null shows placeholders.
  final ThumbnailCache? thumbnails;

  /// Visuals; defaults to the color scheme of the theme.
  final TrimTimelineStyle? style;

  /// Show the large preview above the strip.
  final bool showPreview;

  /// Height of the preview.
  final double previewHeight;

  /// Mirror in right-to-left layouts.
  final bool mirrorInRtl;

  /// Step for semantic increase / decrease.
  final Duration keyboardStep;

  /// Screen-reader label.
  final String label;

  @override
  State<CoverPicker> createState() => _CoverPickerState();
}

class _CoverPickerState extends State<CoverPicker> {
  double _w = 1;
  bool _rtl = false;

  TrimController get c => widget.controller;

  Duration get _coverOrStart => c.cover ?? c.start;

  Duration _timeAtX(double x) {
    var f = _w <= 0 ? 0.0 : (x / _w).clamp(0.0, 1.0);
    if (_rtl) f = 1 - f;
    return c.start +
        Duration(microseconds: (c.selectedDuration.inMicroseconds * f).round());
  }

  double _fracOf(Duration t) {
    final len = c.selectedDuration.inMicroseconds;
    if (len <= 0) return 0;
    final f = (t - c.start).inMicroseconds / len;
    return _rtl ? 1 - f : f;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.style ??
        TrimTimelineStyle.fromColorScheme(Theme.of(context).colorScheme);
    _rtl =
        widget.mirrorInRtl && Directionality.of(context) == TextDirection.rtl;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showPreview)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Center(
                  child: SizedBox(
                    height: widget.previewHeight,
                    child: AspectRatio(
                      aspectRatio: s.thumbnailAspectRatio,
                      child: ClipRRect(
                        borderRadius: s.borderRadius,
                        child: ColoredBox(
                          color: s.backgroundColor,
                          child: ThumbTile(
                            cache: widget.thumbnails,
                            style: s,
                            size: Size(
                                widget.previewHeight * s.thumbnailAspectRatio,
                                widget.previewHeight),
                            position: _coverOrStart,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            LayoutBuilder(builder: (context, box) {
              _w = math.max(box.maxWidth.isFinite ? box.maxWidth : 320, 1);
              final markerX = _fracOf(_coverOrStart) * _w;
              return Semantics(
                label: widget.label,
                slider: true,
                value: formatTrimDuration(_coverOrStart, tenths: true),
                increasedValue: formatTrimDuration(
                    _coverOrStart + widget.keyboardStep,
                    tenths: true),
                decreasedValue: formatTrimDuration(
                    _coverOrStart - widget.keyboardStep,
                    tenths: true),
                onIncrease: () =>
                    c.setCover(_coverOrStart + widget.keyboardStep),
                onDecrease: () =>
                    c.setCover(_coverOrStart - widget.keyboardStep),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => c.setCover(_timeAtX(d.localPosition.dx)),
                  onHorizontalDragUpdate: (d) =>
                      c.setCover(_timeAtX(d.localPosition.dx)),
                  child: SizedBox(
                    height: s.height + 8,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 4,
                          height: s.height,
                          child: ClipRRect(
                            borderRadius: s.borderRadius,
                            child: ColoredBox(
                              color: s.backgroundColor,
                              child: Directionality(
                                textDirection: _rtl
                                    ? TextDirection.rtl
                                    : TextDirection.ltr,
                                child: ThumbnailStrip(
                                  cache: widget.thumbnails,
                                  style: s,
                                  from: c.start,
                                  span: c.selectedDuration,
                                  width: _w,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: markerX - 22,
                          top: 0,
                          width: 44,
                          height: s.height + 8,
                          child: IgnorePointer(
                            child: Center(
                              child: Container(
                                width: math.max(s.playheadWidth, 3) + 1,
                                decoration: BoxDecoration(
                                  color: s.coverColor,
                                  borderRadius: BorderRadius.circular(3),
                                  border: Border.all(
                                      color: s.playheadColor, width: 1.5),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
