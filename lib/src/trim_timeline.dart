import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'thumbnail_provider.dart';
import 'thumbnail_strip.dart';
import 'trim_controller.dart';
import 'trim_selection.dart';
import 'trim_style.dart';

/// The trim timeline: thumbnail strip, two trim handles, playhead, optional
/// cover marker and zoom.
///
/// Interactions (one deterministic pointer handler, no gesture-arena fights):
/// * drag a handle to trim (touch target of [TrimTimelineStyle.handleHitWidth],
///   sized so each handle stays grabbable at the minimum selection),
/// * tap or drag anywhere else to move the playhead,
/// * pinch with two fingers to zoom and pan, or use Ctrl/Cmd + scroll to zoom
///   and plain scroll to pan,
/// * keyboard arrows on a focused handle, and semantic increase / decrease
///   actions for screen readers.
///
/// In right-to-left layouts the timeline is mirrored unless [mirrorInRtl] is
/// false.
class TrimTimeline extends StatefulWidget {
  /// Creates a timeline for [controller].
  const TrimTimeline({
    super.key,
    required this.controller,
    this.thumbnails,
    this.style,
    this.mirrorInRtl = true,
    this.showCoverMarker = true,
    this.enableZoomGestures = true,
    this.keyboardStep = const Duration(seconds: 1),
    this.startHandleLabel = 'Trim start',
    this.endHandleLabel = 'Trim end',
    this.playheadLabel = 'Playhead',
  });

  /// The state holder.
  final TrimController controller;

  /// Frames for the strip; null shows placeholders only.
  final ThumbnailCache? thumbnails;

  /// Visuals; defaults to [TrimTimelineStyle.fromColorScheme] of the theme.
  final TrimTimelineStyle? style;

  /// Mirror left-to-right in RTL.
  final bool mirrorInRtl;

  /// Draw a marker where the cover frame is.
  final bool showCoverMarker;

  /// Allow pinch / wheel zoom.
  final bool enableZoomGestures;

  /// Step for arrow keys and semantic increase / decrease.
  final Duration keyboardStep;

  /// Screen-reader label of the start handle.
  final String startHandleLabel;

  /// Screen-reader label of the end handle.
  final String endHandleLabel;

  /// Screen-reader label of the playhead.
  final String playheadLabel;

  @override
  State<TrimTimeline> createState() => _TrimTimelineState();
}

enum _Mode { none, handle, scrub, zoom }

class _TrimTimelineState extends State<TrimTimeline> {
  final Map<int, Offset> _pointers = {};
  _Mode _mode = _Mode.none;
  TrimHandle? _handle;
  double _stripWidth = 1;
  bool _rtl = false;
  double _pad = 0;
  double _dragDx = 0;
  Duration _dragStartTime = Duration.zero;
  Duration _dragViewStart = Duration.zero;
  double _zoomBase = 1;
  double _distBase = 1;

  TrimController get c => widget.controller;

  TrimTimelineStyle _style(BuildContext context) =>
      widget.style ??
      TrimTimelineStyle.fromColorScheme(Theme.of(context).colorScheme);

  // Handles sit outside the selection; the touch target extends mostly outward.
  static const double _outward = 0.8;

  double _xOf(Duration t) {
    final f = c.fractionOf(t);
    final x = f * _stripWidth;
    return _rtl ? _stripWidth - x : x;
  }

  double _fracOfX(double localX) {
    final x = localX - _pad;
    final f = (_stripWidth <= 0 ? 0 : x / _stripWidth).toDouble();
    return _rtl ? 1 - f : f;
  }

  Rect _hitRect(TrimHandle h, TrimTimelineStyle s, double top) {
    final t = h == TrimHandle.start ? c.start : c.end;
    final x = _pad + _xOf(t);
    // outward direction in screen space
    final outwardLeft = (h == TrimHandle.start) != _rtl;
    final left = outwardLeft
        ? x - s.handleHitWidth * _outward
        : x - s.handleHitWidth * (1 - _outward);
    return Rect.fromLTWH(left, 0, s.handleHitWidth, top + s.height + top);
  }

  bool _inView(Duration t) {
    final f = c.fractionOf(t);
    return f >= -0.0001 && f <= 1.0001;
  }

