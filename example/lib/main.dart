import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ai_chat_scroll/ai_chat_scroll.dart';

void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'ai_chat_scroll Demo',
      home: ChatScreen(),
    );
  }
}

/// A single chat message.
class ChatMessage {
  ChatMessage({required this.text, required this.isUser});

  String text;
  final bool isUser;
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final AiChatScrollController _controller = AiChatScrollController();
  final TextEditingController _textController = TextEditingController();
  Timer? _streamTimer;
  bool _isStreaming = false;

  final List<ChatMessage> _messages = [
    ChatMessage(
      text: 'Welcome to the ai_chat_scroll demo!',
      isUser: false,
    ),
    ChatMessage(
      text: 'Try sending a message to see the anchor behavior.',
      isUser: false,
    ),
  ];

  static const String _cannedResponse =
      "That's a great question! The anchor-on-send pattern works by snapping "
      'your message to the top of the viewport when you send it. As this '
      'response streams in word by word, notice how your message stays fixed '
      'at the top while the text grows below. The filler space shrinks '
      'dynamically to maintain this position. You can try scrolling down '
      'manually during streaming to break the anchor. Pretty neat, right?';

  @override
  void dispose() {
    _streamTimer?.cancel();
    _controller.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final userText = _textController.text.trim();
    if (userText.isEmpty || _isStreaming) return;

    _textController.clear();

    // Step 1: Add ONLY the user message.
    setState(() {
      _messages.add(ChatMessage(text: userText, isUser: true));
    });

    // Step 2: Trigger anchor — this will anchor YOUR message at the top
    // of the viewport (it's the last item right now).
    _controller.onUserMessageSent();

    // Step 3: After a short delay, add the AI placeholder and start streaming.
    // The AI response appears BELOW your anchored message.
    Future.delayed(const Duration(milliseconds: 100), () {
      if (!mounted) return;

      setState(() {
        _messages.add(ChatMessage(text: '', isUser: false));
        _isStreaming = true;
      });

      // Stream canned response word by word.
      final words = _cannedResponse.split(' ');
      int wordIndex = 0;
      final aiMessage = _messages.last;

      _streamTimer =
          Timer.periodic(const Duration(milliseconds: 50), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (wordIndex < words.length) {
          setState(() {
            aiMessage.text = wordIndex == 0
                ? words[0]
                : '${aiMessage.text} ${words[wordIndex]}';
          });
          wordIndex++;
        } else {
          timer.cancel();
          _controller.onResponseComplete();
          setState(() {
            _isStreaming = false;
          });
        }
      });
    });
  }

  Widget _buildBubble(ChatMessage message) {
    final isUser = message.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFF3F51B5) : const Color(0xFFE0E0E0),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
        ),
        constraints: const BoxConstraints(maxWidth: 300),
        child: Text(
          message.text,
          style: TextStyle(
            color: isUser ? Colors.white : Colors.black87,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ai_chat_scroll Demo')),
      body: Column(
        children: [
          Expanded(
            child: AiChatScrollView(
              controller: _controller,
              itemCount: _messages.length,
              itemBuilder: (context, index) => _buildBubble(_messages[index]),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message…',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _isStreaming ? null : _sendMessage,
                    icon: const Icon(Icons.send),
                    color: const Color(0xFF3F51B5),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
