import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../controller/ai_chat_scroll_controller.dart';
import 'filler_sliver.dart';

/// A scrollable view for AI chat interfaces that composes a message list and
/// a dynamic filler sliver.
///
/// Pass [itemBuilder] and [itemCount] to supply your message items. This widget
/// owns the [CustomScrollView] and internal [ScrollController] so it can
/// compose slivers (message list + filler) required for the top-anchor-on-send
/// behavior.
///
/// ## Anchor behavior
///
/// When [AiChatScrollController.onUserMessageSent] is called, this widget
/// snaps the scroll position so the sent message (the last item at call time)
/// appears at the top of the viewport. As the AI response streams in, the
/// filler sliver shrinks to keep the anchor stable without any scroll movement.
/// When the user drags the list, the anchor is cancelled and the user scrolls
/// freely.
///
/// The filler sliver sits below the message list and is driven by an internal
/// [ValueNotifier]. Because it is isolated via [ValueListenableBuilder], filler
/// height changes during AI response streaming do NOT trigger rebuilds of the
/// message list items.
///
/// No [ScrollPhysics] is forced — the widget inherits the ambient
/// [ScrollConfiguration] so that platform-appropriate physics (bouncing on iOS,
/// clamping on Android) are applied automatically.
///
/// ## Keyboard awareness
///
/// During an active anchor, this widget automatically compensates for soft
/// keyboard open/close events. When the viewport dimension changes (e.g. the
/// soft keyboard opens and shrinks the visible area), the filler sliver is
/// recomputed by the exact viewport delta so the anchored message remains at
/// the top of the visible area. When the keyboard closes and the viewport grows,
/// the filler is expanded by the same delta.
///
/// Outside of anchor mode, keyboard events are handled by Flutter's normal
/// scroll behavior — this widget does not interfere.
///
/// Filler height is always clamped to 0.0 and never goes negative, ensuring
/// correctness even when the AI response already exceeds the visible area.
///
/// ## Example
///
/// ```dart
/// AiChatScrollView(
///   controller: myAiChatScrollController,
///   itemCount: messages.length,
///   itemBuilder: (context, index) => MessageTile(messages[index]),
/// )
/// ```
///
/// > **Note:** Pass messages in chronological order (index 0 = oldest,
/// > last index = newest). The [AiChatScrollView] renders items top-to-bottom,
/// > producing the conventional newest-at-bottom chat layout.
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
  final IndexedWidgetBuilder itemBuilder;

  /// The total number of message items to display.
  final int itemCount;

  @override
  State<AiChatScrollView> createState() => _AiChatScrollViewState();
}

class _AiChatScrollViewState extends State<AiChatScrollView> {
  late final ScrollController _scrollController;
  late final ValueNotifier<double> _fillerHeight;

  // Anchor state
  bool _anchorActive = false;
  int _anchorIndex = -1;
  double _lastMaxScrollExtent = 0.0;
  bool _fillerUpdateScheduled = false;
  final GlobalKey _anchorKey = GlobalKey();

  // Keyboard compensation state
  double _lastViewportDimension = 0.0;

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

