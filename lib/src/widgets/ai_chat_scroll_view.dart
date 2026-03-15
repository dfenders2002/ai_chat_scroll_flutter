import 'package:flutter/widgets.dart';

import '../controller/ai_chat_scroll_controller.dart';

/// A wrapper widget that connects [AiChatScrollController] to a scrollable
/// message list.
///
/// Wrap your message list with this widget and pass the same
/// [AiChatScrollController] instance that your screen uses.
///
/// This widget owns an internal [ScrollController] that is attached to the
/// [AiChatScrollController] on mount and detached on dispose. You do not
/// need to manage the [ScrollController] directly.
///
/// ## Example
///
/// ```dart
/// AiChatScrollView(
///   controller: myAiChatScrollController,
///   child: ListView.builder(
///     itemCount: messages.length,
///     itemBuilder: (context, index) => MessageTile(messages[index]),
///   ),
/// )
/// ```
///
/// > **Note:** The [child] API is a Phase 1 stub. Phase 2 will replace this
/// > with a sliver-based builder API for correct top-anchor composition.
class AiChatScrollView extends StatefulWidget {
  /// Creates an [AiChatScrollView].
  ///
  /// Both [controller] and [child] are required.
  const AiChatScrollView({
    super.key,
    required this.controller,
    required this.child,
  });

  /// The [AiChatScrollController] that drives anchor scroll behavior.
  ///
  /// The same controller instance must be used to call [AiChatScrollController.onUserMessageSent]
  /// and [AiChatScrollController.onResponseComplete].
  final AiChatScrollController controller;

  /// The child widget (your message list).
  ///
  /// In Phase 2, this will be replaced with a builder API for sliver
  /// composition and correct top-anchor layout.
  final Widget child;

  @override
  State<AiChatScrollView> createState() => _AiChatScrollViewState();
}

class _AiChatScrollViewState extends State<AiChatScrollView> {
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    widget.controller.attach(_scrollController);
  }

  @override
  void dispose() {
    widget.controller.detach();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Phase 1 stub: pass-through.
    // Phase 2 replaces this with CustomScrollView + SliverList + FillerSliver.
    return widget.child;
  }
}
