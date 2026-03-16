import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat_scroll/ai_chat_scroll.dart';

/// Helper: build AiChatScrollView inside a MaterialApp with a fixed
/// 400x600 viewport. [itemCount] items, each 100px tall with a text child.
Widget buildTestWidget({
  required AiChatScrollController controller,
  required int itemCount,
}) {
  return MaterialApp(
    home: AiChatScrollView(
      controller: controller,
      itemCount: itemCount,
      itemBuilder: (_, index) => SizedBox(height: 100, child: Text('Msg $index')),
    ),
  );
}

/// Pumps enough frames to let all postFrameCallbacks in the anchor pipeline
/// fire. The anchor uses a 3-phase postFrameCallback chain, so we pump
/// several frames.
Future<void> pumpAnchor(WidgetTester tester) async {
  // Phase 0: setState rebuild (so GlobalKey is applied)
  await tester.pump();
  // Phase 1: first postFrameCallback — scrolls to bottom
  await tester.pump();
  // Phase 2: second postFrameCallback — sets filler
  await tester.pump();
  // Phase 3: third postFrameCallback — jumps to target
  await tester.pump();
  // Settle any remaining frames
  await tester.pumpAndSettle();
}

/// Reads the current FillerSliver SizedBox height from the widget tree.
/// Finds the SizedBox inside the ValueListenableBuilder (filler) by
/// locating the one that has no Text child.
double readFillerHeight(WidgetTester tester) {
  final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox)).toList();
  for (final box in sizedBoxes) {
    final element = tester.element(find.byWidget(box));
    int textCount = 0;
    void countText(Element el) {
      if (el.widget is Text) textCount++;
      el.visitChildren(countText);
    }

    element.visitChildren((child) => countText(child));
    if (textCount == 0) {
      return box.height ?? 0.0;
    }
  }
  return 0.0;
}

void main() {
  group('ANCH-02: Anchored message stays at viewport top as items are added', () {
    testWidgets('last item Y unchanged when new item added during streaming', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = AiChatScrollController();
      addTearDown(controller.dispose);

      // Start with 10 items
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 10,
      ));
      await tester.pumpAndSettle();

      // Anchor on last item (Msg 9)
      controller.onUserMessageSent();
      await pumpAnchor(tester);

      final anchoredY = tester.getTopLeft(find.text('Msg 9')).dy;
      expect(anchoredY, closeTo(0.0, 1.0), reason: 'Pre-condition: anchor positioned at Y=0');

      // Add an item (simulating AI response growing / streaming)
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 11,
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      // Msg 9 should still be at Y=0 (anchor must hold)
      final anchoredYAfter = tester.getTopLeft(find.text('Msg 9')).dy;
      expect(anchoredYAfter, closeTo(0.0, 1.0),
          reason: 'ANCH-02: Anchored message must stay at viewport top after adding items during streaming');
    });
  });

  group('ANCH-03: Filler height decreases as content is added during streaming', () {
    testWidgets('FillerSliver SizedBox height decreases after adding items', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = AiChatScrollController();
      addTearDown(controller.dispose);

      // 10 items (1000px total), viewport 600px
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 10,
      ));
      await tester.pumpAndSettle();

      // Anchor: the last item (100px) at top, filler = 600 - 100 = 500px
      controller.onUserMessageSent();
      await pumpAnchor(tester);

      final fillerBefore = readFillerHeight(tester);
      expect(fillerBefore, greaterThan(0.0), reason: 'Pre-condition: filler must be > 0 after anchoring one message');

      // Add another item (simulating AI response)
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 11,
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      final fillerAfter = readFillerHeight(tester);
      expect(fillerAfter, lessThan(fillerBefore),
          reason: 'ANCH-03: Filler height must decrease as streaming content is added below the anchor');
    });
  });

  group('ANCH-04: Scroll position (pixels) does not change during streaming', () {
    testWidgets('pixels unchanged when items added after anchor', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = AiChatScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 10,
      ));
      await tester.pumpAndSettle();

      final scrollController = tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!;

      // Anchor
      controller.onUserMessageSent();
      await pumpAnchor(tester);

      final pixelsBefore = scrollController.position.pixels;
      expect(pixelsBefore, greaterThan(0.0), reason: 'Pre-condition: scroll position should be > 0 after anchor');

      // Add items (simulating streaming)
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 11,
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      final pixelsAfter = scrollController.position.pixels;
      expect(pixelsAfter, closeTo(pixelsBefore, 1.0),
          reason: 'ANCH-04: Scroll pixels must not change during streaming — only filler shrinks');
    });
  });

  group('ANCH-05: Filler clamps to 0 when AI response exceeds viewport', () {
    testWidgets('filler reaches 0 when enough items added to exceed viewport', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = AiChatScrollController();
      addTearDown(controller.dispose);

      // Start with 1 item: user sends a message (100px), filler = 500px
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 1,
      ));
      await tester.pumpAndSettle();

      // Anchor on the single message
      controller.onUserMessageSent();
      await pumpAnchor(tester);

      final fillerInitial = readFillerHeight(tester);
      expect(fillerInitial, closeTo(500.0, 1.0),
          reason: 'Pre-condition: filler after anchoring 100px message in 600px viewport = 500px');

      // Add 6 more items (6 * 100px = 600px > remaining 500px filler)
      // This should bring filler down to 0
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 7,
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      final fillerFinal = readFillerHeight(tester);
      expect(fillerFinal, closeTo(0.0, 1.0),
          reason: 'ANCH-05: Filler must clamp to 0 when AI response content exceeds viewport height');
    });
  });
}
