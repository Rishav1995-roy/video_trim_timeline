import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'playback_adapter.dart';
import 'trim_selection.dart';

/// Which trim handle is being referred to.
enum TrimHandle {
  /// The start (in-point) handle.
  start,

  /// The end (out-point) handle.
  end,
}

/// Receives feedback events so the app can add haptics or sounds.
///
/// All callbacks are optional. [TrimHaptics.system] wires them to
/// `HapticFeedback` for you.
class TrimHaptics {
  /// Creates a hook set.
  const TrimHaptics({
    this.onGrab,
    this.onTick,
    this.onLimit,
    this.onRelease,
    this.onCoverChanged,
  });

  /// Standard system feedback: a selection click on grab and tick, a light
  /// impact at limits and when the cover moves.
  factory TrimHaptics.system() => TrimHaptics(
        onGrab: (_) => HapticFeedback.selectionClick(),
        onTick: HapticFeedback.selectionClick,
        onLimit: HapticFeedback.lightImpact,
        onCoverChanged: HapticFeedback.selectionClick,
      );

  /// A handle was picked up.
  final void Function(TrimHandle handle)? onGrab;

  /// The dragged handle crossed another whole second (a light "tick").
  final VoidCallback? onTick;

  /// A drag hit the minimum or maximum duration, or a timeline edge.
  final VoidCallback? onLimit;

  /// A handle was released.
  final void Function(TrimHandle handle)? onRelease;

  /// The cover frame was moved.
  final VoidCallback? onCoverChanged;
}

/// Owns the trim state: total duration, selection, playhead, cover and zoom.
///
/// Every setter clamps, so no input (zero duration, NaN, reversed handles) can
/// produce an invalid state. A video whose length is not known yet is
/// supported: create the controller with [Duration.zero] and call
/// [setTotalDuration] when the player reports it.
class TrimController extends ChangeNotifier {
  /// Creates a controller for a video of [totalDuration].
  ///
  /// The selection is limited by [minDuration] and the optional [maxDuration].
  /// [maxZoom] bounds [zoom]. [initialStart] / [initialEnd] pre-select a range.
  TrimController({
    Duration totalDuration = Duration.zero,
    this.minDuration = const Duration(seconds: 1),
    this.maxDuration,
    this.maxZoom = 32,
    Duration? initialStart,
    Duration? initialEnd,
    this.haptics = const TrimHaptics(),
  })  : assert(maxZoom >= 1),
        assert(maxDuration == null || maxDuration >= minDuration),
        _total = totalDuration.isNegative ? Duration.zero : totalDuration {
    _start = Duration.zero;
    _end = _total;
    _applyMax(fromStart: true);
    _playhead = _start;
    if (initialStart != null || initialEnd != null) {
      final s = initialStart ?? Duration.zero;
      final e = initialEnd ?? _total;
      setSelection(s, e);
    }
    _playhead = _start;
  }

  /// Smallest allowed selection (shrinks to the total when the video is shorter).
  final Duration minDuration;

  /// Largest allowed selection, or null for no limit.
  final Duration? maxDuration;

  /// Largest zoom factor.
  final double maxZoom;

  /// Feedback hooks.
  TrimHaptics haptics;

  /// Minimum gap between preview seeks sent to the player while a handle is
  /// dragged (keeps slow players responsive).
  Duration previewInterval = const Duration(milliseconds: 30);

  Duration _total;
  late Duration _start;
  late Duration _end;
  late Duration _playhead;
  Duration? _cover;
  double _zoom = 1;
  Duration _viewStart = Duration.zero;
  TrimHandle? _activeHandle;
  TrimPlaybackAdapter? _adapter;
  int _lastTickSecond = -1;
  final Stopwatch _previewClock = Stopwatch()..start();
  int _lastPreviewMs = -1000;

  /// Total video length.
  Duration get totalDuration => _total;

  /// Start of the kept range.
  Duration get start => _start;

  /// End of the kept range.
  Duration get end => _end;

  /// Length of the kept range.
  Duration get selectedDuration => _end - _start;

