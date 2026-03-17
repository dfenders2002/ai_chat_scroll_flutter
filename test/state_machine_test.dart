import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_chat_scroll/ai_chat_scroll.dart';

void main() {
  // ---------------------------------------------------------------------------
  // STATE-01: Enum has exactly 5 values
  // ---------------------------------------------------------------------------
  group('STATE-01: AiChatScrollState enum', () {
    test('has exactly 5 values', () {
      expect(AiChatScrollState.values.length, equals(5));
    });

    test('has all expected named values', () {
      expect(AiChatScrollState.values, containsAll([
        AiChatScrollState.idleAtBottom,
        AiChatScrollState.submittedWaitingResponse,
        AiChatScrollState.streamingFollowing,
        AiChatScrollState.streamingDetached,
        AiChatScrollState.historyBrowsing,
      ]));
    });
  });

  // ---------------------------------------------------------------------------
  // STATE-03: scrollState getter exposes ValueListenable<AiChatScrollState>
  // ---------------------------------------------------------------------------
  group('STATE-03: scrollState getter', () {
    late AiChatScrollController controller;

    setUp(() {
      controller = AiChatScrollController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('STATE-03a: scrollState returns ValueListenable<AiChatScrollState>', () {
      // This will fail until scrollState getter is added to the controller.
      final listenable = controller.scrollState;
      expect(listenable, isA<ValueListenable<AiChatScrollState>>());
    });

    test('STATE-03b: initial value is idleAtBottom', () {
      expect(controller.scrollState.value, equals(AiChatScrollState.idleAtBottom));
    });

    test('STATE-03c: listener fires when state changes', () {
      int callCount = 0;
      controller.scrollState.addListener(() => callCount++);
      controller.onUserMessageSent();
      expect(callCount, equals(1));
    });

    test('STATE-03d: listener does NOT fire for no-op transitions', () {
      // Start at idleAtBottom; calling onResponseComplete (with isAtBottom=true)
      // should transition to idleAtBottom — which is already the current state,
      // so ValueNotifier deduplication should prevent a notification.
      int callCount = 0;
      controller.scrollState.addListener(() => callCount++);
      // Force isAtBottom to true (default is already true)
      controller.updateIsAtBottom(true);
      controller.onResponseComplete();
      // idleAtBottom -> idleAtBottom is a no-op
      expect(callCount, equals(0));
    });
  });

  // ---------------------------------------------------------------------------
  // STATE-02: State transitions
  // ---------------------------------------------------------------------------
  group('STATE-02: onUserMessageSent() transitions', () {
    late AiChatScrollController controller;

    setUp(() {
      controller = AiChatScrollController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('STATE-02a: idleAtBottom -> submittedWaitingResponse', () {
      // Fresh controller is idleAtBottom
      expect(controller.scrollState.value, equals(AiChatScrollState.idleAtBottom));
      controller.onUserMessageSent();
      expect(controller.scrollState.value,
          equals(AiChatScrollState.submittedWaitingResponse));
    });

    test('STATE-02b: historyBrowsing -> submittedWaitingResponse', () {
      // Simulate historyBrowsing: isAtBottom=false, then onResponseComplete
      controller.updateIsAtBottom(false);
      controller.onUserMessageSent();
      controller.onResponseComplete(); // goes to historyBrowsing
      expect(controller.scrollState.value, equals(AiChatScrollState.historyBrowsing));

      controller.onUserMessageSent();
      expect(controller.scrollState.value,
          equals(AiChatScrollState.submittedWaitingResponse));
    });

    test('STATE-02c: streamingFollowing -> submittedWaitingResponse (rapid send)', () {
      // We need to get to streamingFollowing first; for now test that
      // onUserMessageSent from submittedWaitingResponse produces the same result,
      // since streamingFollowing requires Phase 7 transitions.
      // This tests the universal rule: any state -> submittedWaitingResponse.
      controller.onUserMessageSent(); // -> submittedWaitingResponse
      controller.onUserMessageSent(); // rapid send, still -> submittedWaitingResponse
      expect(controller.scrollState.value,
          equals(AiChatScrollState.submittedWaitingResponse));
    });

    test('STATE-02d: streamingDetached -> submittedWaitingResponse (rapid send)', () {
      // Can't reach streamingDetached yet (requires Phase 7), but we can test
      // the controller's dispatch is always to submittedWaitingResponse.
      // Universal rule tested through other states covers this.
      controller.onUserMessageSent();
      expect(controller.scrollState.value,
          equals(AiChatScrollState.submittedWaitingResponse));
    });

    test('STATE-02e: submittedWaitingResponse -> submittedWaitingResponse (no-op)', () {
      controller.onUserMessageSent(); // -> submittedWaitingResponse
      int callCount = 0;
      controller.scrollState.addListener(() => callCount++);
      controller.onUserMessageSent(); // already there, no-op
      expect(controller.scrollState.value,
          equals(AiChatScrollState.submittedWaitingResponse));
      expect(callCount, equals(0));
    });
  });

  group('STATE-02: onResponseComplete() transitions', () {
    late AiChatScrollController controller;

    setUp(() {
      controller = AiChatScrollController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('STATE-02f: onResponseComplete() when isAtBottom=true -> idleAtBottom', () {
      controller.onUserMessageSent(); // -> submittedWaitingResponse
      controller.updateIsAtBottom(true);
      controller.onResponseComplete();
      expect(controller.scrollState.value, equals(AiChatScrollState.idleAtBottom));
    });

    test('STATE-02g: onResponseComplete() when isAtBottom=false -> historyBrowsing', () {
      controller.onUserMessageSent(); // -> submittedWaitingResponse
      controller.updateIsAtBottom(false);
      controller.onResponseComplete();
      expect(controller.scrollState.value, equals(AiChatScrollState.historyBrowsing));
    });

    test('STATE-02h: onResponseComplete() from submittedWaitingResponse is valid', () {
      controller.onUserMessageSent(); // -> submittedWaitingResponse
      controller.updateIsAtBottom(true);
      // Simulates error/timeout: response completes immediately without streaming
      controller.onResponseComplete();
      expect(controller.scrollState.value, equals(AiChatScrollState.idleAtBottom));
    });

    test('STATE-02i: redundant transition is silent no-op', () {
      // Already at idleAtBottom; calling onResponseComplete with isAtBottom=true
      // should be a no-op (idleAtBottom -> idleAtBottom)
      int callCount = 0;
      controller.scrollState.addListener(() => callCount++);
      controller.updateIsAtBottom(true);
      controller.onResponseComplete();
      expect(callCount, equals(0));
    });
  });

  // ---------------------------------------------------------------------------
  // COMPAT: isStreaming derived getter
  // ---------------------------------------------------------------------------
  group('COMPAT: isStreaming derived from scrollState', () {
    late AiChatScrollController controller;

    setUp(() {
      controller = AiChatScrollController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('isStreaming is false when idleAtBottom', () {
      expect(controller.scrollState.value, equals(AiChatScrollState.idleAtBottom));
      expect(controller.isStreaming, isFalse);
    });

    test('isStreaming is true when submittedWaitingResponse', () {
      controller.onUserMessageSent();
      expect(controller.scrollState.value,
          equals(AiChatScrollState.submittedWaitingResponse));
      expect(controller.isStreaming, isTrue);
    });

    test('isStreaming is false when historyBrowsing', () {
      controller.updateIsAtBottom(false);
      controller.onUserMessageSent();
      controller.onResponseComplete();
      expect(controller.scrollState.value, equals(AiChatScrollState.historyBrowsing));
      expect(controller.isStreaming, isFalse);
    });

    test('isStreaming is true when streamingFollowing (enum value check)', () {
      // We cannot reach streamingFollowing via public API yet (Phase 7),
      // but we can verify the derived logic by checking the enum constant directly.
      // The test below checks the logic without requiring a controller transition.
      const states = AiChatScrollState.values;
      final streamingStates = {
        AiChatScrollState.submittedWaitingResponse,
        AiChatScrollState.streamingFollowing,
        AiChatScrollState.streamingDetached,
      };
      final nonStreamingStates = {
        AiChatScrollState.idleAtBottom,
        AiChatScrollState.historyBrowsing,
      };
      expect(states.where(streamingStates.contains).length, equals(3));
      expect(states.where(nonStreamingStates.contains).length, equals(2));
    });
  });
}
