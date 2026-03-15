import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Controls scroll behavior for an AI chat interface.
///
/// Attach to an [AiChatScrollView] by passing this controller to its
/// constructor. The controller is inert until the widget mounts.
///
/// All methods are safe to call before the widget is mounted — they no-op
/// gracefully rather than throwing.
///
/// ## Typical usage
///
/// ```dart
/// final controller = AiChatScrollController();
///
/// // In your widget tree:
/// AiChatScrollView(
///   controller: controller,
///   child: YourMessageList(),
/// );
///
/// // When the user sends a message:
/// controller.onUserMessageSent();
///
/// // When the AI finishes streaming:
/// controller.onResponseComplete();
///
/// // When done:
/// controller.dispose();
/// ```
class AiChatScrollController extends ChangeNotifier {
  ScrollController? _scrollController;

  /// Attaches this controller to the [ScrollController] owned by
  /// [AiChatScrollView]. Called automatically during widget initialization.
  ///
  /// Must only be called once — asserts that no controller is already attached.
  /// Call [detach] before attaching a new controller.
  void attach(ScrollController scrollController) {
    assert(
      _scrollController == null,
      'AiChatScrollController is already attached. Call detach() first.',
    );
    _scrollController = scrollController;
  }

  /// Detaches from the [ScrollController]. Called automatically when
  /// [AiChatScrollView] is disposed.
  ///
  /// Safe to call even if not currently attached.
  void detach() {
    _scrollController = null;
  }

  /// Triggers the top-anchor behavior after the user sends a message.
  ///
  /// Call this after adding the user's message to your message list.
  /// Safe to call before the widget is mounted — no-ops gracefully.
  ///
  /// Also notifies listeners, allowing the widget tree to react to the
  /// message-sent event.
  void onUserMessageSent() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_scrollController == null || !_scrollController!.hasClients) return;
      // Phase 3 will implement the anchor jump here.
    });
    notifyListeners();
  }

  /// Signals that the AI response has finished streaming.
  ///
  /// After this call, the package stops maintaining the anchor position
  /// and the user can scroll freely.
  ///
  /// Also notifies listeners, allowing the widget tree to react to the
  /// response-complete event.
  void onResponseComplete() {
    // Phase 3 will clear streaming state here.
    notifyListeners();
  }

  @override
  void dispose() {
    _scrollController = null;
    super.dispose();
  }
}
