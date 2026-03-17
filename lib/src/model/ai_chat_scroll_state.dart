/// The lifecycle state of an [AiChatScrollController].
///
/// Use [AiChatScrollController.scrollState] with a [ValueListenableBuilder]
/// to reactively rebuild UI when the scroll state changes.
enum AiChatScrollState {
  /// No message is being streamed and the scroll position is at the bottom.
  ///
  /// This is the initial state and the normal resting state after a response
  /// completes while the user is at the bottom.
  idleAtBottom,

  /// The user has sent a message and the AI response has not yet started.
  ///
  /// The controller enters this state on every [AiChatScrollController.onUserMessageSent]
  /// call, regardless of the previous state.
  submittedWaitingResponse,

  /// An AI response is streaming and the viewport is following (anchored) at
  /// the top of the last user message.
  ///
  /// The user has not scrolled away from the anchor position.
  streamingFollowing,

  /// An AI response is streaming but the user has scrolled away from the
  /// anchor position.
  ///
  /// The anchor is no longer maintained; the user is browsing history.
  streamingDetached,

  /// No message is being streamed and the scroll position is NOT at the bottom.
  ///
  /// The user is browsing earlier messages. The controller enters this state
  /// when [AiChatScrollController.onResponseComplete] is called while
  /// [AiChatScrollController.isAtBottom] is `false`.
  historyBrowsing,
}