  void _down(PointerDownEvent e, TrimTimelineStyle s, double top) {
    _pointers[e.pointer] = e.localPosition;
    if (c.totalDuration == Duration.zero) return;
    if (_pointers.length == 1) {
      TrimHandle? hit;
      // The end handle is tested first only if it is nearer, so when both
      // overlap the closest one is picked.
      final cands = <TrimHandle>[
        if (_inView(c.start)) TrimHandle.start,
        if (_inView(c.end)) TrimHandle.end,
      ].where((h) => _hitRect(h, s, top).contains(e.localPosition)).toList();
      if (cands.isNotEmpty) {
        cands.sort((a, b) {
          double d(TrimHandle h) => (e.localPosition.dx -
                  (_pad + _xOf(h == TrimHandle.start ? c.start : c.end)))
              .abs();
          return d(a).compareTo(d(b));
        });
        hit = cands.first;
      }
      if (hit != null) {
        _mode = _Mode.handle;
        _handle = hit;
        _dragDx = 0;
        _dragStartTime = hit == TrimHandle.start ? c.start : c.end;
        _dragViewStart = c.viewStart;
        c.beginHandleDrag(hit);
      } else {
        _mode = _Mode.scrub;
        c.seek(c.timeAt(_fracOfX(e.localPosition.dx)));
      }
    } else if (_pointers.length == 2 &&
        widget.enableZoomGestures &&
        _mode != _Mode.handle) {
      _mode = _Mode.zoom;
      final p = _pointers.values.toList();
      _distBase = math.max((p[0] - p[1]).distance, 1);
      _zoomBase = c.zoom;
    }
  }

  void _move(PointerMoveEvent e) {
    final prev = _pointers[e.pointer];
    if (prev == null) return;
    _pointers[e.pointer] = e.localPosition;
    switch (_mode) {
      case _Mode.handle:
        _dragDx += e.localPosition.dx - prev.dx;
        _applyHandleDrag(e.localPosition.dx);
      case _Mode.scrub:
        c.seek(c.timeAt(_fracOfX(e.localPosition.dx)));
      case _Mode.zoom:
        if (_pointers.length >= 2) {
          final p = _pointers.values.toList();
          final dist = math.max((p[0] - p[1]).distance, 1);
          final focal = (p[0] + p[1]) / 2;
          final prevFocalX = (prev.dx +
                  _pointers.entries
                      .firstWhere((en) => en.key != e.pointer)
                      .value
                      .dx) /
              2;
          c.setZoom(_zoomBase * dist / _distBase,
              focalFraction: _fracOfX(focal.dx));
          final dxFrac = (focal.dx - prevFocalX) /
              math.max(_stripWidth, 1) /
              2; // each pointer moves half
          final shift = c.viewSpan.inMicroseconds * dxFrac * (_rtl ? 1 : -1);
          if (shift != 0) c.scrollBy(Duration(microseconds: shift.round()));
        }
      case _Mode.none:
        break;
    }
  }

  void _applyHandleDrag(double localX) {
    final h = _handle;
    if (h == null) return;
    // Auto-scroll when dragging near an edge of a zoomed timeline.
    if (c.zoom > 1) {
      final x = localX - _pad;
      final edge = 28.0;
      final dir = _rtl ? -1 : 1;
      if (x < edge) {
        c.scrollBy(Duration(
            microseconds: (-c.viewSpan.inMicroseconds * 0.012 * dir).round()));
      } else if (x > _stripWidth - edge) {
        c.scrollBy(Duration(
            microseconds: (c.viewSpan.inMicroseconds * 0.012 * dir).round()));
      }
    }
    final dt = c.viewSpan.inMicroseconds *
        (_dragDx / math.max(_stripWidth, 1)) *
        (_rtl ? -1 : 1);
    final scrolled = (c.viewStart - _dragViewStart).inMicroseconds;
    final target =
        _dragStartTime + Duration(microseconds: (dt + scrolled).round());
    if (h == TrimHandle.start) {
      c.setStart(target);
    } else {
      c.setEnd(target);
    }
  }

  void _up(PointerEvent e) {
    _pointers.remove(e.pointer);
    if (_pointers.isEmpty) {
      if (_mode == _Mode.handle) c.endHandleDrag();
      _mode = _Mode.none;
      _handle = null;
    } else if (_mode == _Mode.zoom && _pointers.length < 2) {
      _mode = _Mode.none;
    }
  }

