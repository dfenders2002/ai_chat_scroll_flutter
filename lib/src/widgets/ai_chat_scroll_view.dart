import 'package:flutter/widgets.dart';

import '../controller/ai_chat_scroll_controller.dart';
import 'filler_sliver.dart';

/// A scrollable view for AI chat interfaces that composes a message list and
/// a dynamic filler sliver.
///
/// Pass [itemBuilder] and [itemCount] to supply your message items. This widget
/// owns the [CustomScrollView] and internal [ScrollController] so it can
/// compose slivers (message list + filler) required for the top-anchor-on-send
/// behavior implemented in Phase 3.
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
  ///
  /// [controller], [itemBuilder], and [itemCount] are all required.
  const AiChatScrollView({
    super.key,
    required this.controller,
    required this.itemBuilder,
    required this.itemCount,
  });

  /// The [AiChatScrollController] that drives anchor scroll behavior.
  ///
  /// The same controller instance must be used to call
  /// [AiChatScrollController.onUserMessageSent] and
  /// [AiChatScrollController.onResponseComplete].
  final AiChatScrollController controller;

  /// Called to build each message item in the list.
  ///
  /// The index is zero-based. Pass messages in chronological order (index 0 =
  /// oldest, last index = newest) for a conventional newest-at-bottom chat layout.
  final IndexedWidgetBuilder itemBuilder;

  /// The total number of message items to display.
  final int itemCount;

  @override
  State<AiChatScrollView> createState() => _AiChatScrollViewState();
}

class _AiChatScrollViewState extends State<AiChatScrollView> {
  late final ScrollController _scrollController;
  late final ValueNotifier<double> _fillerHeight;

  @override
  void initState() {
    super.initState();
    _fillerHeight = ValueNotifier(0.0);
    _scrollController = ScrollController();
    widget.controller.attach(_scrollController);
  }

  @override
  void dispose() {
    widget.controller.detach();
    _fillerHeight.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        SliverList.builder(
          itemCount: widget.itemCount,
          itemBuilder: widget.itemBuilder,
        ),
        SliverToBoxAdapter(
          child: FillerSliver(fillerHeight: _fillerHeight),
        ),
      ],
    );
  }
}