  void _onControllerChanged() {
    if (widget.controller.isStreaming) {
      final anchorIdx = widget.itemCount - 1;

      // setState to apply the GlobalKey to the anchor item in the next build.
      setState(() {
        _anchorIndex = anchorIdx;
      });

      // Schedule the anchor jump for after the rebuild+layout.
      // The item may or may not be visible at this point:
      // - If it's visible (within the current scroll viewport), the GlobalKey
      //   will be attached after the rebuild and we can measure it directly.
      // - If it's outside the lazy render window, we need to scroll there first.
      //
      // Strategy: First scroll to the bottom (ensuring the last item is in the
      // render tree), then in the next postFrameCallback, measure and set filler,
      // then in the next frame, execute the final jump.
      //
      // To avoid "dead frames" (frames that don't schedule new frames because
      // jumpTo is a no-op), we use scheduleFrame() after setting filler to
      // ensure the layout update triggers a frame.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _scrollToBottomForMeasurement();
      });
    } else {
      // onResponseComplete
      setState(() {
        _anchorActive = false;
        _anchorIndex = -1;
      });
    }
  }

  /// Phase 1: Scroll to the bottom so the anchor item is in the render tree.
  /// Then schedule Phase 2 for measurement and filler setup.
  void _scrollToBottomForMeasurement() {
    if (!mounted || !_scrollController.hasClients) return;

    final pos = _scrollController.position;

    // Jump to the current maxScrollExtent to bring the last item into view.
    // If the item is already visible (maxScrollExtent = 0), this is a no-op,
    // but the item should already be attached to the GlobalKey from the setState rebuild.
    if (pos.maxScrollExtent > pos.pixels) {
      _scrollController.jumpTo(pos.maxScrollExtent);
      // jumpTo triggers a scroll update notification, which schedules a frame.
      // Register Phase 2 to fire after that frame.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _measureAndSetFiller();
      });
    } else {
      // Item is already visible (or maxScrollExtent <= pixels).
      // We can measure immediately in the next postFrameCallback.
      // But we need to ensure a frame is drawn so layout is fresh.
      // Force a frame schedule.
      SchedulerBinding.instance.scheduleFrame();
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _measureAndSetFiller();
      });
    }
  }

  /// Phase 2: Measure the anchor item height and set the initial filler.
  /// Then schedule Phase 3 for the final jump.
  void _measureAndSetFiller() {
    if (!mounted || !_scrollController.hasClients) return;

    final pos = _scrollController.position;
    final viewportDimension = pos.viewportDimension;

    // Read anchor item height via GlobalKey.
    final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
    final sentMsgHeight = box?.size.height ?? 60.0;

    // Set filler: viewportDimension - sentMsgHeight.
    // Derivation:
    //   target (desired pixels) = total_content_without_filler - sentMsgHeight
    //                           = original_maxScrollExtent + viewportDimension - sentMsgHeight
    //   new_maxScrollExtent = original_maxScrollExtent + filler
    //   filler = viewportDimension - sentMsgHeight
    //   => new_maxScrollExtent = original_maxScrollExtent + viewportDimension - sentMsgHeight
    //                          = target
    //   => jump to new_maxScrollExtent
    final initialFiller = math.max(0.0, viewportDimension - sentMsgHeight);
    _fillerHeight.value = initialFiller;

    // The ValueNotifier update schedules a rebuild of the FillerSliver,
    // but we need the layout to complete before reading the updated
    // maxScrollExtent. Schedule a frame and then do the final jump.
    // Since _fillerHeight.value changed, Flutter will schedule a rebuild
    // automatically (via ValueListenableBuilder). We add a postFrameCallback
    // for after that rebuild+layout.
    //
    // Also force a frame if the content fits entirely (maxScrollExtent stays 0):
    // in that case, the filler update causes a layout change but may not
    // schedule a new animation frame on its own in test mode.
    SchedulerBinding.instance.scheduleFrame();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _executeAnchorJump();
    });
  }

  /// Phase 3: Execute the final anchor jump using the updated maxScrollExtent.
  void _executeAnchorJump() {
    if (!mounted || !_scrollController.hasClients) return;

    final pos = _scrollController.position;

    // After Phase 2 set filler = viewportDimension - sentMsgHeight, the
    // new maxScrollExtent = original_maxScrollExtent + filler = target.
    // Jumping to maxScrollExtent places the anchor item's top at the viewport top.
    final target = pos.maxScrollExtent.clamp(
      pos.minScrollExtent,
      pos.maxScrollExtent,
    );

    _anchorActive = true;
    _scrollController.jumpTo(target);
    _lastMaxScrollExtent = _scrollController.position.maxScrollExtent;
    _lastViewportDimension = _scrollController.position.viewportDimension;
  }

  // ——— Filler recomputation ————————————————————————————————————————————————

  void _onScrollChanged() {
    // Always track isAtBottom, regardless of anchor state.
    if (_scrollController.hasClients) {
      final pos = _scrollController.position;
      final atBottom =
          pos.maxScrollExtent - pos.pixels <= widget.controller.atBottomThreshold;
      widget.controller.updateIsAtBottom(atBottom);
    }

    if (!_anchorActive || !_scrollController.hasClients) return;
    if (_fillerUpdateScheduled) return;
    _fillerUpdateScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _fillerUpdateScheduled = false;
      _recomputeFiller();
    });
  }

  void _recomputeFiller() {
    if (!_anchorActive || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    _lastViewportDimension = pos.viewportDimension; // keep current for keyboard detection
    final growth = pos.maxScrollExtent - _lastMaxScrollExtent;
    if (growth > 0) {
      _fillerHeight.value = math.max(0.0, _fillerHeight.value - growth);
      _lastMaxScrollExtent = pos.maxScrollExtent;
    }
  }

  // ——— Keyboard compensation ———————————————————————————————————————————————

  /// Called when [ScrollMetricsNotification] reports a new [viewportDimension]
  /// while the anchor is active. Adjusts the filler by the delta so the anchored
  /// message remains at the top of the visible area.
  ///
  /// - delta < 0: viewport shrank (soft keyboard opened) → filler shrinks.
  /// - delta > 0: viewport grew (soft keyboard closed) → filler grows.
  ///
  /// Filler is clamped to 0.0 to prevent negative values when the response
  /// already exceeds the visible area.
  void _onViewportDimensionChanged(double newViewportDimension) {
    final delta = newViewportDimension - _lastViewportDimension;
    _lastViewportDimension = newViewportDimension;

    // delta > 0 means viewport grew (keyboard closed) -> filler grows
    // delta < 0 means viewport shrank (keyboard opened) -> filler shrinks
    _fillerHeight.value = math.max(0.0, _fillerHeight.value + delta);

    // After filler change, re-anchor to keep sent message at viewport top.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      _scrollController.jumpTo(pos.maxScrollExtent);
      _lastMaxScrollExtent = pos.maxScrollExtent;
    });
  }

  // ——— Build ——————————————————————————————————————————————————————————————

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (notification) {
        if (notification.dragDetails != null && _anchorActive) {
          _anchorActive = false;
        }
        return false;
      },
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (notification) {
          final currentVD = notification.metrics.viewportDimension;
          if (_anchorActive &&
              _lastViewportDimension > 0.0 &&
              currentVD != _lastViewportDimension) {
            _onViewportDimensionChanged(currentVD);
          }
          _onScrollChanged();
          return false;
        },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverList.builder(
              itemCount: widget.itemCount,
              itemBuilder: (context, index) {
                final child = widget.itemBuilder(context, index);
                if (index == _anchorIndex) {
                  return KeyedSubtree(key: _anchorKey, child: child);
                }
                return child;
              },
            ),
            SliverToBoxAdapter(
              child: FillerSliver(fillerHeight: _fillerHeight),
            ),
          ],
        ),
      ),
    );
  }
}
