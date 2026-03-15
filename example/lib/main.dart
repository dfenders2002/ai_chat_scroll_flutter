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
      title: 'ai_chat_scroll Example',
      home: ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final AiChatScrollController _controller = AiChatScrollController();
  final List<String> _messages = ['Hello!', 'How can I help you?'];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _sendMessage() {
    setState(() {
      _messages.add('User message ${_messages.length + 1}');
    });
    _controller.onUserMessageSent();

    // Simulate AI response
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _messages.add('AI response ${_messages.length + 1}');
        });
        _controller.onResponseComplete();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ai_chat_scroll Example')),
      body: AiChatScrollView(
        controller: _controller,
        child: ListView.builder(
          itemCount: _messages.length,
          itemBuilder: (context, index) => ListTile(
            title: Text(_messages[index]),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _sendMessage,
        child: const Icon(Icons.send),
      ),
    );
  }
}
