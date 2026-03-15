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

void main() {
  group('ANCH-01: After onUserMessageSent(), sent message top is at viewport top',
      () {
    testWidgets('last item top Y equals 0.0 after anchor', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = AiChatScrollController();
      addTearDown(controller.dispose);

      // Pump 10 items (each 100px tall = 1000px total, viewport 600px)
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 10,
      ));
      await tester.pumpAndSettle();

      // Trigger anchor jump
      controller.onUserMessageSent();
      await tester.pump();
      await tester.pumpAndSettle();

      // The last item (Msg 9) should now have its top at Y = 0.0
      final lastItemTopY = tester.getTopLeft(find.text('Msg 9')).dy;
      expect(lastItemTopY, closeTo(0.0, 1.0),
          reason:
              'ANCH-01: After onUserMessageSent(), the sent message top must be at viewport top (Y=0)');
    });
  });

  group('ANCH-06: Re-anchor works after scrolling to history', () {
    testWidgets(
        'after scrolling to top, new last item anchors at viewport top after onUserMessageSent',
        (tester) async {
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

      // Access scroll controller and scroll to top (history)
      final customScrollView = tester.widget<CustomScrollView>(
        find.byType(CustomScrollView),
      );
      final scrollController = customScrollView.controller!;

      scrollController.jumpTo(0.0);
      await tester.pumpAndSettle();

      expect(scrollController.position.pixels, closeTo(0.0, 1.0),
          reason: 'Pre-condition: scrolled to top of history');

      // Simulate user adding a new message (itemCount goes from 10 to 11)
      // then calling onUserMessageSent
      await tester.pumpWidget(buildTestWidget(
        controller: controller,
        itemCount: 11,
      ));
      await tester.pump();

      controller.onUserMessageSent();
      await tester.pump();
      await tester.pumpAndSettle();

      // New last item (Msg 10) should be at viewport top
      final lastItemTopY = tester.getTopLeft(find.text('Msg 10')).dy;
      expect(lastItemTopY, closeTo(0.0, 1.0),
          reason:
              'ANCH-06: After re-send from history, new sent message must re-anchor at viewport top (Y=0)');
    });
  });
}