  /// Playhead position, always inside [start]..[end].
  Duration get playhead => _playhead;

  /// Chosen cover frame, or null.
  Duration? get cover => _cover;

  /// The handle currently being dragged, if any.
  TrimHandle? get activeHandle => _activeHandle;

  /// Whether playback loops inside the selection (otherwise it pauses at the end).
  bool loop = true;

  /// Current zoom factor (1 = whole video visible).
  double get zoom => _zoom;

  /// Time at the left edge of the visible window.
  Duration get viewStart => _viewStart;

  /// Length of the visible window.
  Duration get viewSpan => _total == Duration.zero
      ? Duration.zero
      : Duration(microseconds: (_total.inMicroseconds / _zoom).round());

  /// Time at the right edge of the visible window.
  Duration get viewEnd => _viewStart + viewSpan;

  /// The plain result to pass to your export engine.
  TrimSelection get selection =>
      TrimSelection(start: _start, end: _end, cover: _cover);

  /// The effective minimum (never longer than the video).
  Duration get effectiveMin => minDuration > _total ? _total : minDuration;

  Duration _effMax() {
    final m = maxDuration;
    return (m == null || m > _total) ? _total : m;
  }

  Duration _clampTime(Duration d) =>
      d < Duration.zero ? Duration.zero : (d > _total ? _total : d);

  void _applyMax({required bool fromStart}) {
    final max = _effMax();
    if (_end - _start > max) {
      if (fromStart) {
        _end = _start + max;
      } else {
        _start = _end - max;
      }
    }
  }

  // ---------------------------------------------------------------- duration

  /// Sets the video length, e.g. once the player has initialised.
  ///
  /// The first call on an empty controller selects the whole video (up to
  /// [maxDuration]). Later calls keep the selection and clamp it.
  void setTotalDuration(Duration d) {
    final next = d.isNegative ? Duration.zero : d;
    if (next == _total) return;
    final wasEmpty = _total == Duration.zero;
    _total = next;
    if (wasEmpty) {
      _start = Duration.zero;
      _end = _total;
      _applyMax(fromStart: true);
    } else {
      _end = _clampTime(_end);
      _start = _clampTime(_start);
      if (_end - _start < effectiveMin) {
        _start = _clampTime(_end - effectiveMin);
        if (_end - _start < effectiveMin) _end = _start + effectiveMin;
      }
      _applyMax(fromStart: true);
    }
    if (_cover != null) _cover = _clampCover(_cover!);
    _playhead = _clampPlayhead(_playhead);
    _clampView();
    notifyListeners();
  }

  // --------------------------------------------------------------- selection

  /// Moves the start handle to [t] within the allowed range. Returns the
  /// value actually applied.
  Duration setStart(Duration t) {
    final lo = _end - _effMax();
    final hi = _end - effectiveMin;
    var v = _clampTime(t);
    final limited = v < lo || v > hi;
    v = v < lo ? lo : (v > hi ? hi : v);
    if (v < Duration.zero) v = Duration.zero;
    if (limited && v != t && _activeHandle != null) haptics.onLimit?.call();
    _commitHandle(TrimHandle.start, v);
    return _start;
  }

  /// Moves the end handle to [t] within the allowed range. Returns the value
  /// actually applied.
  Duration setEnd(Duration t) {
    final lo = _start + effectiveMin;
    final hi = _start + _effMax();
    var v = _clampTime(t);
    final limited = v < lo || v > hi;
    v = v < lo ? lo : (v > hi ? hi : v);
    if (v > _total) v = _total;
    if (limited && v != t && _activeHandle != null) haptics.onLimit?.call();
    _commitHandle(TrimHandle.end, v);
    return _end;
  }

  void _commitHandle(TrimHandle h, Duration v) {
    final changed = h == TrimHandle.start ? v != _start : v != _end;
    if (!changed) return;
    if (h == TrimHandle.start) {
      _start = v;
    } else {
      _end = v;
    }
    final sec = v.inSeconds;
    if (_activeHandle != null && sec != _lastTickSecond) {
      _lastTickSecond = sec;
      haptics.onTick?.call();
    }
    if (_cover != null) _cover = _clampCover(_cover!);
    _playhead = _clampPlayhead(_playhead);
    // Live preview: show the frame under the dragged handle (issue #110).
    if (_activeHandle == h) _previewSeek(v);
    _syncAdapterIntoSelection();
    notifyListeners();
  }

