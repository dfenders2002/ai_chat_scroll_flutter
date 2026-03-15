# ai_chat_scroll

AI-chat-optimized scroll behavior for Flutter. Anchors the user's message at the top of the viewport while the AI response streams below.

> **Note:** This package is under active development. Phase 1 (controller foundation) is complete. Full scroll behavior will be available in a later release.

## Overview

When a user sends a message in an AI chat interface, `ai_chat_scroll` snaps that message to the top of the viewport and keeps it anchored there while the AI response grows below — the user is never disoriented or auto-scrolled away.

## Usage

```dart
final controller = AiChatScrollController();

AiChatScrollView(
  controller: controller,
  child: YourMessageList(),
)

// When the user sends a message:
controller.onUserMessageSent();

// When the AI finishes responding:
controller.onResponseComplete();
```

## Status

- Phase 1: Controller foundation — complete
- Phase 2: Sliver composition — planned
- Phase 3: Streaming anchor behavior — planned
- Phase 4: Polish and publishing — planned
