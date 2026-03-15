import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../controller/ai_chat_scroll_controller.dart';
import 'filler_sliver.dart';

/// A scrollable view for AI chat interfaces with anchor-on-send behavior.
///
/// ## Chat gravity
///
/// Messages gravity-anchor to the bottom of the viewport. Few messages
/// appear at the bottom with space above, like Claude and ChatGPT.
///
/// ## Anchor behavior
///
/// When [AiChatScrollController.onUserMessageSent] is called, the viewport
/// snaps so the sent message is at the top. The AI response streams below it
/// and a dynamic filler fills the remaining viewport space. The user cannot
/// scroll past the filler — only iOS bounce/stretch at the edge.
///
/// Pass messages in chronological order (index 0 = oldest).
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
  late final ValueNotifier<double> _topSpacerHeight;

  // Anchor state
  bool _anchorActive = false;
  int _anchorIndex = -1;
  final GlobalKey _anchorKey = GlobalKey();

  /// The scroll offset of content above the anchor item. Recorded at anchor
  /// jump time and constant during the anchor lifecycle. Used by the
  /// self-correcting filler formula.
  double _contentAboveAnchor = 0.0;

  // Track previous itemCount for auto-scroll
  int _previousItemCount = 0;

  @override
  void initState() {
    super.initState();
    _fillerHeight = ValueNotifier(0.0);
    _topSpacerHeight = ValueNotifier(0.0);
    _scrollController = ScrollController();
    _scrollController.addListener(_onScrollChanged);
    widget.controller.attach(_scrollController);
    widget.controller.addListener(_onControllerChanged);
    _previousItemCount = widget.itemCount;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      _updateTopSpacer();
      _scrollToBottom();
    });
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

    if (widget.itemCount != _previousItemCount) {
      _previousItemCount = widget.itemCount;
      if (!_anchorActive && !widget.controller.isStreaming) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          _updateTopSpacer();
          final pos = _scrollController.position;
          final nearBottom = pos.maxScrollExtent - pos.pixels <=
              widget.controller.atBottomThreshold + 100;
          if (nearBottom) {
            _scrollToBottom();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    widget.controller.detach();
    _scrollController.removeListener(_onScrollChanged);
    _topSpacerHeight.dispose();
    _fillerHeight.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ——— Top spacer (chat gravity) ——————————————————————————————————————————

  void _updateTopSpacer() {
    if (!mounted || !_scrollController.hasClients) return;
    if (_anchorActive || widget.controller.isStreaming) {
      _topSpacerHeight.value = 0.0;
      return;
    }

    final pos = _scrollController.position;
    final viewport = pos.viewportDimension;
    final totalContent = pos.maxScrollExtent + viewport;
    final currentSpacer = _topSpacerHeight.value;
    final currentFiller = _fillerHeight.value;
    final messageContent = totalContent - currentSpacer - currentFiller;
    _topSpacerHeight.value = math.max(0.0, viewport - messageContent);
  }

  void _scrollToBottom() {
    if (!mounted || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent > 0) {
      _scrollController.jumpTo(pos.maxScrollExtent);
    }
  }

  // ——— Anchor lifecycle ——————————————————————————————————————————————————

  void _onControllerChanged() {
    if (widget.controller.isStreaming) {
      // Defer to AFTER parent rebuilds with new itemCount.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;

        // Clear spacers from previous state.
        _topSpacerHeight.value = 0.0;
        _fillerHeight.value = 0.0;

        final anchorIdx = widget.itemCount - 1;
        setState(() {
          _anchorIndex = anchorIdx;
        });

        // After rebuild (GlobalKey attached), measure and anchor.
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _performAnchorJump();
        });
      });
    } else {
      // onResponseComplete — stop managing scroll. Filler persists so layout
      // stays: user msg at top, AI response below, filler fills the rest.
      setState(() {
        _anchorActive = false;
        _anchorIndex = -1;
      });
    }
  }

  void _performAnchorJump() {
    if (!mounted || !_scrollController.hasClients) return;

    final pos = _scrollController.position;

    // Scroll to bottom to ensure anchor item is in the render tree.
    if (pos.maxScrollExtent > pos.pixels) {
      _scrollController.jumpTo(pos.maxScrollExtent);
    }

    SchedulerBinding.instance.scheduleFrame();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;

      final box = _anchorKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) {
        _performAnchorJump(); // Retry if not rendered.
        return;
      }

      final pos = _scrollController.position;
      final viewport = pos.viewportDimension;
      final anchorHeight = box.size.height;

      // Set filler = viewport - anchorHeight. This makes:
      // totalContent = contentAboveAnchor + anchorHeight + filler
      //              = contentAboveAnchor + viewport
      // maxScrollExtent = contentAboveAnchor
      // At maxScrollExtent: anchor is at viewport top. ✓
      _fillerHeight.value = math.max(0.0, viewport - anchorHeight);

      // After filler layout update, jump to final position.
      SchedulerBinding.instance.scheduleFrame();
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final pos = _scrollController.position;

        _anchorActive = true;
        _contentAboveAnchor = pos.maxScrollExtent;
        _scrollController.jumpTo(pos.maxScrollExtent);
      });
    });
  }

  // ——— Filler recomputation (self-correcting absolute formula) ———————————

  void _recomputeFiller() {
    if (!_anchorActive || !_scrollController.hasClients) return;

    final pos = _scrollController.position;

    // Self-correcting formula:
    // correctFiller = currentFiller + contentAboveAnchor - maxScrollExtent
    //
    // When AI response grows by N, maxScrollExtent grows by N.
    // Formula: filler -= N. After filler layout update, maxScrollExtent
    // shrinks back. Formula re-evaluates to the same value (stable).
    final currentFiller = _fillerHeight.value;
    final correctFiller =
        math.max(0.0, currentFiller + _contentAboveAnchor - pos.maxScrollExtent);

    if ((currentFiller - correctFiller).abs() > 0.5) {
      _fillerHeight.value = correctFiller;
    }
  }

  // ——— Scroll tracking ——————————————————————————————————————————————————

  void _onScrollChanged() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final atBottom =
        pos.maxScrollExtent - pos.pixels <= widget.controller.atBottomThreshold;
    widget.controller.updateIsAtBottom(atBottom);

    // Recompute filler during anchor.
    if (_anchorActive) {
      _recomputeFiller();
    }
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
          if (_anchorActive) {
            _recomputeFiller();
          }
          _onScrollChanged();
          return false;
        },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            // Top spacer — pushes messages to bottom (chat gravity).
            SliverToBoxAdapter(
              child: FillerSliver(fillerHeight: _topSpacerHeight),
            ),
            // Message list.
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
            // Bottom filler — maintains anchor position during streaming.
            SliverToBoxAdapter(
              child: FillerSliver(fillerHeight: _fillerHeight),
            ),
          ],
        ),
      ),
    );
  }
}