  /// Sets both handles at once, respecting min/max.
  void setSelection(Duration start, Duration end) {
    var s = _clampTime(start);
    var e = _clampTime(end);
    if (e < s) {
      final t = s;
      s = e;
      e = t;
    }
    if (e - s < effectiveMin) e = s + effectiveMin;
    if (e > _total) {
      e = _total;
      s = e - effectiveMin;
    }
    if (e - s > _effMax()) e = s + _effMax();
    if (s == _start && e == _end) return;
    _start = s;
    _end = e;
    if (_cover != null) _cover = _clampCover(_cover!);
    _playhead = _clampPlayhead(_playhead);
    _syncAdapterIntoSelection();
    notifyListeners();
  }

  /// Slides the whole selection by [delta], keeping its length.
  void moveSelectionBy(Duration delta) {
    final len = _end - _start;
    var s = _start + delta;
    if (s < Duration.zero) s = Duration.zero;
    if (s + len > _total) s = _total - len;
    setSelection(s, s + len);
  }

  /// Marks [handle] as being dragged (drives preview seeking, ticks, styling).
  void beginHandleDrag(TrimHandle handle) {
    _activeHandle = handle;
    _lastTickSecond = (handle == TrimHandle.start ? _start : _end).inSeconds;
    haptics.onGrab?.call(handle);
    _adapter?.pause();
    notifyListeners();
  }

  /// Ends a handle drag.
  void endHandleDrag() {
    final h = _activeHandle;
    if (h == null) return;
    _activeHandle = null;
    haptics.onRelease?.call(h);
    _playhead = _start;
    _adapter?.seekTo(_start);
    notifyListeners();
  }

  // ----------------------------------------------------------------- playhead

  Duration _clampPlayhead(Duration d) =>
      d < _start ? _start : (d > _end ? _end : d);

  /// Moves the playhead to [t] (clamped into the selection) and seeks the
  /// player.
  void seek(Duration t) {
    final v = _clampPlayhead(t);
    _playhead = v;
    _adapter?.seekTo(v);
    notifyListeners();
  }

  // -------------------------------------------------------------------- cover

  Duration _clampCover(Duration d) => _clampPlayheadLike(d);
  Duration _clampPlayheadLike(Duration d) =>
      d < _start ? _start : (d > _end ? _end : d);

  /// Picks the cover frame at [t], clamped into the selection. Pass null to
  /// clear it.
  void setCover(Duration? t) {
    final v = t == null ? null : _clampCover(t);
    if (v == _cover) return;
    _cover = v;
    haptics.onCoverChanged?.call();
    notifyListeners();
  }

  // --------------------------------------------------------------------- zoom

  void _clampView() {
    if (_total == Duration.zero) {
      _viewStart = Duration.zero;
      return;
    }
    final maxStart = _total - viewSpan;
    if (_viewStart > maxStart) _viewStart = maxStart;
    if (_viewStart < Duration.zero) _viewStart = Duration.zero;
  }

  /// Sets the zoom to [value] (clamped to 1..[maxZoom]), keeping the time at
  /// [focalFraction] (0..1 across the visible window) under the same screen
  /// position.
  void setZoom(double value, {double focalFraction = 0.5}) {
    if (value.isNaN || value.isInfinite) return;
    final z = value.clamp(1.0, maxZoom);
    if (z == _zoom || _total == Duration.zero) return;
    final f = focalFraction.isNaN ? 0.5 : focalFraction.clamp(0.0, 1.0);
    final focalTime = _viewStart.inMicroseconds + viewSpan.inMicroseconds * f;
    _zoom = z;
    final newSpan = viewSpan.inMicroseconds;
    _viewStart = Duration(microseconds: (focalTime - newSpan * f).round());
    _clampView();
    notifyListeners();
  }

