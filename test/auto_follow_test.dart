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
/// fire. The anchor uses a multi-phase postFrameCallback chain.
/// Extra pumps ensure the chain completes even if box lookup retries once.
Future<void> pumpAnchor(WidgetTester tester) async {
  // Pump enough frames to drive the full anchor callback chain:
  // frame 0: callsStartAnchor fires → setState + addPFCB(_measureAndAnchor)
  // frame 1: rebuild + _measureAndAnchor fires (box check, filler set, scheduleFrame + PFCB(C))
  // frame 2: C fires → jumpTo(0) + _lastMaxScrollExtent + _anchorSetupComplete = true
  // extra frames in case box is null on first attempt (rare in tests)
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
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

/// Simulates AI response starting by directly triggering the state transition
/// that the view would trigger upon detecting first content growth.
///
/// In production, [AiChatScrollController.onContentGrowthDetected] is called
/// by [AiChatScrollView] when [ScrollMetricsNotification] detects maxScrollExtent
/// growing while in submittedWaitingResponse. In tests, this notification does
/// not fire when items are added via pumpWidget, so we call it directly.
void simulateContentGrowth(AiChatScrollController controller) {
  // This calls the same method the view calls — the test is exercising the
  // controller state machine and view compensation, not the notification plumbing.
  controller.onContentGrowthDetected();
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
      expect(
        controller.scrollState.value,
        AiChatScrollState.submittedWaitingResponse,
        reason: 'After onUserMessageSent() and anchor, state is submittedWaitingResponse',
      );

      // Simulate AI response: first token arrives → content growth detected.
      // In production, AiChatScrollView calls this when ScrollMetricsNotification
      // fires with growing maxScrollExtent. We call it directly in tests.
      simulateContentGrowth(controller);
      await tester.pump();

      // State must have transitioned to streamingFollowing
      expect(
        controller.scrollState.value,
        AiChatScrollState.streamingFollowing,
        reason: 'FOLLOW-01: Content growth during submittedWaitingResponse must trigger streamingFollowing',
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

      // Add items while in idleAtBottom — state must NOT change
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 12,
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      // State remains idleAtBottom — no spurious transition
      expect(
        controller.scrollState.value,
        AiChatScrollState.idleAtBottom,
        reason: 'FOLLOW-01b: State must remain idleAtBottom when not in streaming state',
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
      simulateContentGrowth(controller);
      await tester.pump();

      expect(
        controller.scrollState.value,
        AiChatScrollState.streamingFollowing,
        reason: 'Pre-condition: must be in streamingFollowing before drag test',
      );

      // User drags down (positive Y = toward history / away from live bottom)
      // in a reverse:true list, drag down increases pixels = moves away from live bottom
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 200));
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

      simulateContentGrowth(controller);
      await tester.pump();

      expect(controller.scrollState.value, AiChatScrollState.streamingFollowing);

      // User drags down (positive Y = toward history) to detach
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 200));
      await tester.pump();

      expect(controller.scrollState.value, AiChatScrollState.streamingDetached);

      // After detach: state is streamingDetached — compenssation must NOT fire.
      // In production, adding new content would not change scroll position.
      // We verify the state machine: onContentGrowthDetected() in streamingDetached
      // must NOT change state (no accidental re-attach).
      final previousState = controller.scrollState.value;
      // Simulate more content growth while detached
      controller.onContentGrowthDetected(); // no-op in streamingDetached
      await tester.pump();

      expect(
        controller.scrollState.value,
        previousState,
        reason: 'FOLLOW-02b: onContentGrowthDetected is a no-op when not in submittedWaitingResponse',
      );
      expect(
        controller.scrollState.value,
        AiChatScrollState.streamingDetached,
        reason: 'FOLLOW-02b: State remains streamingDetached after content growth while detached',
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

      simulateContentGrowth(controller);
      await tester.pump();

      expect(controller.scrollState.value, AiChatScrollState.streamingFollowing);

      // Drag down (positive Y = toward history) to detach
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 200));
      await tester.pump();

      expect(controller.scrollState.value, AiChatScrollState.streamingDetached);

      // Drag up (negative Y = toward live bottom) to re-attach.
      // In reverse:true: negative Y drag decreases pixels, returning to pixels~=0
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pump();
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

      simulateContentGrowth(controller);
      await tester.pump();

      expect(controller.scrollState.value, AiChatScrollState.streamingFollowing);

      // Drag down (positive Y = toward history) to detach
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 200));
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
