import 'package:flutter/material.dart';

/// Built-in handle looks. Use [TrimTimelineStyle.handleBuilder] for anything else.
enum TrimHandleShape {
  /// A rectangle with a grip.
  bar,

  /// A rectangle with rounded outer corners and a grip.
  rounded,

  /// A narrow pill without grip.
  pill,

  /// A rounded bar with a chevron pointing outwards.
  chevron,
}

/// Which side of the selection a handle sits on.
enum TrimHandleSide {
  /// In-point.
  start,

  /// Out-point.
  end,
}

/// Builds a custom handle. [side] is the logical side (the start handle is on
/// the right in RTL); [active] is true while dragged; [size] is the visual size.
typedef TrimHandleBuilder = Widget Function(
  BuildContext context,
  TrimHandleSide side,
  bool active,
  Size size,
);

/// Builds the placeholder shown for a thumbnail that is loading or missing.
typedef TrimPlaceholderBuilder = Widget Function(BuildContext context);

/// Visual configuration of [TrimTimeline] and `CoverPicker`.
@immutable
class TrimTimelineStyle {
  /// Creates a style. Defaults suit a dark-on-light Material app; use
  /// [TrimTimelineStyle.fromColorScheme] to follow the theme.
  const TrimTimelineStyle({
    this.height = 64,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.handleWidth = 14,
    this.handleHitWidth = 44,
    this.handleShape = TrimHandleShape.rounded,
    this.handleBuilder,
    this.handleColor = const Color(0xFFFFC107),
    this.handleActiveColor = const Color(0xFFFFD54F),
    this.handleGripColor = const Color(0xFF3A2E00),
    this.overlayColor = const Color(0xAA000000),
    this.borderColor = const Color(0xFFFFC107),
    this.borderWidth = 2.5,
    this.playheadColor = const Color(0xFFFFFFFF),
    this.playheadWidth = 2.5,
    this.playheadHeadSize = 12,
    this.showPlayhead = true,
    this.coverColor = const Color(0xFFE91E63),
    this.placeholderColor = const Color(0xFF9E9E9E),
    this.placeholderBuilder,
    this.thumbnailAspectRatio = 16 / 9,
    this.backgroundColor = const Color(0xFF212121),
  })  : assert(handleHitWidth >= handleWidth),
        assert(height > 0);

  /// Follows [scheme]: primary for handles and border, surface tones elsewhere.
  factory TrimTimelineStyle.fromColorScheme(ColorScheme scheme) =>
      TrimTimelineStyle(
        handleColor: scheme.primary,
        handleActiveColor: scheme.primaryContainer,
        handleGripColor: scheme.onPrimary,
        borderColor: scheme.primary,
        overlayColor: scheme.scrim.withValues(alpha: 0.6),
        playheadColor: scheme.onSurface,
        coverColor: scheme.tertiary,
        placeholderColor: scheme.outline,
        backgroundColor: scheme.surfaceContainerHighest,
      );

  /// Height of the thumbnail strip.
  final double height;

  /// Corner radius of the strip.
  final BorderRadius borderRadius;

  /// Visual width of a handle.
  final double handleWidth;

  /// Touch-target width of a handle (at least [handleWidth]). 44 follows
  /// platform guidance; mostly extends outwards so handles stay grabbable
  /// even when the selection is at its minimum.
  final double handleHitWidth;

  /// Built-in handle shape (ignored when [handleBuilder] is set).
  final TrimHandleShape handleShape;

  /// Fully custom handle widget.
  final TrimHandleBuilder? handleBuilder;

  /// Handle fill.
  final Color handleColor;

  /// Handle fill while dragged.
  final Color handleActiveColor;

  /// Color of the grip / chevron on the handle.
  final Color handleGripColor;

  /// Color laid over the trimmed-away parts.
  final Color overlayColor;

  /// Border drawn around the kept range between the handles.
  final Color borderColor;

  /// Width of that border.
  final double borderWidth;

  /// Playhead line color.
  final Color playheadColor;

  /// Playhead line width.
  final double playheadWidth;

  /// Diameter of the playhead's round head.
  final double playheadHeadSize;

  /// Whether the playhead is drawn.
  final bool showPlayhead;

  /// Color of the cover-frame marker.
  final Color coverColor;

  /// Fill of a missing / loading thumbnail.
  final Color placeholderColor;

  /// Custom placeholder widget for a missing / loading thumbnail.
  final TrimPlaceholderBuilder? placeholderBuilder;

  /// Width / height of one thumbnail tile.
  final double thumbnailAspectRatio;

  /// Color behind the thumbnails.
  final Color backgroundColor;

  /// Returns a copy with the given fields replaced.
  TrimTimelineStyle copyWith({
    double? height,
    BorderRadius? borderRadius,
    double? handleWidth,
    double? handleHitWidth,
    TrimHandleShape? handleShape,
    TrimHandleBuilder? handleBuilder,
    Color? handleColor,
    Color? handleActiveColor,
    Color? handleGripColor,
    Color? overlayColor,
    Color? borderColor,
    double? borderWidth,
    Color? playheadColor,
    double? playheadWidth,
    double? playheadHeadSize,
    bool? showPlayhead,
    Color? coverColor,
    Color? placeholderColor,
    TrimPlaceholderBuilder? placeholderBuilder,
    double? thumbnailAspectRatio,
    Color? backgroundColor,
  }) =>
      TrimTimelineStyle(
        height: height ?? this.height,
        borderRadius: borderRadius ?? this.borderRadius,
        handleWidth: handleWidth ?? this.handleWidth,
        handleHitWidth: handleHitWidth ?? this.handleHitWidth,
        handleShape: handleShape ?? this.handleShape,
        handleBuilder: handleBuilder ?? this.handleBuilder,
        handleColor: handleColor ?? this.handleColor,
        handleActiveColor: handleActiveColor ?? this.handleActiveColor,
        handleGripColor: handleGripColor ?? this.handleGripColor,
        overlayColor: overlayColor ?? this.overlayColor,
        borderColor: borderColor ?? this.borderColor,
        borderWidth: borderWidth ?? this.borderWidth,
        playheadColor: playheadColor ?? this.playheadColor,
        playheadWidth: playheadWidth ?? this.playheadWidth,
        playheadHeadSize: playheadHeadSize ?? this.playheadHeadSize,
        showPlayhead: showPlayhead ?? this.showPlayhead,
        coverColor: coverColor ?? this.coverColor,
        placeholderColor: placeholderColor ?? this.placeholderColor,
        placeholderBuilder: placeholderBuilder ?? this.placeholderBuilder,
        thumbnailAspectRatio: thumbnailAspectRatio ?? this.thumbnailAspectRatio,
        backgroundColor: backgroundColor ?? this.backgroundColor,
      );
}
