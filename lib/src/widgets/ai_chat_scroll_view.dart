import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../controller/ai_chat_scroll_controller.dart';
import '../model/ai_chat_scroll_state.dart';

/// AI chat scroll view with anchor-on-send behavior.
///
/// Uses `reverse: true` internally so messages gravity to the bottom
/// automatically (like Claude/ChatGPT). Pass messages in chronological
/// order (index 0 = oldest) — the widget handles reversal.
class AiChatScrollView extends StatefulWidget {
  /// Creates an [AiChatScrollView].
  const AiChatScrollView({
    super.key,
    required this.controller,
    required this.itemBuilder,
    required this.itemCount,
  });

  /// The [AiChatScrollController] that drives anchor scroll behavior.
  final AiChatScrollController controller;

  /// Called to build each message item in the list.
  /// Pass messages in chronological order (index 0 = oldest).
  final IndexedWidgetBuilder itemBuilder;

  /// The total number of message items to display.
  final int itemCount;

  @override
  State<AiChatScrollView> createState() => _AiChatScrollViewState();
}

class _AiChatScrollViewState extends State<AiChatScrollView> {
  late final ScrollController _scrollController;
  late final ValueNotifier<double> _fillerHeight;

  // Anchor state — no setState needed for these, they're read in
  // notification handlers and postFrameCallbacks, not in build().
  int _anchorReverseIndex = -1;
  final GlobalKey _anchorKey = GlobalKey();
  // Initialized to maxFinite so no spurious delta is computed before the anchor
  // callback establishes the real baseline. The anchor callback sets this to the
  // actual post-filler maxScrollExtent after jumpTo(0.0) runs.
  double _lastMaxScrollExtent = double.maxFinite;

  @override
  void initState() {
    super.initState();
    _fillerHeight = ValueNotifier(0.0);
    _scrollController = ScrollController();
    _scrollController.addListener(_onScrollChanged);
    widget.controller.attach(_scrollController);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(AiChatScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      oldWidget.controller.detach();
      widget.controller.attach(_scrollController);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    widget.controller.detach();
    _scrollController.removeListener(_onScrollChanged);
    _fillerHeight.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ——— Controller events ————————————————————————————————————————————————

  void _onControllerChanged() {
    final state = widget.controller.scrollState.value;
    if (state == AiChatScrollState.submittedWaitingResponse) {
      // Only start anchor on fresh message send, not on streaming state changes.
      // Wait for parent to rebuild with the new message.
      // scheduleFrame() ensures the postFrameCallback fires on the next pump()
      // even when called between frames (e.g., in tests).
      SchedulerBinding.instance.scheduleFrame();
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _startAnchor();
      });
    } else if (!widget.controller.isStreaming) {
      // onResponseComplete — stop compensating, keep layout as-is.
      // Only rebuild to remove the GlobalKey from the anchor item.
      if (_anchorReverseIndex != -1) {
        setState(() {
          _anchorReverseIndex = -1;
        });
      }
    }
  }