  void _signal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || c.totalDuration == Duration.zero) return;
    final ctrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (ctrl && widget.enableZoomGestures) {
      GestureBinding.instance.pointerSignalResolver.register(e, (_) {
        c.zoomBy(math.exp(-e.scrollDelta.dy / 200),
            focalFraction: _fracOfX(e.localPosition.dx));
      });
    } else if (c.zoom > 1) {
      GestureBinding.instance.pointerSignalResolver.register(e, (_) {
        final d = e.scrollDelta.dx != 0 ? e.scrollDelta.dx : e.scrollDelta.dy;
        final f = d / math.max(_stripWidth, 1);
        c.scrollBy(Duration(
            microseconds:
                (c.viewSpan.inMicroseconds * f * (_rtl ? -1 : 1)).round()));
      });
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final s = _style(context);
    _rtl =
        widget.mirrorInRtl && Directionality.of(context) == TextDirection.rtl;
    final top = math.max(s.playheadHeadSize / 2, 4).toDouble();
    _pad = s.handleHitWidth * _outward;
    final totalH = s.height + top * 2;

    return LayoutBuilder(builder: (context, box) {
      final w = box.hasBoundedWidth ? box.maxWidth : 320.0;
      _stripWidth = math.max(w - _pad * 2, 1);
      return ListenableBuilder(
        listenable: c,
        builder: (context, _) {
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (e) => _down(e, s, top),
            onPointerMove: _move,
            onPointerUp: _up,
            onPointerCancel: _up,
            onPointerSignal: _signal,
            child: SizedBox(
              width: w,
              height: totalH,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: _pad,
                    top: top,
                    width: _stripWidth,
                    height: s.height,
                    child: ClipRRect(
                      borderRadius: s.borderRadius,
                      child: ColoredBox(
                        color: s.backgroundColor,
                        child: Directionality(
                          textDirection:
                              _rtl ? TextDirection.rtl : TextDirection.ltr,
                          child: ThumbnailStrip(
                            cache: widget.thumbnails,
                            style: s,
                            from: c.viewStart,
                            span: c.viewSpan,
                            width: _stripWidth,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _OverlayPainter(
                          controller: c,
                          style: s,
                          pad: _pad,
                          top: top,
                          stripWidth: _stripWidth,
                          rtl: _rtl,
                          showCover: widget.showCoverMarker,
                        ),
                      ),
                    ),
                  ),
                  if (c.totalDuration > Duration.zero) ...[
                    _handleWidget(TrimHandle.start, s, top),
                    _handleWidget(TrimHandle.end, s, top),
                    _playheadSemantics(s, top),
                  ],
                ],
              ),
            ),
          );
        },
      );
    });
  }

  Widget _handleWidget(TrimHandle h, TrimTimelineStyle s, double top) {
    final t = h == TrimHandle.start ? c.start : c.end;
    if (!_inView(t)) return const SizedBox.shrink();
    final x = _pad + _xOf(t);
    final outwardLeft = (h == TrimHandle.start) != _rtl;
    final visualLeft = outwardLeft ? x - s.handleWidth : x;
    final active = c.activeHandle == h;
    final side =
        h == TrimHandle.start ? TrimHandleSide.start : TrimHandleSide.end;
    final size = Size(s.handleWidth, s.height);
    final visual = s.handleBuilder?.call(context, side, active, size) ??
        CustomPaint(
          size: size,
          painter: _HandlePainter(
            shape: s.handleShape,
            color: active ? s.handleActiveColor : s.handleColor,
            grip: s.handleGripColor,
            outwardLeft: outwardLeft,
          ),
        );
    final rect = _hitRect(h, s, top);
    final label =
        h == TrimHandle.start ? widget.startHandleLabel : widget.endHandleLabel;
    final step = widget.keyboardStep;
    void nudge(int sign) {
      final d = step * sign;
      c.beginHandleDrag(h);
      if (h == TrimHandle.start) {
        c.setStart(c.start + d);
      } else {
        c.setEnd(c.end + d);
      }
      c.endHandleDrag();
    }

    return Positioned.fromRect(
      rect: rect,
      child: Semantics(
        label: label,
        slider: true,
        value: formatTrimDuration(t, tenths: true),
        increasedValue: formatTrimDuration(t + step, tenths: true),
        decreasedValue: formatTrimDuration(t - step, tenths: true),
        onIncrease: () => nudge(1),
        onDecrease: () => nudge(-1),
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is KeyUpEvent) return KeyEventResult.ignored;
            final big = HardwareKeyboard.instance.isShiftPressed ? 5 : 1;
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              nudge(_rtl ? -big : big);
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              nudge(_rtl ? big : -big);
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: visualLeft - rect.left,
                top: top,
                width: s.handleWidth,
                height: s.height,
                child: IgnorePointer(child: visual),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playheadSemantics(TrimTimelineStyle s, double top) {
    final step = widget.keyboardStep;
    final x = _pad + _xOf(c.playhead);
    return Positioned(
      left: x - 12,
      top: 0,
      width: 24,
      height: top * 2 + s.height,
      child: Semantics(
        label: widget.playheadLabel,
        slider: true,
        value: formatTrimDuration(c.playhead, tenths: true),
        increasedValue: formatTrimDuration(c.playhead + step, tenths: true),
        decreasedValue: formatTrimDuration(c.playhead - step, tenths: true),
        onIncrease: () => c.seek(c.playhead + step),
        onDecrease: () => c.seek(c.playhead - step),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  _OverlayPainter({
    required this.controller,
    required this.style,
    required this.pad,
    required this.top,
    required this.stripWidth,
    required this.rtl,
    required this.showCover,
  }) : super(repaint: controller);

  final TrimController controller;
  final TrimTimelineStyle style;
  final double pad;
  final double top;
  final double stripWidth;
  final bool rtl;
  final bool showCover;

  double x(Duration t) {
    final f = controller.fractionOf(t).clamp(0.0, 1.0);
    final v = f * stripWidth;
    return pad + (rtl ? stripWidth - v : v);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (controller.totalDuration == Duration.zero) return;
    final strip = Rect.fromLTWH(pad, top, stripWidth, style.height);
    final a = x(controller.start);
    final b = x(controller.end);
    final left = math.min(a, b);
    final right = math.max(a, b);
    final dim = Paint()..color = style.overlayColor;
    final rr = style.borderRadius;
    canvas.save();
    canvas.clipRRect(rr.toRRect(strip));
    if (left > strip.left) {
      canvas.drawRect(
          Rect.fromLTRB(strip.left, strip.top, left, strip.bottom), dim);
    }
    if (right < strip.right) {
      canvas.drawRect(
          Rect.fromLTRB(right, strip.top, strip.right, strip.bottom), dim);
    }
    canvas.restore();

    if (style.borderWidth > 0 && right > left) {
      final p = Paint()
        ..color = style.borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = style.borderWidth;
      final h = style.borderWidth / 2;
      canvas.drawLine(
          Offset(left, strip.top + h), Offset(right, strip.top + h), p);
      canvas.drawLine(
          Offset(left, strip.bottom - h), Offset(right, strip.bottom - h), p);
    }

    final cover = controller.cover;
    if (showCover && cover != null) {
      final cx = x(cover);
      final p = Paint()..color = style.coverColor;
      final path = Path()
        ..moveTo(cx, strip.bottom - 9)
        ..lineTo(cx - 6, strip.bottom)
        ..lineTo(cx + 6, strip.bottom)
        ..close();
      canvas.drawPath(path, p);
    }

    if (style.showPlayhead) {
      final px = x(controller.playhead);
      final p = Paint()
        ..color = style.playheadColor
        ..strokeWidth = style.playheadWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
          Offset(px, strip.top - 2), Offset(px, strip.bottom + 2), p);
      canvas.drawCircle(
          Offset(px, strip.top - 2), style.playheadHeadSize / 2, p);
    }
  }

  @override
  bool shouldRepaint(_OverlayPainter old) =>
      old.style != style ||
      old.pad != pad ||
      old.stripWidth != stripWidth ||
      old.rtl != rtl ||
      old.showCover != showCover;
}

class _HandlePainter extends CustomPainter {
  _HandlePainter({
    required this.shape,
    required this.color,
    required this.grip,
    required this.outwardLeft,
  });

  final TrimHandleShape shape;
  final Color color;
  final Color grip;
  final bool outwardLeft;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color;
    final r = Radius.circular(switch (shape) {
      TrimHandleShape.bar => 0,
      TrimHandleShape.rounded || TrimHandleShape.chevron => 8,
      TrimHandleShape.pill => size.width / 2,
    });
    final rect = Offset.zero & size;
    final rrect = switch (shape) {
      TrimHandleShape.pill => RRect.fromRectAndRadius(rect, r),
      _ => outwardLeft
          ? RRect.fromRectAndCorners(rect, topLeft: r, bottomLeft: r)
          : RRect.fromRectAndCorners(rect, topRight: r, bottomRight: r),
    };
    canvas.drawRRect(rrect, fill);
    final g = Paint()
      ..color = grip
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final cx = size.width / 2;
    final cy = size.height / 2;
    switch (shape) {
      case TrimHandleShape.pill:
        break;
      case TrimHandleShape.chevron:
        final d = outwardLeft ? -1 : 1;
        canvas.drawPath(
            Path()
              ..moveTo(cx - 2 * d, cy - 7)
              ..lineTo(cx + 2 * d, cy)
              ..lineTo(cx - 2 * d, cy + 7),
            g);
      case TrimHandleShape.bar || TrimHandleShape.rounded:
        canvas.drawLine(Offset(cx, cy - 8), Offset(cx, cy + 8), g);
    }
  }

  @override
  bool shouldRepaint(_HandlePainter old) =>
      old.shape != shape || old.color != color || old.grip != grip;
}
