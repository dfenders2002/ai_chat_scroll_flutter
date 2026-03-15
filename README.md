# ai_chat_scroll

AI-chat-optimized scroll behavior for Flutter. Anchors the user's sent message at the top of the viewport while the AI response streams below.

## Problem

Auto-scrolling during AI response streaming constantly moves the chat list away from the content users care about. As each token arrives, the list jumps to the bottom — disorienting the user and making it hard to follow the conversation.

## Solution

`ai_chat_scroll` implements a top-anchor-on-send pattern. When the user sends a message, that message snaps to the top of the viewport. The AI response grows below it. A dynamic filler sliver absorbs the incoming content so the viewport stays locked in place — no jumping, no auto-scroll. The user can drag at any time to regain manual control.

## Installation

```sh
flutter pub add ai_chat_scroll
```

## Quick Start

```dart
import 'package:ai_chat_scroll/ai_chat_scroll.dart';
import 'package:flutter/material.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = AiChatScrollController();
  final _messages = <String>[];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onUserSend(String text) {
    setState(() => _messages.add(text));

    // Snaps the sent message to the top of the viewport
    // and begins tracking the AI response below it.
    _controller.onUserMessageSent();

    // ... trigger your AI response here ...
  }

  void _onAiResponseComplete() {
    // Releases the anchor so the user can scroll freely.
    _controller.onResponseComplete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AiChatScrollView(
        controller: _controller,
        itemCount: _messages.length,
        itemBuilder: (context, index) => ListTile(
          title: Text(_messages[index]),
        ),
      ),
    );
  }
}
```

## How It Works

- When `onUserMessageSent()` is called, the sent message snaps to the top of the viewport.
- A dynamic filler sliver sits below the message list. As the AI response grows, the filler shrinks by the same amount, keeping the anchor stable with no scroll movement.
- If the user drags the list during streaming, the anchor is cancelled immediately and the user scrolls freely.
- No auto-scroll occurs during streaming — the viewport only moves when the user initiates it.

## API Reference

### AiChatScrollController

| Method / Property | Description |
|---|---|
| `onUserMessageSent()` | Call after adding the user's message to your list. Snaps the message to the viewport top and starts streaming mode. |
| `onResponseComplete()` | Call when the AI finishes streaming. Releases the anchor. |
| `isStreaming` | `true` while anchor mode is active (between `onUserMessageSent` and `onResponseComplete`). |
| `dispose()` | Releases resources. Call in your widget's `dispose()`. |

### AiChatScrollView

| Parameter | Type | Description |
|---|---|---|
| `controller` | `AiChatScrollController` | The controller that drives anchor scroll behavior. |
| `itemBuilder` | `IndexedWidgetBuilder` | Called to build each message item. |
| `itemCount` | `int` | Total number of message items. |

Pass messages in chronological order (index 0 = oldest, last index = newest). The widget renders top-to-bottom, producing the conventional newest-at-bottom chat layout.

## Requirements

- Flutter >= 3.22.0
- Zero runtime dependencies (Flutter SDK only)
