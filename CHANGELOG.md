## 0.1.0

- `AiChatScrollController` with `onUserMessageSent()` and `onResponseComplete()` lifecycle methods
- `AiChatScrollView` widget with `itemBuilder`/`itemCount` builder API
- Top-anchor-on-send: user's message snaps to viewport top when sent
- Streaming filler: dynamic space below AI response keeps anchor stable during streaming
- User drag cancellation: dragging during streaming cancels managed scroll
- Zero runtime dependencies (Flutter SDK only)
- Supports iOS (bouncing) and Android (clamping) scroll physics via ambient ScrollConfiguration
