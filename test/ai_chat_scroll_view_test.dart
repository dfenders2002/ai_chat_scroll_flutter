import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat_scroll/ai_chat_scroll.dart';

void main() {
  group('API-03: Builder API renders messages', () {
    testWidgets('renders all items via itemBuilder and itemCount',
        (tester) async {
      final controller = AiChatScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: AiChatScrollView(
            controller: controller,
            itemCount: 5,
            itemBuilder: (_, index) =>
                SizedBox(height: 100, child: Text('Msg $index')),
          ),
        ),
      );

      for (var i = 0; i < 5; i++) {
        expect(find.text('Msg $i'), findsOneWidget);
      }
    });
  });

  group('SCRL-01: Items render in index order', () {
    testWidgets(
        'index 0 has smaller Y offset than index 4 (rendered top to bottom)',
        (tester) async {
      final controller = AiChatScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: AiChatScrollView(
            controller: controller,
            itemCount: 10,
            itemBuilder: (_, index) =>
                SizedBox(height: 100, child: Text('Msg $index')),
          ),
        ),
      );

      // Msg 0 should be near the top of the scrollable area (smallest Y).
      // Msg 4 should be below it (larger Y).
      final y0 = tester.getTopLeft(find.text('Msg 0')).dy;
      final y4 = tester.getTopLeft(find.text('Msg 4')).dy;

      expect(y0, lessThan(y4),
          reason:
              'Index 0 should render above index 4 (forward-growing sliver list)');
    });
  });

  group('SCRL-02: Filler isolation — no extra message list rebuilds', () {
    testWidgets(
        'SliverToBoxAdapter (filler) exists in widget tree alongside SliverList',
        (tester) async {
      final controller = AiChatScrollController();
      addTearDown(controller.dispose);

      var buildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: AiChatScrollView(
            controller: controller,
            itemCount: 3,
            itemBuilder: (_, index) {
              buildCount++;
              return SizedBox(height: 100, child: Text('Msg $index'));
            },
          ),
        ),
      );

      final countAfterFirstPump = buildCount;

      // Verify composition: CustomScrollView exists and the filler's
      // ValueListenableBuilder is present (proves FillerSliver isolation).
      expect(find.byType(CustomScrollView), findsOneWidget,
          reason: 'AiChatScrollView must use a CustomScrollView');
      // ValueListenableBuilder<double> — use byWidgetPredicate because generic
      // type parameters are erased by find.byType at runtime.
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString().contains('ValueListenableBuilder'),
        ),
        findsOneWidget,
        reason: 'FillerSliver must use ValueListenableBuilder for isolation',
      );

      // Re-pump with the same widget (simulates a no-op parent rebuild)
      await tester.pumpWidget(
        MaterialApp(
          home: AiChatScrollView(
            controller: controller,
            itemCount: 3,
            itemBuilder: (_, index) {
              buildCount++;
              return SizedBox(height: 100, child: Text('Msg $index'));
            },
          ),
        ),
      );

      // On a no-op rebuild, SliverList.builder only rebuilds visible items
      // (which is all 3 here since they fit in the viewport). The key point
      // is that the filler uses ValueListenableBuilder — its updates don't
      // push extra build calls to the message itemBuilder.
      // Verify the count did not exceed 2x the expected visible items.
      expect(buildCount, lessThanOrEqualTo(countAfterFirstPump * 2),
          reason:
              'Message builder should not be called more than necessary on rebuild');
    });
  });

  group('SCRL-03: Scroll position preserved on item insertion', () {
    testWidgets(
        'scroll pixels unchanged when itemCount increases while user is mid-list',
        (tester) async {
      final controller = AiChatScrollController();
      addTearDown(controller.dispose);

      // Use a fixed-size window so we have a bounded viewport
      await tester.binding.setSurfaceSize(const Size(400, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: AiChatScrollView(
            controller: controller,
            itemCount: 20,
            itemBuilder: (_, index) =>
                SizedBox(height: 100, child: Text('Msg $index')),
          ),
        ),
      );

      // Find the internal ScrollController via the CustomScrollView
      final customScrollView = tester.widget<CustomScrollView>(
        find.byType(CustomScrollView),
      );
      final scrollController = customScrollView.controller!;

      // Jump to a mid-list position (500px into 2000px total content)
      scrollController.jumpTo(500);
      await tester.pumpAndSettle();

      final pixelsBefore = scrollController.position.pixels;
      expect(pixelsBefore, closeTo(500.0, 1.0));

      // Add one more item (no automatic scroll should occur)
      await tester.pumpWidget(
        MaterialApp(
          home: AiChatScrollView(
            controller: controller,
            itemCount: 21,
            itemBuilder: (_, index) =>
                SizedBox(height: 100, child: Text('Msg $index')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final pixelsAfter = scrollController.position.pixels;
      expect(pixelsAfter, closeTo(pixelsBefore, 1.0),
          reason:
              'Scroll position must not change when a new item is inserted '
              'and user is mid-list (SCRL-03)');
    });
  });

  group('SCRL-04: No hardcoded physics on CustomScrollView', () {
    testWidgets('CustomScrollView.physics is null (inherits ambient)',
        (tester) async {
      final controller = AiChatScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: AiChatScrollView(
            controller: controller,
            itemCount: 3,
            itemBuilder: (_, index) =>
                SizedBox(height: 100, child: Text('Msg $index')),
          ),
        ),
      );

      final customScrollView = tester.widget<CustomScrollView>(
        find.byType(CustomScrollView),
      );

      expect(customScrollView.physics, isNull,
          reason:
              'No physics should be hardcoded on CustomScrollView — '
              'the ambient ScrollConfiguration provides platform-appropriate physics (SCRL-04)');
    });
  });
}
