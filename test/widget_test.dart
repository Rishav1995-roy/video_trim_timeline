import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_trim_timeline/video_trim_timeline.dart';

import 'package:video_trim_timeline/src/thumbnail_strip.dart';
import 'support.dart';

Duration s(num v) => Duration(milliseconds: (v * 1000).round());

Widget host(Widget child,
        {TextDirection dir = TextDirection.ltr, double w = 400}) =>
    MaterialApp(
      home: Directionality(
        textDirection: dir,
        child: Scaffold(
          body: Center(child: SizedBox(width: w, child: child)),
        ),
      ),
    );

void act(WidgetTester t, String label, SemanticsAction a) {
  final node = t.getSemantics(find.bySemanticsLabel(label));
  node.owner!.performAction(node.id, a);
}

void main() {
  testWidgets('drags both handles and scrubs the playhead', (tester) async {
    final c = TrimController(totalDuration: s(100), minDuration: s(1));
    await tester.pumpWidget(host(TrimTimeline(controller: c)));
    final box = tester.getRect(find.byType(TrimTimeline));
    // strip: pad 35.2 each side -> width ~329.6 for 100 s
    final pxPerSec = (box.width - 35.2 * 2) / 100;

    // end handle sits at the strip right edge; grab inside its hit area
    final endX = box.right - 35.2 + 10;
    final y = box.center.dy;
    await tester.dragFrom(Offset(endX, y), Offset(-pxPerSec * 40, 0));
    expect(c.end.inSeconds, inInclusiveRange(58, 62));

    final startX = box.left + 35.2 - 10;
    await tester.dragFrom(Offset(startX, y), Offset(pxPerSec * 20, 0));
    expect(c.start.inSeconds, inInclusiveRange(18, 22));

    await tester.tapAt(Offset(box.left + 35.2 + pxPerSec * 40, y));
    expect(c.playhead.inSeconds, inInclusiveRange(39, 41));
    // scrub outside selection clamps
    await tester.tapAt(Offset(box.left + 35.2 + pxPerSec * 90, y));
    expect(c.playhead, c.end);
  });

  testWidgets(
      'core problem 3: end handle is grabbable at the minimum selection (video_editor #207)',
      (tester) async {
    final c = TrimController(totalDuration: s(120), minDuration: s(1));
    c.setSelection(s(50), s(51)); // ~3 px wide selection at this width
    await tester.pumpWidget(host(TrimTimeline(controller: c)));
    final box = tester.getRect(find.byType(TrimTimeline));
    final pxPerSec = (box.width - 35.2 * 2) / 120;
    final endEdge = box.left + 35.2 + pxPerSec * 51;
    final y = box.center.dy;

    // Touch 12 px right of the end edge: inside the outward hit area, outside
    // the 14 px visual handle's centre.
    await tester.dragFrom(Offset(endEdge + 12, y), Offset(pxPerSec * 30, 0));
    expect(c.end.inSeconds, greaterThanOrEqualTo(78), reason: 'end moved');
    expect(c.start, s(50), reason: 'start untouched');

    // And the start handle is still independently grabbable on its outer side.
    final startEdge = box.left + 35.2 + pxPerSec * 50;
    await tester.dragFrom(Offset(startEdge - 12, y), Offset(-pxPerSec * 20, 0));
    expect(c.start.inSeconds, lessThanOrEqualTo(32));
    expect(c.end.inSeconds, greaterThanOrEqualTo(78));
  });

  testWidgets('hit target is at least 44 logical px wide', (tester) async {
    final c = TrimController(totalDuration: s(100));
    await tester.pumpWidget(host(TrimTimeline(controller: c)));
    final slider = find.bySemanticsLabel('Trim start');
    expect(slider, findsOneWidget);
    expect(tester.getSize(slider).width, greaterThanOrEqualTo(44));
  });

  testWidgets(
      'core problem 2: null / throwing thumbnails render placeholders, no exception',
      (tester) async {
    for (final mode in ['null', 'throw']) {
      final c = TrimController(totalDuration: s(60));
      final cache = ThumbnailCache(FakeProvider(mode: mode));
      await tester
          .pumpWidget(host(TrimTimeline(controller: c, thumbnails: cache)));
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(tester.takeException(), isNull);
      expect(find.byType(ThumbTile), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('zero-duration video renders and ignores gestures',
      (tester) async {
    final c = TrimController();
    await tester.pumpWidget(host(TrimTimeline(controller: c)));
    await tester.dragFrom(const Offset(200, 300), const Offset(50, 0));
    expect(tester.takeException(), isNull);
    c.setTotalDuration(s(10));
    await tester.pump();
    expect(find.bySemanticsLabel('Trim end'), findsOneWidget);
  });

  testWidgets('real thumbnails are displayed', (tester) async {
    final c = TrimController(totalDuration: s(60));
    final p = FakeProvider();
    await tester.pumpWidget(
        host(TrimTimeline(controller: c, thumbnails: ThumbnailCache(p))));
    await tester.pump();
    await tester.pump();
    expect(p.calls, greaterThan(2));
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('semantic actions on handles and playhead', (tester) async {
    final h = tester.ensureSemantics();
    final c = TrimController(totalDuration: s(60), minDuration: s(1));
    c.setSelection(s(10), s(30));
    await tester.pumpWidget(host(TrimTimeline(controller: c)));

    final start = tester.getSemantics(find.bySemanticsLabel('Trim start'));
    expect(start.value, '0:10.0');
    act(tester, 'Trim start', SemanticsAction.increase);
    await tester.pump();
    expect(c.start, s(11));
    act(tester, 'Trim end', SemanticsAction.decrease);
    await tester.pump();
    expect(c.end, s(29));
    act(tester, 'Playhead', SemanticsAction.increase);
    await tester.pump();
    expect(c.playhead, s(12)); // clamped start was 11 -> +1
    h.dispose();
  });

  testWidgets('RTL mirrors: dragging right moves the start handle earlier',
      (tester) async {
    final c = TrimController(totalDuration: s(100));
    c.setSelection(s(40), s(80));
    await tester
        .pumpWidget(host(TrimTimeline(controller: c), dir: TextDirection.rtl));
    final box = tester.getRect(find.byType(TrimTimeline));
    final pxPerSec = (box.width - 35.2 * 2) / 100;
    // start (t=40) is at x = right - pad - 40*pxPerSec ; its outward side is right of it
    final startX = box.right - 35.2 - pxPerSec * 40 + 10;
    await tester.dragFrom(
        Offset(startX, box.center.dy), Offset(pxPerSec * 10, 0));
    expect(c.start.inSeconds, inInclusiveRange(29, 31));
  });

  testWidgets('two-finger pinch zooms in', (tester) async {
    final c = TrimController(totalDuration: s(100));
    await tester.pumpWidget(host(TrimTimeline(controller: c)));
    final center = tester.getCenter(find.byType(TrimTimeline));
    final g1 = await tester.startGesture(center + const Offset(-20, 0));
    final g2 = await tester.startGesture(center + const Offset(20, 0));
    await g1.moveBy(const Offset(-60, 0));
    await g2.moveBy(const Offset(60, 0));
    await g1.up();
    await g2.up();
    expect(c.zoom, greaterThan(2));
  });

  testWidgets('custom handle builder and haptics via widget drag',
      (tester) async {
    var grabbed = 0;
    final c = TrimController(
        totalDuration: s(100), haptics: TrimHaptics(onGrab: (_) => grabbed++));
    await tester.pumpWidget(host(TrimTimeline(
      controller: c,
      style: const TrimTimelineStyle().copyWith(
        handleBuilder: (ctx, side, active, size) =>
            Container(key: ValueKey('h-$side'), color: Colors.red),
      ),
    )));
    expect(
        find.byKey(const ValueKey('h-TrimHandleSide.start')), findsOneWidget);
    final box = tester.getRect(find.byType(TrimTimeline));
    await tester.dragFrom(
        Offset(box.right - 25, box.center.dy), const Offset(-30, 0));
    expect(grabbed, 1);
  });

  testWidgets('CoverPicker picks within the trimmed range', (tester) async {
    final c = TrimController(totalDuration: s(100));
    c.setSelection(s(20), s(40));
    final cache = ThumbnailCache(FakeProvider());
    await tester
        .pumpWidget(host(CoverPicker(controller: c, thumbnails: cache)));
    final strip = find.byType(GestureDetector).last;
    final r = tester.getRect(strip);
    await tester.tapAt(Offset(r.left + r.width * 0.5, r.center.dy));
    expect(c.cover!.inSeconds, inInclusiveRange(29, 31));
    await tester.tapAt(Offset(r.right - 1, r.center.dy));
    expect(c.cover!.inSeconds, inInclusiveRange(39, 40));
    expect(tester.takeException(), isNull);
    final h = tester.ensureSemantics();
    await tester.pump();
    act(tester, 'Cover frame', SemanticsAction.decrease);
    await tester.pump();
    expect(c.cover!.inMilliseconds, lessThan(39500));
    h.dispose();
  });

  test('engine independence: package depends only on flutter', () {
    // Proven by pubspec: no engine, no thumbnail plugin, no player.
    final deps = RegExp(r'dependencies:\n  flutter:\n    sdk: flutter\n\ndev')
        .hasMatch(File('pubspec.yaml').readAsStringSync());
    expect(deps, isTrue);
  });
}
