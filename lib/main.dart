import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
// llama_cpp_dart 패키지를 사용해 C++ NDK 바인딩으로 로컬 GGUF 모델을 구동합니다.
import 'package:llama_cpp_dart/llama_cpp_dart.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const LocalGgufAiApp());
}

class LocalGgufAiApp extends StatelessWidget {
  const LocalGgufAiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local GGUF AI Runner',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF111827),
        primaryColor: const Color(0xFF2563EB),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2563EB),
          secondary: Color(0xFF3B82F6),
          surface: Color(0xFF1F2937),
        ),
      ),
      home: const ChatHomeScreen(),
    );
  }
}

// 모델 설정 정보
class ModelConfig {
  String? modelPath;
  String? modelName;
  int maxTokens;
  double temperature;
  int threads;

  ModelConfig({
    this.modelPath,
    this.modelName,
    this.maxTokens = 512,
    this.temperature = 0.7,
    this.threads = 4,
  });
}

// AI 세션 클래스
class ChatSession {
  final String id;
  String name;
  String? avatarPath;
  String systemPrompt;
  List<Map<String, String>> messages;

  ChatSession({
    required this.id,
    required this.name,
    this.avatarPath,
    required this.systemPrompt,
    required this.messages,
  });
}

class ChatHomeScreen extends StatefulWidget {
  const ChatHomeScreen({super.key});

  @override
  State<ChatHomeScreen> createState() => _ChatHomeScreenState();
}

class _ChatHomeScreenState extends State<ChatHomeScreen> {
  final List<ChatSession> _sessions = [];
  String? _currentSessionId;
  final ModelConfig _config = ModelConfig();
  
