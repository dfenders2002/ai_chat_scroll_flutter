import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat_scroll/ai_chat_scroll.dart';

/// Helper: builds a test widget with a scrollable chat view backed by
/// [controller] and [itemCount] items of fixed height [itemHeight].
Widget buildChat({
  required AiChatScrollController controller,
  required int itemCount,
  double itemHeight = 100.0,
}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: AiChatScrollView(
      controller: controller,
      itemCount: itemCount,
      itemBuilder: (_, index) => SizedBox(
        height: itemHeight,
        child: Text('item $index'),
      ),
    ),
  );
}

void main() {
  // ---------------------------------------------------------------------------
  // Test 1: isAtBottom is a ValueListenable<bool> and starts as true
  // ---------------------------------------------------------------------------
  test('Test 1: isAtBottom is a ValueListenable<bool> and starts as true', () {
    final controller = AiChatScrollController();
    expect(controller.isAtBottom, isA<ValueListenable<bool>>());
    expect(controller.isAtBottom.value, isTrue);
    controller.dispose();
  });

  // ---------------------------------------------------------------------------
  // Test 2: isAtBottom transitions to false when user scrolls up
  // ---------------------------------------------------------------------------
  testWidgets(
    'Test 2: isAtBottom becomes false when user scrolls away from bottom',
    (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = AiChatScrollController();
      // 20 items × 100px = 2000px content; viewport 600px → scrollable
      await tester.pumpWidget(buildChat(
        controller: controller,
        itemCount: 20,
        itemHeight: 100.0,
      ));
      await tester.pump();

      // Simulate scrolling to the bottom first (so isAtBottom starts true)
      // Then drag up to move away from the bottom
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, 500), // drag down = content scrolls up = user moves toward top
      );
      await tester.pump();

      expect(controller.isAtBottom.value, isFalse);
      controller.dispose();
    },
  );

  // ---------------------------------------------------------------------------
  // Test 3: isAtBottom transitions to true when user scrolls back to bottom
  // ---------------------------------------------------------------------------
  testWidgets(
    'Test 3: isAtBottom becomes true when user scrolls back to bottom',
    (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = AiChatScrollController();
      await tester.pumpWidget(buildChat(
        controller: controller,
        itemCount: 20,
        itemHeight: 100.0,
      ));
      await tester.pump();

      // Scroll away from the bottom first
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, 500),
      );
      await tester.pump();
      expect(controller.isAtBottom.value, isFalse);

      // Now scroll back to the bottom
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, -2000),
      );
      await tester.pump();

      expect(controller.isAtBottom.value, isTrue);
      controller.dispose();
    },
  );

  // ---------------------------------------------------------------------------
  // Test 4: scrollToBottom() animates to bottom and isAtBottom becomes true
  // ---------------------------------------------------------------------------
  testWidgets(
    'Test 4: scrollToBottom() animates to maxScrollExtent and isAtBottom becomes true',
    (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = AiChatScrollController();
      await tester.pumpWidget(buildChat(
        controller: controller,
        itemCount: 20,
        itemHeight: 100.0,
      ));
      await tester.pump();

      // Scroll away from the bottom
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, 500),
      );
      await tester.pump();
      expect(controller.isAtBottom.value, isFalse);

      // Call scrollToBottom()
      controller.scrollToBottom();
      // Run animation to completion
      await tester.pumpAndSettle();

      expect(controller.isAtBottom.value, isTrue);
      controller.dispose();
    },
  );

  // ---------------------------------------------------------------------------
  // Test 5: After onUserMessageSent() + anchor pipeline, isAtBottom reflects
  // scroll position. The anchor pipeline places the user at maxScrollExtent
  // (filler fills the viewport, sent message at top). Since position is at
  // maxScrollExtent, isAtBottom is true — the user is "at the bottom" of the
  // scroll range (the filler is below but that is invisible padding).
  // ---------------------------------------------------------------------------
  testWidgets(
    'Test 5: After onUserMessageSent() and anchor pipeline, isAtBottom reflects actual scroll position',
    (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = AiChatScrollController();
      // Use 10 items so there's enough content for an anchor jump
      await tester.pumpWidget(buildChat(
        controller: controller,
        itemCount: 10,
        itemHeight: 100.0,
      ));
      // Let initial layout settle
      await tester.pumpAndSettle();

      // Send a message — triggers anchor pipeline
      controller.onUserMessageSent();
      // Drive all post-frame callbacks (multi-phase anchor pipeline)
      await tester.pumpAndSettle();

      // After the anchor jump, scroll is at maxScrollExtent (the filler
      // extends below the sent message). isAtBottom is true because
      // maxScrollExtent - pixels == 0 <= threshold (50.0).
      expect(controller.isAtBottom.value, isTrue);

      controller.dispose();
    },
  );

  // ---------------------------------------------------------------------------
  // Test 6: After onResponseComplete(), isAtBottom reflects actual scroll position
  // ---------------------------------------------------------------------------
  testWidgets(
    'Test 6: After onResponseComplete(), isAtBottom reflects actual scroll position',
    (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = AiChatScrollController();
      await tester.pumpWidget(buildChat(
        controller: controller,
        itemCount: 10,
        itemHeight: 100.0,
      ));
      await tester.pumpAndSettle();

      // Scroll away from the bottom
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, 300),
      );
      await tester.pump();
      expect(controller.isAtBottom.value, isFalse);

      // Complete response — anchor resets, but user is still scrolled up
      controller.onResponseComplete();
      await tester.pump();

      // isAtBottom should still be false since user hasn't scrolled back
      expect(controller.isAtBottom.value, isFalse);

      controller.dispose();
    },
  );

  // ---------------------------------------------------------------------------
  // Test 7: atBottomThreshold is configurable; near-bottom counts as "at bottom"
  // ---------------------------------------------------------------------------
  testWidgets(
    'Test 7: atBottomThreshold is configurable — items within threshold count as at bottom',
    (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Use large threshold so a position within 100px of bottom still counts as bottom
      final controller = AiChatScrollController(atBottomThreshold: 100.0);
      await tester.pumpWidget(buildChat(
        controller: controller,
        itemCount: 20,
        itemHeight: 100.0,
      ));
      await tester.pump();

      // Widget starts at the top (pixels = 0) with 20×100px = 2000px content
      // and 600px viewport → maxScrollExtent = 1400px.
      // isAtBottom.value defaults to true before any scroll event fires;
      // after pump() the scroll listener fires and updates to false.
      expect(controller.isAtBottom.value, isFalse);

      // Scroll to near-bottom: drag up strongly so pixels ≈ maxScrollExtent - 60px.
      // Drag down (positive y) scrolls toward top; drag up (negative y) scrolls toward bottom.
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, -1340), // go to ~60px from bottom (1400 - 1340 = 60 < threshold 100)
      );
      await tester.pump();

      // Within 100px threshold → should be considered "at bottom"
      expect(controller.isAtBottom.value, isTrue);

      // Drag back up — beyond the threshold
      await tester.drag(
        find.byType(CustomScrollView),
        const Offset(0, 200), // 200px back toward top → now 260px from bottom > 100px threshold
      );
      await tester.pump();

      expect(controller.isAtBottom.value, isFalse);
      controller.dispose();
    },
  );

  // ---------------------------------------------------------------------------
  // scrollToBottom() is a no-op when controller has no clients
  // ---------------------------------------------------------------------------
  test('scrollToBottom() is safe to call before attach (no-op)', () {
    final controller = AiChatScrollController();
    expect(() => controller.scrollToBottom(), returnsNormally);
    controller.dispose();
  });

  // ---------------------------------------------------------------------------
  // atBottomThreshold has default value of 50.0
  // ---------------------------------------------------------------------------
  test('atBottomThreshold defaults to 50.0', () {
    final controller = AiChatScrollController();
    expect(controller.atBottomThreshold, equals(50.0));
    controller.dispose();
  });
}
