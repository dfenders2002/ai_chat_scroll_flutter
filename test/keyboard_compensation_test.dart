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

ScrollController getScrollController(WidgetTester tester) {
  final csv = tester.widget<CustomScrollView>(find.byType(CustomScrollView));
  return csv.controller!;
}

void main() {
  // ---------------------------------------------------------------------------
  // Test 1: During active anchor, keyboard open (viewport shrinks) — anchor
  // item remains visible at viewport top. The filler shrinks proportionally to
  // the viewport reduction so that maxScrollExtent (and therefore the anchor
  // position) remains stable. Visual Y=0 is the key invariant.
  // ---------------------------------------------------------------------------
  testWidgets(
    'Test 1: Keyboard open during anchor — anchor item stays at viewport top (Y=0)',
    (tester) async {
      // Set initial viewport: 400×600
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = AiChatScrollController();
      addTearDown(controller.dispose);

      // 10 items × 100px = 1000px; viewport 600px → scrollable
      await tester.pumpWidget(buildChat(controller: controller, itemCount: 10));
      await tester.pumpAndSettle();

      // Trigger anchor pipeline — anchor item is item 9
      controller.onUserMessageSent();
      await pumpAnchor(tester);

      // Verify anchor is active: item 9 is at Y=0
      final itemTopBefore = tester.getTopLeft(find.text('item 9')).dy;
      expect(itemTopBefore, closeTo(0.0, 2.0),
          reason: 'Pre-condition: anchor item at viewport top');

      // Simulate keyboard open: viewport shrinks from 600 to 400 (200px keyboard)
      tester.view.physicalSize = const Size(400, 400);
      await tester.pumpAndSettle();

      // Anchor item should still be at viewport top (Y=0)
      // Key invariant: filler shrinks by the same delta as viewport, keeping
      // maxScrollExtent constant, so scroll pixels don't change and item 9
      // remains exactly at Y=0.
      final itemTopAfterKeyboard = tester.getTopLeft(find.text('item 9')).dy;
      expect(itemTopAfterKeyboard, closeTo(0.0, 2.0),
          reason:
              'Test 1: After keyboard open, anchor item must remain at viewport top (Y=0)');

      // Scroll position should still equal maxScrollExtent (still anchored)
      final scrollCtrl = getScrollController(tester);
      final pos = scrollCtrl.position;
      expect(pos.pixels, closeTo(pos.maxScrollExtent, 1.0),
          reason:
              'Test 1: After keyboard open, scroll is still at maxScrollExtent (anchor stable)');
    },
  );

  // ---------------------------------------------------------------------------
  // Test 2: During active anchor, keyboard close (viewport grows) — anchor
  // item remains visible at viewport top. The filler grows proportionally.
  // ---------------------------------------------------------------------------
  testWidgets(
    'Test 2: Keyboard close during anchor — anchor item stays at viewport top (Y=0)',
    (tester) async {
      // Start with keyboard open: 400×400
      tester.view.physicalSize = const Size(400, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = AiChatScrollController();
      addTearDown(controller.dispose);

      // 10 items × 100px = 1000px; viewport 400px → scrollable
      await tester.pumpWidget(buildChat(controller: controller, itemCount: 10));
      await tester.pumpAndSettle();

      // Trigger anchor pipeline
      controller.onUserMessageSent();
      await pumpAnchor(tester);

      // Verify anchor is active
      final itemTopBefore = tester.getTopLeft(find.text('item 9')).dy;
      expect(itemTopBefore, closeTo(0.0, 2.0),
          reason: 'Pre-condition: anchor item at viewport top');

      // Simulate keyboard close: viewport grows from 400 to 600
      tester.view.physicalSize = const Size(400, 600);
      await tester.pumpAndSettle();

      // Anchor item should still be at viewport top
      final itemTopAfterKeyboardClose = tester.getTopLeft(find.text('item 9')).dy;
      expect(itemTopAfterKeyboardClose, closeTo(0.0, 2.0),
          reason:
              'Test 2: After keyboard close, anchor item must remain at viewport top (Y=0)');

      // Scroll position should still equal maxScrollExtent (still anchored)
      final scrollCtrl = getScrollController(tester);
      final pos = scrollCtrl.position;
      expect(pos.pixels, closeTo(pos.maxScrollExtent, 1.0),
          reason:
              'Test 2: After keyboard close, scroll is still at maxScrollExtent (anchor stable)');
    },
  );

  // ---------------------------------------------------------------------------
  // Test 3: Outside anchor mode, viewportDimension changes have no custom effect.
  // The package does not intervene — Flutter's natural layout handles resize.
  // ---------------------------------------------------------------------------
  testWidgets(
    'Test 3: Outside anchor mode, viewport dimension change has no custom compensation',
    (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final controller = AiChatScrollController();
      addTearDown(controller.dispose);

      // 5 items × 100px = 500px; viewport 600px — all items fit
      await tester.pumpWidget(buildChat(controller: controller, itemCount: 5));
      await tester.pumpAndSettle();

      // Do NOT call onUserMessageSent — anchor is not active
      // All items should be visible
      expect(find.text('item 0'), findsOneWidget);
      expect(find.text('item 4'), findsOneWidget);

      // Simulate keyboard open: viewport shrinks to 400px
      // Content 500px > viewport 400px → some items will go off screen naturally
      tester.view.physicalSize = const Size(400, 400);
      await tester.pumpAndSettle();

      // Verify that no compensation interfered — item 0 remains at top (we
      // never called onUserMessageSent, so no anchor was set, no filler manipulation)
      final item0Y = tester.getTopLeft(find.text('item 0')).dy;
      expect(item0Y, closeTo(0.0, 2.0),
          reason:
              'Test 3: Outside anchor mode, items stay in their natural position; item 0 at top');

      // The scroll position remains at 0 — no compensation moved it
      final scrollCtrl = getScrollController(tester);
      expect(scrollCtrl.position.pixels, closeTo(0.0, 1.0),
          reason: 'Test 3: Outside anchor mode, scroll position unchanged');
    },
  );

  // ---------------------------------------------------------------------------
  // Test 4: Filler clamps to 0.0 if keyboard opens and delta > filler.
  // The package must never allow filler to go negative.
  // ---------------------------------------------------------------------------
  testWidgets(
    'Test 4: Filler clamps to 0.0 when keyboard open delta exceeds current filler',
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

      // Anchor active; item 1 is at viewport top
      final itemTopBefore = tester.getTopLeft(find.text('item 1')).dy;
      expect(itemTopBefore, closeTo(0.0, 2.0),
          reason: 'Pre-condition: anchor item at viewport top');

      // Simulate extreme keyboard open: viewport shrinks to 50px
      // delta = 50 - 600 = -550, filler = max(0, 500 - 550) = 0 (clamped)
      tester.view.physicalSize = const Size(400, 50);
      await tester.pumpAndSettle();

      // No crash, no negative values
      final scrollCtrl = getScrollController(tester);
      final maxExtent = scrollCtrl.position.maxScrollExtent;
      expect(maxExtent, greaterThanOrEqualTo(0.0),
          reason: 'Test 4: maxScrollExtent must never go negative (filler clamped to 0)');

      // pixels should also be >= 0
      expect(scrollCtrl.position.pixels, greaterThanOrEqualTo(0.0),
          reason: 'Test 4: scroll pixels must never go negative');
    },
  );
}