  LlamaProcessor? _llamaProcessor;
  bool _isGenerating = false;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _createDefaultSession();
  }

  void _createDefaultSession() {
    final defaultSession = ChatSession(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: '기본 AI 어시스턴트',
      systemPrompt: '당신은 스마트폰에서 오프라인으로 작동하는 유용한 온디바이스 AI 어시스턴트입니다.',
      messages: [
        {
          'sender': 'ai',
          'text': '안녕하세요! 전체 설정에서 내 스마트폰 저장소의 .gguf 모델 파일을 로드하면 오프라인 네이티브 추론을 시작할 수 있습니다.'
        }
      ],
    );
    setState(() {
      _sessions.add(defaultSession);
      _currentSessionId = defaultSession.id;
    });
  }

  ChatSession? get _currentSession {
    if (_currentSessionId == null) return null;
    return _sessions.firstWhere((s) => s.id == _currentSessionId, orElse: () => _sessions.first);
  }

  // GGUF 모델 로드 및 Llama 엔진 초기화
  Future<void> _loadModelFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['gguf', 'bin'],
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final name = result.files.single.name;

      setState(() {
        _config.modelPath = path;
        _config.modelName = name;
      });

      // 기존 엔진 해제 후 새로 로드
      _llamaProcessor?.unload();
      
      try {
        final params = ModelParams()
          ..contextSize = 2048
          ..nGpuLayers = 0; // CPU 가속 설정

        _llamaProcessor = LlamaProcessor(path, params);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GGUF 모델이 성공적으로 로드되었습니다: $name')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('모델 로드 실패: $e')),
        );
      }
    }
  }

  // 메시지 전송 및 네이티브 온디바이스 추론
  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _currentSession == null || _isGenerating) return;

    final session = _currentSession!;
    _inputController.clear();

    setState(() {
      session.messages.add({'sender': 'user', 'text': text});
      session.messages.add({'sender': 'ai', 'text': ''}); // 스트리밍 응답용 빈 메시지
      _isGenerating = true;
    });

    _scrollToBottom();

    if (_config.modelPath == null || _llamaProcessor == null) {
      setState(() {
        session.messages.last['text'] = 
            '[경고] GGUF 모델이 선택되지 않았습니다. [전체 설정]에서 스마트폰에 다운로드된 .gguf 파일의 경로를 로드해주세요.';
        _isGenerating = false;
      });
      return;
    }

    try {
      // 프롬프트 조립 (System Prompt + User Input)
      final fullPrompt = "<|system|>\n${session.systemPrompt}\n<|user|>\n$text\n<|assistant|>\n";

      // Llama.cpp C++ 엔진 실시간 스트리밍 추론
      final stream = _llamaProcessor!.stream(
        fullPrompt,
        temperature: _config.temperature,
        maxTokens: _config.maxTokens,
      );

      await for (final token in stream) {
        setState(() {
          session.messages.last['text'] = session.messages.last['text']! + token;
        });
        _scrollToBottom();
      }
    } catch (e) {
      setState(() {
        session.messages.last['text'] = "추론 중 오류가 발생했습니다: $e";
      });
    } finally {
      setState(() {
        _isGenerating = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // 새 세션 추가 모달
  void _openNewSessionDialog() {
    final nameController = TextEditingController();
    final promptController = TextEditingController();
    String? selectedAvatarPath;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          title: const Text('새 AI 세션 생성', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () async {
                    final picker = ImagePicker();
                    final image = await picker.pickImage(source: ImageSource.gallery);
                    if (image != null) {
                      setModalState(() {
                        selectedAvatarPath = image.path;
                      });
                    }
                  },
                  child: CircleAvatar(
                    radius: 32,
                    backgroundColor: Colors.blue.withOpacity(0.2),
                    backgroundImage: selectedAvatarPath != null ? FileImage(File(selectedAvatarPath!)) : null,
                    child: selectedAvatarPath == null 
                        ? const Icon(Icons.add_a_photo, color: Colors.blue) 
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: '세션 이름',
                    hintText: '예: 코드 리뷰어, 캐릭터 AI',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: promptController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: '기본 시스템 프롬프트',
                    hintText: 'AI의 페르소나 지침을 입력하세요.',
                    border: OutlineInputBorder(),
                  ),
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
                if (nameController.text.trim().isEmpty) return;
                final newSession = ChatSession(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: nameController.text.trim(),
                  avatarPath: selectedAvatarPath,
                  systemPrompt: promptController.text.trim().isEmpty 
                      ? '당신은 온디바이스 AI입니다.' 
                      : promptController.text.trim(),
                  messages: [
                    {
                      'sender': 'ai',
                      'text': '${nameController.text.trim()} 세션이 생성되었습니다.'
                    }
                  ],
                );
                setState(() {
                  _sessions.insert(0, newSession);
                  _currentSessionId = newSession.id;
                });
                Navigator.pop(context);
              },
              child: const Text('생성'),
            ),
          ],
        ),
      ),
    );
  }

  // 전체 모델 설정 모달
  void _openSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          title: const Text('전체 모델 및 추론 설정', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('내 저장소 GGUF 모델 파일', style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await _loadModelFile();
                  setModalState(() {});
                },
                icon: const Icon(Icons.folder_open),
                label: Text(_config.modelName ?? '.gguf 파일 로드'),
              ),
              const SizedBox(height: 16),
              Text('최대 토큰수: ${_config.maxTokens}', style: const TextStyle(color: Colors.white)),
              Slider(
                value: _config.maxTokens.toDouble(),
                min: 128,
                max: 2048,
                divisions: 15,
                onChanged: (val) {
                  setModalState(() {
                    _config.maxTokens = val.toInt();
                  });
                },
              ),
              Text('Temperature: ${_config.temperature.toStringAsFixed(1)}', style: const TextStyle(color: Colors.white)),
              Slider(
                value: _config.temperature,
                min: 0.1,
                max: 1.5,
                divisions: 14,
                onChanged: (val) {
                  setModalState(() {
                    _config.temperature = val;
                  });
                },
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('완료'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _currentSession;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF030712),
        title: Row(
          children: [
            if (session?.avatarPath != null)
              CircleAvatar(
                radius: 16,
                backgroundImage: FileImage(File(session!.avatarPath!)),
              )
            else
              const CircleAvatar(
                radius: 16,
                backgroundColor: Colors.blue,
                child: Icon(Icons.bot, size: 18, color: Colors.white),
              ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                session?.name ?? 'Local AI',
                style: const TextStyle(fontSize: 16),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettingsDialog,
          ),
        ],
      ),
      drawer: Drawer(
        backgroundColor: const Color(0xFF030712),
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF1F2937)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      backgroundColor: Colors.blue,
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _openNewSessionDialog();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('새 세션 추가'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _sessions.length,
                itemBuilder: (context, index) {
                  final s = _sessions[index];
                  final isSelected = s.id == _currentSessionId;
                  return ListTile(
                    selected: isSelected,
                    selectedTileColor: Colors.blue.withOpacity(0.2),
                    leading: s.avatarPath != null
                        ? CircleAvatar(backgroundImage: FileImage(File(s.avatarPath!)))
                        : const CircleAvatar(child: Icon(Icons.bot)),
                    title: Text(s.name, style: const TextStyle(color: Colors.white)),
                    subtitle: Text(s.systemPrompt, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey)),
                    onTap: () {
                      setState(() {
                        _currentSessionId = s.id;
                      });
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_config.modelPath == null)
            Container(
              color: Colors.amber.withOpacity(0.15),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Colors.amber, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('GGUF 모델 파일이 설정되지 않았습니다.', style: TextStyle(color: Colors.amber, fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: _openSettingsDialog,
                    child: const Text('설정'),
                  )
                ],
              ),
            ),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: session?.messages.length ?? 0,
              itemBuilder: (context, index) {
                final msg = session!.messages[index];
                final isUser = msg['sender'] == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isUser ? Colors.blue : const Color(0xFF1F2937),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                    child: Text(
                      msg['text'] ?? '',
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            color: const Color(0xFF030712),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: '메시지 입력...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF1F2937),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: _isGenerating 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                      : const Icon(Icons.send, color: Colors.blue),
                  onPressed: _isGenerating ? null : _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
