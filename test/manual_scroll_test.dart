import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat_scroll/ai_chat_scroll.dart';

/// Helper: build AiChatScrollView inside a MaterialApp with a fixed
/// 400x600 viewport. [itemCount] items, each 100px tall.
Widget buildTestWidget({
  required AiChatScrollController controller,
  required int itemCount,
}) {
  return MaterialApp(
    home: AiChatScrollView(
      controller: controller,
      itemCount: itemCount,
      itemBuilder: (_, index) =>
          SizedBox(height: 100, child: Text('Msg $index')),
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

void main() {
  group('API-04: User drag cancels anchor', () {
    testWidgets('drag during streaming stops filler updates', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = AiChatScrollController();
      addTearDown(controller.dispose);

      // Set up 10 items (100px each = 1000px total, viewport 600px)
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 10,
      ));
      await tester.pumpAndSettle();

      // Trigger anchor: last item (Msg 9) snaps to viewport top
      controller.onUserMessageSent();
      await pumpAnchor(tester);

      // Pre-condition: anchor is active, Msg 9 is at Y=0
      final anchoredY = tester.getTopLeft(find.text('Msg 9')).dy;
      expect(anchoredY, closeTo(0.0, 1.0),
          reason: 'Pre-condition: anchor active, Msg 9 at Y=0');

      // Get scroll controller to read position
      final scrollController = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      final pixelsBeforeDrag = scrollController.position.pixels;
      expect(pixelsBeforeDrag, greaterThan(0.0),
          reason: 'Pre-condition: scroll position > 0 after anchor');

      // Simulate user drag gesture (scroll up by 100px)
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -100));
      await tester.pumpAndSettle();

      // Record scroll position after drag
      final pixelsAfterDrag = scrollController.position.pixels;

      // Add item 11 (simulates AI response continuing to stream)
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 11,
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      // Scroll position must NOT reset to the anchor target.
      // If drag cancellation worked, position stays where user dragged it
      // (or close to it). It must not jump back to pixelsBeforeDrag.
      final pixelsAfterStreamItem = scrollController.position.pixels;
      expect(
        (pixelsAfterStreamItem - pixelsAfterDrag).abs(),
        lessThan(50.0),
        reason:
            'API-04: After drag cancellation, adding streaming items must NOT '
            're-hijack scroll position back to anchor target',
      );
    });

    testWidgets('onUserMessageSent after drag re-enables anchor', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = AiChatScrollController();
      addTearDown(controller.dispose);

      // Set up 10 items
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 10,
      ));
      await tester.pumpAndSettle();

      // Anchor on Msg 9
      controller.onUserMessageSent();
      await pumpAnchor(tester);

      // Drag to cancel anchor
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -100));
      await tester.pumpAndSettle();

      // Simulate user sending a new message: add item 11, call onUserMessageSent
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 11,
      ));
      await tester.pump();

      // Re-enable anchor on the new last item (Msg 10)
      controller.onUserMessageSent();
      await pumpAnchor(tester);

      // New last item (Msg 10) should now be at viewport top — anchor resumed
      final newLastItemY = tester.getTopLeft(find.text('Msg 10')).dy;
      expect(newLastItemY, closeTo(0.0, 1.0),
          reason:
              'API-04: After drag cancellation, next onUserMessageSent() must '
              're-enable anchor on new last item at viewport top (Y=0)');
    });
  });

  group('ANCH-05: Manual scroll when response exceeds viewport', () {
    testWidgets('user can scroll freely when AI response exceeds viewport',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = AiChatScrollController();
      addTearDown(controller.dispose);

      // Start with 1 item: user message (100px) in 600px viewport
      // After anchor: filler = 500px (viewportDimension - sentMsgHeight)
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 1,
      ));
      await tester.pumpAndSettle();

      // Anchor on Msg 0
      controller.onUserMessageSent();
      await pumpAnchor(tester);

      // Add 7 more items (700px of AI response below anchor).
      // Total content below anchor (700px) > viewport (600px) → filler = 0.
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 8,
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      // Get scroll controller to verify position changes on drag
      final scrollController = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      final pixelsBeforeDrag = scrollController.position.pixels;

      // User drags down to see more of the AI response (scroll forward)
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -100));
      await tester.pumpAndSettle();

      final pixelsAfterDrag = scrollController.position.pixels;

      // Scroll position must have changed — user is not locked in place
      expect(
        pixelsAfterDrag,
        isNot(closeTo(pixelsBeforeDrag, 1.0)),
        reason:
            'ANCH-05: When AI response exceeds viewport (filler=0), user must '
            'be able to scroll freely — scroll position must change on drag',
      );
    });
  });
}
