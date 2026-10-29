import 'dart:async';

import 'package:flutter/widgets.dart';

import 'thumbnail_provider.dart';
import 'trim_style.dart';

/// Internal: a row of lazily loaded thumbnail tiles covering
/// [from] .. [from] + [span].
class ThumbnailStrip extends StatelessWidget {
  const ThumbnailStrip({
    super.key,
    required this.cache,
    required this.style,
    required this.from,
    required this.span,
    required this.width,
  });

  final ThumbnailCache? cache;
  final TrimTimelineStyle style;
  final Duration from;
  final Duration span;
  final double width;

  @override
  Widget build(BuildContext context) {
    final tileW = style.height * style.thumbnailAspectRatio;
    final count = width <= 0 ? 0 : (width / tileW).ceil().clamp(1, 400);
    if (count == 0) return const SizedBox.shrink();
    final w = width / count;
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          SizedBox(
            width: w,
            height: style.height,
            child: ThumbTile(
              // Keyed by index so a tile is reused while zooming/scrolling.
              key: ValueKey(i),
              cache: cache,
              style: style,
              size: Size(w, style.height),
              position: span == Duration.zero
                  ? Duration.zero
                  : from +
                      Duration(
                          microseconds:
                              (span.inMicroseconds * (i + 0.5) / count)
                                  .round()),
            ),
          ),
      ],
    );
  }
}

/// Internal: one tile. Shows the cached frame, else a placeholder, and loads
/// (debounced after the first load) without ever throwing.
class ThumbTile extends StatefulWidget {
  const ThumbTile({
    super.key,
    required this.cache,
    required this.style,
    required this.size,
    required this.position,
    this.fit = BoxFit.cover,
  });

  final ThumbnailCache? cache;
  final TrimTimelineStyle style;
  final Size size;
  final Duration position;
  final BoxFit fit;

  @override
  State<ThumbTile> createState() => _ThumbTileState();
}

class _ThumbTileState extends State<ThumbTile> {
  ImageProvider? _image;
  Timer? _debounce;
  bool _loadedOnce = false;

  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  void didUpdateWidget(ThumbTile old) {
    super.didUpdateWidget(old);
    if (old.position != widget.position || old.cache != widget.cache) {
      _request();
    }
  }

  void _request() {
    _debounce?.cancel();
    final cache = widget.cache;
    if (cache == null) return;
    final hit = cache.peek(widget.position);
    if (hit != null || cache.isResolved(widget.position)) {
      _image = hit;
      _loadedOnce = true;
      return;
    }
    final pos = widget.position;
    void go() {
      cache.load(pos, widget.size).then((img) {
        if (!mounted || pos != widget.position) return;
        setState(() {
          _image = img;
          _loadedOnce = true;
        });
      });
    }

    if (_loadedOnce) {
      _debounce = Timer(const Duration(milliseconds: 80), go);
    } else {
      go();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Widget _placeholder(BuildContext context) =>
      widget.style.placeholderBuilder?.call(context) ??
      ColoredBox(
        color: widget.style.placeholderColor.withValues(alpha: 0.35),
        child: const SizedBox.expand(),
      );

  @override
  Widget build(BuildContext context) {
    final img = _image;
    if (img == null) return _placeholder(context);
    return Image(
      image: img,
      fit: widget.fit,
      gaplessPlayback: true,
      excludeFromSemantics: true,
      errorBuilder: (c, _, __) => _placeholder(c),
    );
  }
}
