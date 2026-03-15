/// AI-chat-optimized scroll behavior for Flutter.
///
/// This library provides [AiChatScrollController] and [AiChatScrollView]
/// to implement the top-anchor-on-send pattern: when a user sends a message,
/// it snaps to the top of the viewport and the AI response grows below.
library ai_chat_scroll;

export 'src/controller/ai_chat_scroll_controller.dart';
export 'src/widgets/ai_chat_scroll_view.dart';
