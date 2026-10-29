import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_trim_timeline/video_trim_timeline.dart';

import 'support.dart';

Duration s(num v) => Duration(milliseconds: (v * 1000).round());

void main() {
  group('TrimSelection', () {
    test('ffmpeg arguments, json round trip and formatting', () {
      final sel = TrimSelection(start: s(1.5), end: s(4), cover: s(2));
      expect(sel.duration, s(2.5));
      expect(sel.toFfmpegArguments(input: 'a.mp4', output: 'b.mp4'),
          ['-y', '-ss', '1.500', '-i', 'a.mp4', '-t', '2.500', 'b.mp4']);
      expect(sel.toFfmpegArguments(input: 'a', output: 'b', copyStreams: true),
          containsAllInOrder(['-c', 'copy']));
      expect(sel.toCoverFfmpegArguments(input: 'a', output: 'c.jpg'), [
        '-y',
        '-ss',
        '2.000',
        '-i',
        'a',
        '-frames:v',
        '1',
        '-q:v',
        '2',
        'c.jpg'
      ]);
      expect(TrimSelection.fromJson(sel.toJson()), sel);
      expect(formatTrimDuration(s(65.4), tenths: true), '1:05.4');
      expect(formatTrimDuration(s(3725)), '1:02:05');
      expect(formatTrimDuration(const Duration(seconds: -3)), '0:00');
    });
  });

  group('TrimController constraints', () {
    test('min and max duration are enforced on both handles', () {
      final c = TrimController(
          totalDuration: s(60), minDuration: s(2), maxDuration: s(10));
      expect(c.selectedDuration, s(10)); // starts at max
      c.setEnd(s(1));
      expect(c.end, s(2));
      c.setEnd(s(50));
      expect(c.end, s(10));
      c.setStart(s(9.5));
      expect(c.start, s(8));
      c.setStart(s(-5));
      expect(c.start, Duration.zero);
      c.setSelection(s(55), s(60));
      expect(c.selection.start, s(55));
      c.moveSelectionBy(s(30));
      expect(c.end, s(60));
    });

    test('initial range is applied and the playhead starts at its in-point',
        () {
      final c = TrimController(
          totalDuration: s(60), initialStart: s(6), initialEnd: s(26));
      expect(c.selection, TrimSelection(start: s(6), end: s(26)));
      expect(c.playhead, s(6));
    });

    test('handles can never cross', () {
      final c = TrimController(totalDuration: s(20), minDuration: s(1));
      c.setStart(s(30));
      expect(c.start, s(19));
      expect(c.end, s(20));
      c.setEnd(s(0));
      expect(c.end - c.start, s(1));
    });
  });

  group(
      'core problem 2: no crashes on empty/odd data (video_editor #160 #165 #181)',
      () {
    test('zero duration: no NaN, no exceptions, everything stays zero', () {
      final c = TrimController();
      expect(c.fractionOf(s(3)), 0);
      expect(c.timeAt(0.5), Duration.zero);
      expect(c.timeAt(double.nan), Duration.zero);
      c.setStart(s(3));
      c.setEnd(s(3));
      c.seek(s(2));
      c.zoomBy(4);
      c.setZoom(double.nan);
      c.setCover(s(1));
      expect(c.selection.duration, Duration.zero);
      expect(c.zoom, 1);
    });

    test('duration arriving late selects the whole video; shrink re-clamps',
        () {
      final c = TrimController(maxDuration: s(30));
      c.setTotalDuration(s(100));
      expect(c.start, Duration.zero);
      expect(c.end, s(30));
      c.setSelection(s(60), s(90));
      c.setCover(s(70));
      c.setTotalDuration(s(65));
      expect(c.end, s(65));
      expect(c.start, lessThan(c.end));
      expect(c.cover! <= c.end && c.cover! >= c.start, isTrue);
    });

    test('video shorter than min duration is fully selected', () {
      final c = TrimController(totalDuration: s(0.4), minDuration: s(1));
      expect(c.selection, TrimSelection(start: Duration.zero, end: s(0.4)));
      c.setStart(s(0.3));
      expect(c.start, Duration.zero);
    });

    test('cover follows the selection', () {
      final c = TrimController(totalDuration: s(30));
      c.setCover(s(25));
      c.setEnd(s(10));
      expect(c.cover, s(10));
      c.setCover(null);
      expect(c.cover, isNull);
    });
  });

  group('zoom', () {
    test('keeps the focal time fixed and stays in bounds', () {
      final c = TrimController(totalDuration: s(100));
      c.setZoom(4, focalFraction: 0.5);
      expect(c.viewSpan, s(25));
      expect(c.viewStart, s(37.5));
      c.scrollBy(s(1000));
      expect(c.viewEnd, s(100));
      c.scrollBy(s(-1000));
      expect(c.viewStart, Duration.zero);
      c.setZoom(1000);
      expect(c.zoom, c.maxZoom);
      c.setZoom(0.1);
      expect(c.zoom, 1);
      expect(c.fractionOf(s(50)), 0.5);
    });

    test('zoomToSelection shows the selection', () {
      final c = TrimController(totalDuration: s(100));
      c.setSelection(s(40), s(50));
      c.zoomToSelection();
      expect(c.viewStart <= s(40) && c.viewEnd >= s(50), isTrue);
      expect(c.zoom, greaterThan(5));
    });
  });

  group(
      'core problem 4: playback stays inside the trim (video_editor #202, #110)',
      () {
    test('starting before the in-point jumps to it; end loops or pauses',
        () async {
      final a = SimulatedPlaybackAdapter();
      final c = TrimController(totalDuration: s(60));
      c.setSelection(s(20), s(30));
      c.attachPlayback(a);
      expect(a.seeks.last, s(20)); // adapter at 0 is outside the trim

      await c.play();
      expect(a.isPlaying.value, isTrue);
      a.advance(s(9.99));
      expect(c.playhead, s(30) > a.position.value ? a.position.value : s(30));
      a.position.value = s(30);
      expect(a.position.value, s(20)); // looped
      expect(c.playhead, s(20));

      c.loop = false;
      a.position.value = s(30);
      expect(a.isPlaying.value, isFalse);
      expect(c.playhead, s(30));
      await c.play(); // restarts from in-point
      expect(a.position.value, s(20));
      c.dispose();
    });

    test('player position outside range while playing is pulled back',
        () async {
      final a = SimulatedPlaybackAdapter();
      final c = TrimController(totalDuration: s(60))
        ..setSelection(s(10), s(20));
      c.attachPlayback(a);
      await a.play();
      a.position.value = s(3);
      expect(a.position.value, s(10));
    });

    test('dragging a handle previews the frame under it and ends at in-point',
        () {
      final a = SimulatedPlaybackAdapter();
      final c = TrimController(totalDuration: s(60))
        ..previewInterval = Duration.zero;
      c.attachPlayback(a);
      c.beginHandleDrag(TrimHandle.start);
      c.setStart(s(12));
      expect(a.seeks.last, s(12));
      c.setStart(s(14));
      expect(a.seeks.last, s(14));
      c.endHandleDrag();
      expect(a.position.value, s(14));
      expect(c.playhead, s(14));
    });

    test('moving the in-point past the player position re-seeks', () {
      final a = SimulatedPlaybackAdapter();
      final c = TrimController(totalDuration: s(60));
      c.attachPlayback(a);
      c.setStart(s(30));
      expect(a.position.value, s(30));
    });
  });

  group('haptics hooks', () {
    test('grab, tick, limit, release fire', () {
      final log = <String>[];
      final c = TrimController(
        totalDuration: s(30),
        minDuration: s(2),
        haptics: TrimHaptics(
          onGrab: (h) => log.add('grab'),
          onTick: () => log.add('tick'),
          onLimit: () => log.add('limit'),
          onRelease: (h) => log.add('release'),
          onCoverChanged: () => log.add('cover'),
        ),
      );
      c.beginHandleDrag(TrimHandle.end);
      c.setEnd(s(20.5));
      c.setEnd(s(0));
      c.endHandleDrag();
      c.setCover(s(3));
      expect(log, ['grab', 'tick', 'limit', 'tick', 'release', 'cover']);
    });
  });

  group('core problem 2b: ThumbnailCache never throws (video_editor #209)', () {
    test('null and throwing providers resolve to null and are remembered',
        () async {
      for (final mode in ['null', 'throw']) {
        final p = FakeProvider(mode: mode);
        final cache = ThumbnailCache(p);
        expect(await cache.load(s(1), const Size(10, 10)), isNull);
        expect(cache.isResolved(s(1)), isTrue);
        await cache.load(s(1.02), const Size(10, 10)); // same quantum
        expect(p.calls, 1);
      }
    });

    test('de-duplicates concurrent requests and evicts LRU', () async {
      final p = FakeProvider();
      final cache = ThumbnailCache(p, capacity: 2);
      await Future.wait([
        cache.load(s(1), const Size(1, 1)),
        cache.load(s(1), const Size(1, 1)),
      ]);
      expect(p.calls, 1);
      await cache.load(s(2), const Size(1, 1));
      cache.peek(s(1)); // refresh 1
      await cache.load(s(3), const Size(1, 1));
      expect(cache.isResolved(s(1)), isTrue);
      expect(cache.isResolved(s(2)), isFalse);
      expect(cache.length, 2);
    });
  });
}