  void _startAnchor() {
    // Reset anchor-complete flag and baseline.
    // Setting _lastMaxScrollExtent = maxFinite prevents _onMetricsChanged from
    // detecting "content growth" until the anchor callback sets the real baseline.
    _lastMaxScrollExtent = double.maxFinite;
    // The user message is the newest = reverseIndex 0.
    // setState ONCE to attach the GlobalKey to the correct item.
    setState(() {
      _anchorReverseIndex = 0;
    });

    // After rebuild with GlobalKey attached, measure and set filler.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _measureAndAnchor();
    });
  }

  void _measureAndAnchor() {
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _measureAndAnchor();
      });
      return;
    }

    final pos = _scrollController.position;
    final viewport = pos.viewportDimension;
    final userMsgHeight = box.size.height;

    // Set filler via ValueNotifier — only the filler SizedBox rebuilds,
    // NOT the entire CustomScrollView or SliverList.
    _fillerHeight.value = math.max(0.0, viewport - userMsgHeight);

    // After filler layout, jump to anchor position.
    SchedulerBinding.instance.scheduleFrame();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.jumpTo(0.0);
      // Establish baseline after filler-adjusted layout is complete.
      // From this point, any newMax > _lastMaxScrollExtent is real content growth.
      _lastMaxScrollExtent = _scrollController.position.maxScrollExtent;
    });
  }

  // ——— Scroll tracking ——————————————————————————————————————————————————

  void _onScrollChanged() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final atBottom = pos.pixels <= widget.controller.atBottomThreshold;
    widget.controller.updateIsAtBottom(atBottom);

    // Re-attach: if user scrolled back to live bottom during streamingDetached
    final state = widget.controller.scrollState.value;
    if (state == AiChatScrollState.streamingDetached && atBottom) {
      widget.controller.onScrolledToBottom();
    }
  }

  // ——— Streaming compensation ———————————————————————————————————————————

  void _onMetricsChanged(ScrollMetricsNotification notification) {
    if (!_scrollController.hasClients) return;
    final state = widget.controller.scrollState.value;

    // First content growth while waiting for response → start following.
    // _lastMaxScrollExtent starts at double.maxFinite until the anchor callback
    // sets the real baseline. Any notification before the anchor completes will
    // have newMax < maxFinite, making the check fail → no spurious transition.
    // After anchor completes: _lastMaxScrollExtent = actual post-anchor max.
    // Real content growth (AI response) will have newMax > _lastMaxScrollExtent.
    if (state == AiChatScrollState.submittedWaitingResponse) {
      final newMax = notification.metrics.maxScrollExtent;
      if (newMax <= _lastMaxScrollExtent + 0.5) return;
      widget.controller.onContentGrowthDetected();
      // Fall through to compensate on the same frame.
    } else if (state != AiChatScrollState.streamingFollowing) {
      // Not in any streaming-following state — no compensation needed.
      return;
    }

    final newMax = notification.metrics.maxScrollExtent;
    final delta = newMax - _lastMaxScrollExtent;

    if (delta > 0.5) {
      _lastMaxScrollExtent = newMax;
      final target = _scrollController.offset + delta;
      _scrollController.jumpTo(target.clamp(0.0, newMax));
    } else if (delta < -0.5) {
      _lastMaxScrollExtent = newMax;
    }
  }

  // ——— Build ——————————————————————————————————————————————————————————————

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (notification) {
        // Detach only when the user drags AWAY from the live bottom
        // (scrollDelta > 0 means pixels are increasing = moving toward history
        // in a reverse:true list). Ignore drag events moving toward live bottom
        // to prevent immediately re-detaching during a scroll-back gesture.
        if (notification.dragDetails != null &&
            (notification.scrollDelta ?? 0) > 0 &&
            widget.controller.scrollState.value ==
                AiChatScrollState.streamingFollowing) {
          widget.controller.onUserScrolled();
        }
        return false;
      },
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          _onMetricsChanged(notification);
          return false;
        },
        child: CustomScrollView(
          reverse: true,
          controller: _scrollController,
          slivers: [
            // Filler — isolated via ValueListenableBuilder so changes
            // only rebuild this SizedBox, not the message list.
            SliverToBoxAdapter(
              child: ValueListenableBuilder<double>(
                valueListenable: _fillerHeight,
                builder: (context, height, _) => SizedBox(height: height),
              ),
            ),
            // Messages — reversed indices so user passes chronological order.
            SliverList.builder(
              itemCount: widget.itemCount,
              itemBuilder: (context, reverseIndex) {
                final chronoIndex = widget.itemCount - 1 - reverseIndex;
                final child = widget.itemBuilder(context, chronoIndex);
                if (reverseIndex == _anchorReverseIndex) {
                  return KeyedSubtree(key: _anchorKey, child: child);
                }
                return child;
              },
            ),
          ],
        ),
      ),
    );
  }
}