  /// Multiplies the zoom by [factor] around [focalFraction].
  void zoomBy(double factor, {double focalFraction = 0.5}) =>
      setZoom(_zoom * factor, focalFraction: focalFraction);

  /// Scrolls the visible window by [delta].
  void scrollBy(Duration delta) {
    _viewStart += delta;
    _clampView();
    notifyListeners();
  }

  /// Zooms to fit the current selection with some margin.
  void zoomToSelection({double margin = 0.1}) {
    if (_total == Duration.zero) return;
    final len = selectedDuration.inMicroseconds * (1 + 2 * margin);
    _zoom = 1;
    setZoom(_total.inMicroseconds / math.max(len, 1));
    _viewStart = Duration(
        microseconds:
            (_start.inMicroseconds - selectedDuration.inMicroseconds * margin)
                .round());
    _clampView();
    notifyListeners();
  }

  // ------------------------------------------------------- time <-> fraction

  /// Where [t] sits in the visible window (0..1 inside it; outside = beyond).
  double fractionOf(Duration t) {
    final span = viewSpan.inMicroseconds;
    if (span <= 0) return 0;
    return (t.inMicroseconds - _viewStart.inMicroseconds) / span;
  }

  /// The time at [fraction] of the visible window.
  Duration timeAt(double fraction) {
    if (fraction.isNaN) return _viewStart;
    return _clampTime(Duration(
        microseconds:
            (_viewStart.inMicroseconds + viewSpan.inMicroseconds * fraction)
                .round()));
  }

  // ----------------------------------------------------------------- playback

  /// Connects a player. The controller then keeps playback inside the
  /// selection: starting before the in-point jumps to it (issue #202), reaching
  /// the out-point loops or pauses, and the playhead follows the player.
  void attachPlayback(TrimPlaybackAdapter adapter) {
    detachPlayback();
    _adapter = adapter;
    adapter.position.addListener(_onPlayerPosition);
    adapter.isPlaying.addListener(_onPlayerState);
    _syncAdapterIntoSelection();
  }

  /// Disconnects the player.
  void detachPlayback() {
    _adapter?.position.removeListener(_onPlayerPosition);
    _adapter?.isPlaying.removeListener(_onPlayerState);
    _adapter = null;
  }

  /// Whether the attached player is playing.
  bool get isPlaying => _adapter?.isPlaying.value ?? false;

  /// Plays from the playhead (restarting at the in-point if at the end).
  Future<void> play() async {
    final a = _adapter;
    if (a == null) return;
    if (_playhead >= _end) await a.seekTo(_start);
    await a.play();
  }

  /// Pauses the attached player.
  Future<void> pause() async => _adapter?.pause();

  /// Toggles play / pause.
  Future<void> togglePlay() => isPlaying ? pause() : play();

  static const Duration _tolerance = Duration(milliseconds: 60);

  void _onPlayerPosition() {
    final a = _adapter;
    if (a == null || _activeHandle != null) return;
    final p = a.position.value;
    if (a.isPlaying.value) {
      if (p >= _end) {
        if (loop) {
          a.seekTo(_start);
          _playhead = _start;
        } else {
          a.pause();
          _playhead = _end;
        }
        notifyListeners();
        return;
      }
      if (p < _start - _tolerance) {
        a.seekTo(_start);
        _playhead = _start;
        notifyListeners();
        return;
      }
    }
    final next = _clampPlayhead(p);
    if (next != _playhead) {
      _playhead = next;
      notifyListeners();
    }
  }

  void _onPlayerState() => notifyListeners();

  void _syncAdapterIntoSelection() {
    final a = _adapter;
    if (a == null) return;
    final p = a.position.value;
    if (p < _start || p > _end) a.seekTo(_start);
  }

  void _previewSeek(Duration t) {
    final a = _adapter;
    if (a == null) return;
    final now = _previewClock.elapsedMilliseconds;
    if (now - _lastPreviewMs < previewInterval.inMilliseconds) return;
    _lastPreviewMs = now;
    a.seekTo(t);
  }

  @override
  void dispose() {
    detachPlayback();
    super.dispose();
  }
}
