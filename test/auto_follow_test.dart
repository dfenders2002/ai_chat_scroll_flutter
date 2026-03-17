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
  // FOLLOW-01, FOLLOW-02, FOLLOW-03 tests verify the behavior wired through:
  // - controller.onUserScrolled() — drag triggers streamingFollowing → streamingDetached
  // - controller.onContentGrowthDetected() — content growth triggers submittedWaitingResponse → streamingFollowing
  // - controller.onScrolledToBottom() — scroll-back triggers streamingDetached → streamingFollowing
  group('FOLLOW-01: Auto-follow tracks content growth during streamingFollowing', () {
    testWidgets('FOLLOW-01 content growth triggers streamingFollowing and compensation',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = AiChatScrollController();
      addTearDown(controller.dispose);

      // Start with 10 items (1000px total, viewport 600px)
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 10,
      ));
      await tester.pumpAndSettle();

      // Trigger anchor: user sent message
      controller.onUserMessageSent();
      await pumpAnchor(tester);

      // State should be submittedWaitingResponse at this point
      // (no content growth yet)
      expect(
        controller.scrollState.value,
        AiChatScrollState.submittedWaitingResponse,
        reason: 'After onUserMessageSent() and anchor, state is submittedWaitingResponse',
      );

      final scrollController =
          tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!;
      final pixelsBefore = scrollController.position.pixels;

      // Simulate AI response: add item → triggers content growth
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 11,
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      // State must have transitioned to streamingFollowing due to content growth
      expect(
        controller.scrollState.value,
        AiChatScrollState.streamingFollowing,
        reason: 'FOLLOW-01: Content growth during submittedWaitingResponse must trigger streamingFollowing',
      );

      // Scroll compensation must have fired to keep viewport tracking content
      final pixelsAfter = scrollController.position.pixels;
      expect(
        pixelsAfter,
        greaterThan(pixelsBefore),
        reason: 'FOLLOW-01: During streamingFollowing, scroll position increases to track content growth',
      );
    });

    testWidgets('FOLLOW-01b no compensation when not in streaming state', (tester) async {
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

      // Controller starts in idleAtBottom — NOT streaming
      expect(
        controller.scrollState.value,
        AiChatScrollState.idleAtBottom,
        reason: 'Pre-condition: starts in idleAtBottom',
      );

      final scrollController =
          tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!;

      // Scroll to middle (not at bottom, simulate user browsing)
      scrollController.jumpTo(200.0);
      await tester.pump();
      final pixelsBefore = scrollController.position.pixels;

      // Add items while in idleAtBottom — should NOT cause jumpTo compensation
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 12,
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      final pixelsAfter = scrollController.position.pixels;
      // Pixels should not have been artificially compensated upward
      // (state is idleAtBottom, so no compensation should fire)
      expect(
        controller.scrollState.value,
        AiChatScrollState.idleAtBottom,
        reason: 'FOLLOW-01b: State must remain idleAtBottom when no message was sent',
      );
      expect(
        pixelsAfter,
        closeTo(pixelsBefore, 5.0),
        reason: 'FOLLOW-01b: No scroll compensation when not in streaming state',
      );
    });
  });

  group('FOLLOW-02: User drag detaches auto-follow', () {
    testWidgets('FOLLOW-02 drag transitions to streamingDetached', (tester) async {
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

      // Anchor
      controller.onUserMessageSent();
      await pumpAnchor(tester);

      // Transition to streamingFollowing by simulating content growth
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 11,
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        controller.scrollState.value,
        AiChatScrollState.streamingFollowing,
        reason: 'Pre-condition: must be in streamingFollowing before drag test',
      );

      // User drags upward (away from live bottom) during streaming
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
      await tester.pump();

      // State must transition to streamingDetached immediately
      expect(
        controller.scrollState.value,
        AiChatScrollState.streamingDetached,
        reason: 'FOLLOW-02: User drag during streamingFollowing must immediately transition to streamingDetached',
      );
    });

    testWidgets('FOLLOW-02b no compensation after detach', (tester) async {
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

      // Anchor and reach streamingFollowing
      controller.onUserMessageSent();
      await pumpAnchor(tester);

      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 11,
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(controller.scrollState.value, AiChatScrollState.streamingFollowing);

      // User drags to detach
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
      await tester.pump();

      expect(controller.scrollState.value, AiChatScrollState.streamingDetached);

      final scrollController =
          tester.widget<CustomScrollView>(find.byType(CustomScrollView)).controller!;
      final pixelsAfterDetach = scrollController.position.pixels;

      // Add more items — should NOT cause compensation in streamingDetached
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 13,
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      final pixelsAfterMoreContent = scrollController.position.pixels;
      expect(
        pixelsAfterMoreContent,
        closeTo(pixelsAfterDetach, 5.0),
        reason: 'FOLLOW-02b: No scroll compensation fires after entering streamingDetached',
      );
    });
  });

  group('FOLLOW-03: Re-attach on scroll-back or scrollToBottom', () {
    testWidgets('FOLLOW-03 scroll to bottom re-attaches during streaming', (tester) async {
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

      // Anchor and reach streamingFollowing
      controller.onUserMessageSent();
      await pumpAnchor(tester);

      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 11,
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(controller.scrollState.value, AiChatScrollState.streamingFollowing);

      // Drag upward to detach
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
      await tester.pump();

      expect(controller.scrollState.value, AiChatScrollState.streamingDetached);

      // Drag back to live bottom (positive Y = toward live bottom in reverse:true list)
      // In reverse:true, pixels=0 is live bottom; positive drag moves toward pixels=0
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 200));
      await tester.pumpAndSettle();

      // State should have re-attached to streamingFollowing
      expect(
        controller.scrollState.value,
        AiChatScrollState.streamingFollowing,
        reason: 'FOLLOW-03: Scrolling back to live bottom during streamingDetached must re-attach to streamingFollowing',
      );
    });

    testWidgets('FOLLOW-03b scrollToBottom() re-attaches during streaming', (tester) async {
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

      // Anchor and reach streamingFollowing
      controller.onUserMessageSent();
      await pumpAnchor(tester);

      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 11,
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(controller.scrollState.value, AiChatScrollState.streamingFollowing);

      // Drag upward to detach
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
      await tester.pump();

      expect(controller.scrollState.value, AiChatScrollState.streamingDetached);

      // Call scrollToBottom() — should re-attach to streamingFollowing
      controller.scrollToBottom();
      await tester.pumpAndSettle();

      expect(
        controller.scrollState.value,
        AiChatScrollState.streamingFollowing,
        reason: 'FOLLOW-03b: scrollToBottom() during streamingDetached must re-attach to streamingFollowing',
      );
    });
  });
}
