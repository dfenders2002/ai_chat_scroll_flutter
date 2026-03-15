import 'package:flutter/foundation.dart';
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
/// ## Scroll-to-bottom indicator
///
/// Listen to [isAtBottom] to know when to show or hide a "scroll to bottom"
/// floating action button or indicator:
///
/// ```dart
/// ValueListenableBuilder<bool>(
///   valueListenable: controller.isAtBottom,
///   builder: (context, atBottom, _) {
///     return atBottom ? const SizedBox.shrink() : MyScrollToBottomFab();
///   },
/// );
/// ```
///
/// Call [scrollToBottom] to animate the list back to the latest messages.
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
  /// Creates an [AiChatScrollController].
  ///
  /// [atBottomThreshold] — logical pixels from [ScrollPosition.maxScrollExtent]
  /// within which the user is considered "at the bottom". Defaults to 50.0.
  AiChatScrollController({this.atBottomThreshold = 50.0});

  ScrollController? _scrollController;

  /// Whether an AI response is currently streaming.
  ///
  /// Set to `true` by [onUserMessageSent] and `false` by [onResponseComplete].
  /// The [AiChatScrollView] listens to this via [addListener] to drive anchor
  /// behavior and filler recomputation.
  bool _streaming = false;

  /// Whether an AI response is currently streaming.
  bool get isStreaming => _streaming;

  /// The distance from [ScrollPosition.maxScrollExtent] (in logical pixels)
  /// within which the user is considered to be "at the bottom".
  ///
  /// Defaults to 50.0. Increase this to make the "at bottom" zone larger
  /// (e.g. so a position 80px from the bottom still counts as "at bottom").
  final double atBottomThreshold;

  final ValueNotifier<bool> _isAtBottom = ValueNotifier(true);

  /// Whether the scroll position is at (or near) the bottom of the list.
  ///
  /// Returns `true` when the distance from the current scroll position to
  /// [ScrollPosition.maxScrollExtent] is within [atBottomThreshold].
  ///
  /// Listen to this [ValueListenable] to show or hide a scroll-to-bottom
  /// indicator without rebuilding the entire widget tree.
  ValueListenable<bool> get isAtBottom => _isAtBottom;

  /// Updates the [isAtBottom] value. Called by [AiChatScrollView] when the
  /// scroll position changes.
  void updateIsAtBottom(bool value) {
    _isAtBottom.value = value;
  }

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
  /// Sets [isStreaming] to `true` and notifies listeners, allowing the widget
  /// tree to react by scheduling an anchor jump and setting up filler
  /// recomputation.
  void onUserMessageSent() {
    _streaming = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_scrollController == null || !_scrollController!.hasClients) return;
      // The actual anchor jump is performed by the widget state via its
      // listener. The postFrameCallback guard here is retained from Phase 1
      // to ensure scroll commands are safe to dispatch.
    });
    notifyListeners();
  }

  /// Signals that the AI response has finished streaming.
  ///
  /// After this call, the package stops maintaining the anchor position
  /// and the user can scroll freely.
  ///
  /// Sets [isStreaming] to `false` and notifies listeners, allowing the widget
  /// tree to clear anchor state.
  void onResponseComplete() {
    _streaming = false;
    notifyListeners();
  }

  /// Animates the scroll position to the bottom of the message list.
  ///
  /// Use this to implement a "scroll to bottom" button or FAB. Safe to call
  /// before the widget is mounted — no-ops gracefully.
  ///
  /// The scroll animation uses a 300 ms [Curves.easeOut] curve.
  /// [isAtBottom] will become `true` as the animation completes and the
  /// scroll listener detects the new position.
  void scrollToBottom() {
    if (_scrollController == null || !_scrollController!.hasClients) return;
    _scrollController!.animateTo(
      _scrollController!.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  /// Releases resources and detaches from any [ScrollController].
  ///
  /// Call this when the controller is no longer needed. After disposal,
  /// do not call any other methods on this controller.
  @override
  void dispose() {
    _isAtBottom.dispose();
    _scrollController = null;
    super.dispose();
  }
}
