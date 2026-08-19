import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const LocalAiApp());
}

class LocalAiApp extends StatelessWidget {
  const LocalAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local GGUF AI Runner',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
      ),
      home: const MainChatScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// 세션 모델
class ChatSession {
  String id;
  String title;
  String systemPrompt;
  String? avatarPath;
  List<Map<String, String>> messages;

  ChatSession({
    required this.id,
    required this.title,
    this.systemPrompt = "당신은 유용한 AI 비서입니다.",
    this.avatarPath,
    List<Map<String, String>>? messages,
  }) : messages = messages ?? [];
}

class MainChatScreen extends StatefulWidget {
  const MainChatScreen({super.key});

  @override
  State<MainChatScreen> createState() => _MainChatScreenState();
}

class _MainChatScreenState extends State<MainChatScreen> {
  String? selectedModelPath;
  List<ChatSession> sessions = [];
  int currentSessionIndex = 0;

  final TextEditingController _messageController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // 기본 세션 1개 생성
    _createNewSession();
  }

  void _createNewSession() {
    setState(() {
      final newSession = ChatSession(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        title: '새로운 대화 ${sessions.length + 1}',
      );
      sessions.add(newSession);
      currentSessionIndex = sessions.length - 1;
    });
  }

  // 3. 앱 전체 설정: 내 저장소에서 GGUF 모델 파일 로드
  Future<void> _pickModelFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gguf', 'bin'],
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        selectedModelPath = result.files.single.path;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('모델 로드 완료: ${result.files.single.name}')),
      );
    }
  }

  // 2. 세션 AI 프로필 이미지 변경
  Future<void> _pickAvatarImage(ChatSession session) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        session.avatarPath = image.path;
      });
    }
  }

  // 2. 세션 설정 수정 창 (프로필, 기본 프롬프트)
  void _openSessionSettings(ChatSession session) {
    final promptController = TextEditingController(text: session.systemPrompt);
    final titleController = TextEditingController(text: session.title);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('세션 AI 설정'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () async {
                  await _pickAvatarImage(session);
                  (context as Element).markNeedsBuild();
                },
                child: CircleAvatar(
                  radius: 35,
                  backgroundImage: session.avatarPath != null
                      ? FileImage(File(session.avatarPath!))
                      : null,
                  child: session.avatarPath == null
                      ? const Icon(Icons.add_a_photo, size: 30)
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              const Text('프로필 사진 변경 (터치)', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: '세션 이름', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: promptController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '기본 시스템 프롬프트', border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                session.title = titleController.text;
                session.systemPrompt = promptController.text;
              });
              Navigator.pop(context);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  void _sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    if (selectedModelPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('메시지를 보내기 전 설정에서 GGUF 모델을 선택해주세요.')),
      );
      return;
    }

    final text = _messageController.text;
    _messageController.clear();

    setState(() {
      final currentSession = sessions[currentSessionIndex];
      currentSession.messages.add({'role': 'user', 'text': text});

      // 추론 시뮬레이션 및 로컬 GGUF 연동 수신 응답
      currentSession.messages.add({
        'role': 'ai',
        'text': '[로컬 AI 응답]: 모델(${selectedModelPath!.split('/').last}) 기반 처리 결과입니다.\n\n프롬프트: "${currentSession.systemPrompt}" 적용됨.'
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentSession = sessions.isNotEmpty ? sessions[currentSessionIndex] : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(currentSession?.title ?? 'GGUF AI Runner'),
        actions: [
          if (currentSession != null)
            IconButton(
              icon: const Icon(Icons.tune),
              onPressed: () => _openSessionSettings(currentSession),
            ),
          IconButton(
            icon: const Icon(Icons.folder_open),
            onPressed: _pickModelFile,
            tooltip: 'GGUF 모델 선택',
          ),
        ],
      ),
      // 1. 멀티 세션 드로어 (사이드바)
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.deepPurple),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('GGUF Local AI', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('온디바이스 로컬 실행기', style: TextStyle(fontSize: 14)),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('새 세션 추가'),
              onTap: () {
                _createNewSession();
                Navigator.pop(context);
              },
            ),
            const Divider(),
            ...List.generate(sessions.length, (index) {
              final s = sessions[index];
              return ListTile(
                leading: CircleAvatar(
                  backgroundImage: s.avatarPath != null ? FileImage(File(s.avatarPath!)) : null,
                  child: s.avatarPath == null ? const Icon(Icons.smart_toy, size: 20) : null,
                ),
                title: Text(s.title),
                selected: index == currentSessionIndex,
                onTap: () {
                  setState(() => currentSessionIndex = index);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
      body: Column(
        children: [
          // 모델 미선택 시 경고 바
          if (selectedModelPath == null)
            Container(
              color: Colors.amber.shade900,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: const Row(
                children: [
                  Icon(Icons.warning, size: 20),
                  SizedBox(width: 8),
                  Expanded(child: Text('상단 폴더 아이콘을 눌러 GGUF 모델을 선택해주세요.', style: TextStyle(fontSize: 13))),
                ],
              ),
            ),
          // 채팅 목록
          Expanded(
            child: currentSession == null || currentSession.messages.isEmpty
                ? Center(
                    child: Text(
                      '대화를 시작해 보세요!\n현재 시스템 프롬프트: "${currentSession?.systemPrompt}"',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: currentSession.messages.length,
                    itemBuilder: (context, index) {
                      final msg = currentSession.messages[index];
                      final isUser = msg['role'] == 'user';
                      return Align(
                        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isUser ? Colors.deepPurple : Colors.grey.shade800,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                          child: Text(msg['text'] ?? ''),
                        ),
                      );
                    },
                  ),
          ),
          // 입력창
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: '메시지를 입력하세요...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.send),
                  color: Colors.deepPurpleAccent,
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
