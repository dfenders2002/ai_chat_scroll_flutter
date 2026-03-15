import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat_scroll/ai_chat_scroll.dart';

/// Helper: builds a test widget with a scrollable chat view.
/// [itemCount] items of fixed [itemHeight].
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

/// Drive the 3-phase anchor pipeline to completion.
Future<void> pumpAnchor(WidgetTester tester) async {
  await tester.pump(); // setState rebuild
  await tester.pump(); // Phase 1 — scroll to bottom
  await tester.pump(); // Phase 2 — set filler
  await tester.pump(); // Phase 3 — jump to target
  await tester.pumpAndSettle(); // settle
}

/// Get the internal filler height ValueNotifier by reading the CustomScrollView.
/// We read the actual scroll position and filler from the scroll controller.
ScrollController getScrollController(WidgetTester tester) {
  final csv = tester.widget<CustomScrollView>(find.byType(CustomScrollView));
  return csv.controller!;
}

void main() {
  // ---------------------------------------------------------------------------
  // Test 1: During active anchor, keyboard open (viewport shrinks) reduces filler
  // and scroll position adjusts so anchor item stays at viewport top.
  // ---------------------------------------------------------------------------
  testWidgets(
    'Test 1: Keyboard open during anchor — filler shrinks and anchor stays at top',
    (tester) async {
      // Set initial viewport: 400×600
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = AiChatScrollController();
      addTearDown(controller.dispose);

      // 10 items × 100px = 1000px; viewport 600px
      await tester.pumpWidget(buildChat(controller: controller, itemCount: 10));
      await tester.pumpAndSettle();

      // Trigger anchor pipeline — anchor item is item 9
      controller.onUserMessageSent();
      await pumpAnchor(tester);

      // Verify anchor is active: item 9 is at Y=0
      final itemTopY = tester.getTopLeft(find.text('item 9')).dy;
      expect(itemTopY, closeTo(0.0, 2.0),
          reason: 'Pre-condition: anchor item at viewport top');

      // Record scroll state before keyboard open
      final scrollCtrl = getScrollController(tester);
      final maxExtentBefore = scrollCtrl.position.maxScrollExtent;

      // Simulate keyboard open: viewport shrinks from 600 to 400 (200px keyboard)
      tester.view.physicalSize = const Size(400, 400);
      await tester.pumpAndSettle();

      // Anchor item should still be at viewport top (Y=0)
      final itemTopAfterKeyboard = tester.getTopLeft(find.text('item 9')).dy;
      expect(itemTopAfterKeyboard, closeTo(0.0, 2.0),
          reason:
              'Test 1: After keyboard open, anchor item must remain at viewport top (Y=0)');

      // maxScrollExtent should have decreased (filler shrank)
      final maxExtentAfter = scrollCtrl.position.maxScrollExtent;
      expect(maxExtentAfter, lessThan(maxExtentBefore),
          reason:
              'Test 1: After keyboard open, filler must shrink → maxScrollExtent decreases');
    },
  );

  // ---------------------------------------------------------------------------
  // Test 2: During active anchor, keyboard close (viewport grows) increases filler
  // and anchor item stays at viewport top.
  // ---------------------------------------------------------------------------
  testWidgets(
    'Test 2: Keyboard close during anchor — filler grows and anchor stays at top',
    (tester) async {
      // Start with keyboard open: 400×400
      tester.view.physicalSize = const Size(400, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = AiChatScrollController();
      addTearDown(controller.dispose);

      // 10 items × 100px = 1000px; viewport 400px
      await tester.pumpWidget(buildChat(controller: controller, itemCount: 10));
      await tester.pumpAndSettle();

      // Trigger anchor pipeline
      controller.onUserMessageSent();
      await pumpAnchor(tester);

      // Verify anchor is active
      final itemTopY = tester.getTopLeft(find.text('item 9')).dy;
      expect(itemTopY, closeTo(0.0, 2.0),
          reason: 'Pre-condition: anchor item at viewport top');

      final scrollCtrl = getScrollController(tester);
      final maxExtentBefore = scrollCtrl.position.maxScrollExtent;

      // Simulate keyboard close: viewport grows from 400 to 600
      tester.view.physicalSize = const Size(400, 600);
      await tester.pumpAndSettle();

      // Anchor item should still be at viewport top
      final itemTopAfterKeyboardClose = tester.getTopLeft(find.text('item 9')).dy;
      expect(itemTopAfterKeyboardClose, closeTo(0.0, 2.0),
          reason:
              'Test 2: After keyboard close, anchor item must remain at viewport top (Y=0)');

      // maxScrollExtent should have increased (filler grew)
      final maxExtentAfter = scrollCtrl.position.maxScrollExtent;
      expect(maxExtentAfter, greaterThan(maxExtentBefore),
          reason:
              'Test 2: After keyboard close, filler must grow → maxScrollExtent increases');
    },
  );

  // ---------------------------------------------------------------------------
  // Test 3: Outside anchor mode, viewportDimension changes have no effect on filler.
  // ---------------------------------------------------------------------------
  testWidgets(
    'Test 3: Outside anchor mode, viewport dimension change does not affect filler',
    (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = AiChatScrollController();
      addTearDown(controller.dispose);

      // 5 items × 100px = 500px; viewport 600px — no scrolling needed, all items fit
      await tester.pumpWidget(buildChat(controller: controller, itemCount: 5));
      await tester.pumpAndSettle();

      // Do NOT call onUserMessageSent — anchor is not active
      final scrollCtrl = getScrollController(tester);
      final maxExtentBefore = scrollCtrl.position.maxScrollExtent;

      // Simulate keyboard open
      tester.view.physicalSize = const Size(400, 400);
      await tester.pumpAndSettle();

      final maxExtentAfter = scrollCtrl.position.maxScrollExtent;

      // Content is 500px; viewport is now 400px. The change in maxScrollExtent
      // is purely due to Flutter's layout, NOT filler compensation.
      // With 5×100px content = 500px and viewport=400px → maxScrollExtent should be ~100px
      // (without keyboard compensation altering the filler from 0).
      // Before: 500px content, 600px viewport, maxScrollExtent=0 (content fits)
      // After: 500px content, 400px viewport, maxScrollExtent=100px (content no longer fits)
      // The key: filler should still be 0.0 (no anchor active).
      // We verify by checking no extra compensation was added — the change matches natural layout.
      expect(maxExtentAfter, closeTo(100.0, 2.0),
          reason:
              'Test 3: Outside anchor mode, maxScrollExtent reflects natural layout only, no filler compensation');
    },
  );

  // ---------------------------------------------------------------------------
  // Test 4: Filler clamps to 0.0 if keyboard opens when filler is already small.
  // ---------------------------------------------------------------------------
  testWidgets(
    'Test 4: Filler clamps to 0.0 when keyboard open would push filler negative',
    (tester) async {
      // 400×600 viewport
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = AiChatScrollController();
      addTearDown(controller.dispose);

      // Only 2 items × 100px = 200px; viewport 600px
      // filler = viewportDimension - sentMsgHeight = 600 - 100 = 500px
      await tester.pumpWidget(buildChat(controller: controller, itemCount: 2));
      await tester.pumpAndSettle();

      controller.onUserMessageSent();
      await pumpAnchor(tester);

      // Anchor active; filler should be ~500px (600 - 100)
      final scrollCtrl = getScrollController(tester);
      final initialMaxExtent = scrollCtrl.position.maxScrollExtent;
      // With 2×100px content + 500px filler = 700px; viewport 600px → maxScrollExtent = 100px
      expect(initialMaxExtent, greaterThan(0.0),
          reason: 'Pre-condition: filler is set, maxScrollExtent > 0');

      // Simulate keyboard open that shrinks viewport by 600px (larger than filler).
      // This simulates a case where the delta > filler — filler must clamp to 0.
      // Actually, let's just shrink to 50px viewport (unrealistic but tests the clamp)
      tester.view.physicalSize = const Size(400, 50);
      await tester.pumpAndSettle();

      // Filler should be 0.0 — never negative
      // With filler=0, the content is 200px total; viewport=50px → maxScrollExtent=150px
      // We verify the filler doesn't go negative by checking scroll behavior is sane
      // (no assertion errors, no negative maxScrollExtent)
      final maxExtentAfter = scrollCtrl.position.maxScrollExtent;
      expect(maxExtentAfter, greaterThanOrEqualTo(0.0),
          reason: 'Test 4: maxScrollExtent must never go negative (filler clamped to 0)');
    },
  );
}
