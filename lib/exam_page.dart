import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ExamPage extends StatefulWidget {
  const ExamPage({super.key, required this.userId});

  final int userId;

  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> {
  List<Map<String, dynamic>> topics = [];
  int? selectedTopicId;
  bool loadingTopics = true;
  String? topicsError;
  String? examError;
  bool examStarted = false;
  bool loading = false;
  bool submitted = false;
  bool _submitting = false;
  bool _submissionSaved = false;
  bool _checkingRelease = false;
  Map<String, dynamic>? _completedResult;
  String? _completionError;
  String? _releaseCheckError;
  int? currentResultId;

  List<Map<String, dynamic>> questions = [];
  final Map<int, String> answers = {};

  int currentIndex = 0;
  int remainingSeconds = 5 * 60;
  Timer? countdown;
  Timer? _resultReleaseTimer;

  // Web/Desktop: localhost.
  // Android emulator: 10.0.2.2.
  // Physical phone: replace with your computer's LAN IP address.
  String get apiBaseUrl {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return 'http://127.0.0.1:8000';
    }
    return 'http://10.0.2.2:8000';
  }

  @override
  void initState() {
    super.initState();
    loadTopics();
  }

  @override
  void dispose() {
    countdown?.cancel();
    _resultReleaseTimer?.cancel();
    super.dispose();
  }

  Future<void> loadTopics() async {
    setState(() {
      loadingTopics = true;
      topicsError = null;
    });

    try {
      final response = await http
          .get(Uri.parse('$apiBaseUrl/topics'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final decoded = jsonDecode(response.body);
      final List<dynamic> topicList;

      if (decoded is Map<String, dynamic> && decoded['topics'] is List) {
        topicList = decoded['topics'] as List<dynamic>;
      } else if (decoded is List) {
        topicList = decoded;
      } else {
        throw const FormatException('Unexpected topics response format.');
      }

      final loadedTopics = topicList
          .whereType<Map>()
          .map((topic) => Map<String, dynamic>.from(topic))
          .where((topic) => topic['topic_id'] is num)
          .toList();

      if (!mounted) return;

      setState(() {
        topics = loadedTopics;
        selectedTopicId = loadedTopics.isNotEmpty
            ? (loadedTopics.first['topic_id'] as num).toInt()
            : null;
        loadingTopics = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loadingTopics = false;
        topicsError = 'Could not load topics: $e';
      });
    }
  }

  String get selectedTopicName {
    for (final topic in topics) {
      if ((topic['topic_id'] as num).toInt() == selectedTopicId) {
        return topic['topic_name']?.toString() ?? 'Selected topic';
      }
    }
    return 'Selected topic';
  }

  Future<void> startExam() async {
    if (selectedTopicId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a topic first.')),
      );
      return;
    }

    setState(() {
      loading = true;
      questions = [];
      answers.clear();
      currentIndex = 0;
      submitted = false;
      currentResultId = null;
      _submissionSaved = false;
      _checkingRelease = false;
      _completedResult = null;
      _completionError = null;
      _releaseCheckError = null;
      _submitting = false;
      examStarted = false;
      examError = null;
    });

    try {
      final uri = Uri.parse(
        '$apiBaseUrl/questions',
      ).replace(queryParameters: {'topic_id': selectedTopicId.toString()});
      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception(
          'Failed to load questions: ${response.statusCode} '
          '${response.body}',
        );
      }

      final decoded = jsonDecode(response.body);

      final List<dynamic> allQuestions;

      if (decoded is List) {
        allQuestions = decoded;
      } else if (decoded is Map<String, dynamic> &&
          decoded['questions'] is List) {
        allQuestions = decoded['questions'] as List<dynamic>;
      } else {
        throw Exception('Unexpected API response format: ${response.body}');
      }

      final topicQuestions = allQuestions
          .where((item) => item is Map)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      if (!mounted) return;

      if (topicQuestions.isEmpty) {
        setState(() {
          loading = false;
          examError = 'No questions found for $selectedTopicName.';
        });
        return;
      }

      final questionIds = topicQuestions.map((question) {
        final questionId = question['question_id'];
        if (questionId is! num) {
          throw const FormatException(
            'A question did not include a valid question ID.',
          );
        }
        return questionId.toInt();
      }).toList();

      final startResponse = await http
          .post(
            Uri.parse('$apiBaseUrl/results/start'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': widget.userId,
              'topic_id': selectedTopicId,
              'question_ids': questionIds,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (startResponse.statusCode != 201) {
        throw Exception(
          'Could not record exam start: ${startResponse.statusCode} '
          '${startResponse.body}',
        );
      }

      final startData = jsonDecode(startResponse.body);
      if (startData is! Map<String, dynamic> ||
          startData['result_id'] is! num) {
        throw const FormatException('Invalid exam start response.');
      }

      setState(() {
        questions = topicQuestions;
        currentResultId = (startData['result_id'] as num).toInt();
        currentIndex = 0;
        examStarted = true;
        loading = false;
        remainingSeconds = 5 * 60;
      });

      startTimer();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
        examStarted = false;
        examError = 'Could not load questions: $e';
      });
    }
  }

  void startTimer() {
    countdown?.cancel();

    countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || submitted) {
        timer.cancel();
        return;
      }

      if (remainingSeconds <= 1) {
        setState(() => remainingSeconds = 0);
        timer.cancel();
        submitExam(timeExpired: true);
      } else {
        setState(() => remainingSeconds--);
      }
    });
  }

  String get formattedTime {
    final minutes = remainingSeconds ~/ 60;
    final seconds = remainingSeconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  void selectAnswer(String label) {
    if (submitted) return;

    setState(() {
      answers[currentIndex] = label;
    });
  }

  void nextQuestion() {
    if (currentIndex < questions.length - 1) {
      setState(() => currentIndex++);
    }
  }

  void previousQuestion() {
    if (currentIndex > 0) {
      setState(() => currentIndex--);
    }
  }

  Future<void> submitExam({
    bool timeExpired = false,
    bool retry = false,
  }) async {
    if (submitted && !retry) return;

    final submittedAnswers = <Map<String, dynamic>>[];
    for (int i = 0; i < questions.length; i++) {
      final question = questions[i];
      final questionId = question['question_id'];
      if (questionId is! num || question['options'] is! List) {
        if (!mounted) return;
        setState(() {
          examError = 'Cannot save this exam because question data is invalid.';
        });
        return;
      }

      int? selectedOptionId;
      final selectedLabel = answers[i];
      if (selectedLabel != null) {
        for (final rawOption in question['options'] as List<dynamic>) {
          if (rawOption is Map &&
              rawOption['label']?.toString() == selectedLabel &&
              rawOption['option_id'] is num) {
            selectedOptionId = (rawOption['option_id'] as num).toInt();
            break;
          }
        }
        if (selectedOptionId == null) {
          if (!mounted) return;
          setState(() {
            examError =
                'Cannot save your answer because its option ID is missing.';
          });
          return;
        }
      }

      submittedAnswers.add({
        'question_id': questionId.toInt(),
        'selected_option_id': selectedOptionId,
      });
    }

    countdown?.cancel();
    setState(() {
      submitted = true;
      _submitting = true;
      _completionError = null;
    });

    if (!mounted) return;

    bool submissionSaved = false;
    String? saveError;
    try {
      final resultId = currentResultId;
      if (resultId == null) {
        throw StateError('Exam attempt ID is missing.');
      }

      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/results/$resultId/complete'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'user_id': widget.userId,
              'duration_seconds': (5 * 60 - remainingSeconds).clamp(0, 5 * 60),
              'answers': submittedAnswers,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['status']?.toString() != 'Completed') {
        throw const FormatException('Invalid exam result response.');
      }
      submissionSaved = true;
    } catch (error) {
      saveError = error.toString();
    }

    if (!mounted) return;

    setState(() {
      _submitting = false;
      _submissionSaved = submissionSaved;
      _completionError = saveError;
    });

    if (submissionSaved) {
      await _checkResultRelease();
      if (_completedResult == null) {
        _resultReleaseTimer?.cancel();
        _resultReleaseTimer = Timer.periodic(
          const Duration(seconds: 10),
          (_) => _checkResultRelease(),
        );
      }
    }
  }

  Future<void> _checkResultRelease() async {
    final resultId = currentResultId;
    if (!mounted ||
        resultId == null ||
        !_submissionSaved ||
        _completedResult != null ||
        _checkingRelease) {
      return;
    }

    _checkingRelease = true;
    try {
      final uri = Uri.parse(
        '$apiBaseUrl/results/$resultId/student',
      ).replace(queryParameters: {'user_id': widget.userId.toString()});
      final response = await http.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid student result response.');
      }

      if (decoded['is_released'] == true) {
        if (decoded['score'] is! num ||
            decoded['total_questions'] is! num ||
            decoded['percentage'] is! num) {
          throw const FormatException(
            'Released result did not contain a valid score.',
          );
        }
        if (!mounted) return;
        setState(() {
          _completedResult = decoded;
          _releaseCheckError = null;
        });
        _resultReleaseTimer?.cancel();
      } else if (mounted) {
        setState(() => _releaseCheckError = null);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _releaseCheckError = 'Could not check result release: $error';
      });
    } finally {
      _checkingRelease = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: examStarted ? buildExamScreen() : buildTopicScreen(),
        ),
      ),
    );
  }

  Widget buildTopicScreen() {
    return Column(
      children: [
        const Text(
          'Welcome to Exam Page',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 21, color: Colors.blue),
        ),
        const SizedBox(height: 8),
        const Text(
          'Please select a topic and click Start to take the exam.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.blue),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.blue, width: 1.5),
            ),
            child: Column(
              children: [
                const SizedBox(height: 12),
                if (loadingTopics)
                  const Expanded(
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (topicsError != null)
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            topicsError!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: loadTopics,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (topics.isEmpty)
                  const Expanded(
                    child: Center(
                      child: Text(
                        'No active topics found. Add active topics in the backend first.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: ListView(
                      children: topics.map((topic) {
                        final topicId = (topic['topic_id'] as num).toInt();

                        return RadioListTile<int>(
                          value: topicId,
                          groupValue: selectedTopicId,
                          title: Text(
                            topic['topic_name']?.toString() ?? 'Unnamed topic',
                          ),
                          activeColor: Colors.blue,
                          onChanged: (value) {
                            if (value != null) {
                              setState(() {
                                selectedTopicId = value;
                                examError = null;
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ),
                if (examError != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      examError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const Spacer(),
                if (loading)
                  const CircularProgressIndicator()
                else
                  ElevatedButton(
                    onPressed:
                        loadingTopics || topicsError != null || topics.isEmpty
                        ? null
                        : startExam,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.blue,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                    ),
                    child: const Text('Start', style: TextStyle(fontSize: 18)),
                  ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget buildExamScreen() {
    if (submitted) {
      return buildSubmissionSummary();
    }

    final question = questions[currentIndex];

    final options = List<Map<String, dynamic>>.from(
      (question['options'] ?? []).map(
        (option) => Map<String, dynamic>.from(option),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back to topics',
              onPressed: submitted ? null : _returnToTopics,
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                selectedTopicName,
                style: const TextStyle(
                  fontSize: 20,
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              formattedTime,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: remainingSeconds <= 60 ? Colors.red : Colors.blue,
              ),
            ),
          ],
        ),
        const Divider(),
        if (examError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(examError!, style: const TextStyle(color: Colors.red)),
          ),
        Text(
          'Question ${currentIndex + 1} of ${questions.length}',
          style: const TextStyle(fontSize: 16, color: Colors.grey),
        ),
        const SizedBox(height: 20),
        Text(
          question['question_text']?.toString() ?? 'Question text unavailable',
          style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: ListView(
            children: options.map((option) {
              final label = option['label']?.toString() ?? '';
              final text = option['text']?.toString() ?? '';
              final selected = answers[currentIndex] == label;

              return Card(
                elevation: 0,
                color: selected
                    ? Colors.blue.withValues(alpha: 0.10)
                    : Colors.white,
                child: RadioListTile<String>(
                  value: label,
                  groupValue: answers[currentIndex],
                  activeColor: Colors.blue,
                  title: Text('$label. $text'),
                  onChanged: submitted
                      ? null
                      : (value) {
                          if (value != null) selectAnswer(value);
                        },
                ),
              );
            }).toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 32),
          child: Row(
            children: [
              if (currentIndex > 0)
                OutlinedButton(
                  onPressed: submitted ? null : previousQuestion,
                  child: const Text('Previous'),
                ),
              const Spacer(),
              if (currentIndex < questions.length - 1)
                ElevatedButton(
                  onPressed: submitted ? null : nextQuestion,
                  child: const Text('Next'),
                ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: submitted ? null : () => submitExam(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Submit'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget buildSubmissionSummary() {
    final result = _completedResult;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Card(
          elevation: 3,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _submitting
                      ? Icons.hourglass_top
                      : result != null
                      ? Icons.task_alt
                      : Icons.error_outline,
                  size: 56,
                  color: _submitting
                      ? Colors.blue
                      : result != null
                      ? Colors.green
                      : Colors.red,
                ),
                const SizedBox(height: 16),
                Text(
                  _submitting
                      ? 'Saving your result...'
                      : result != null
                      ? 'Exam submitted'
                      : 'Could not see your result',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                if (_submitting)
                  const CircularProgressIndicator()
                else if (result != null) ...[
                  Text(
                    'Your score: ${(result['score'] as num).toInt()} / '
                    '${(result['total_questions'] as num).toInt()}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(result['percentage'] as num).toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 20, color: Colors.blue),
                  ),
                  const SizedBox(height: 12),
                  const Text('Your result has been saved.'),
                ] else if (_submissionSaved) ...[
                  const Text(
                    'Your exam was submitted successfully. Your score is '
                    'hidden until an admin releases it.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  if (_releaseCheckError != null)
                    Text(
                      _releaseCheckError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    )
                  else
                    const Text('Waiting for admin approval...'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _checkingRelease ? null : _checkResultRelease,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Check result'),
                  ),
                ] else ...[
                  Text(
                    _completionError ??
                        'Your score could not be saved. Please try again.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => submitExam(
                      timeExpired: remainingSeconds == 0,
                      retry: true,
                    ),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry saving result'),
                  ),
                ],
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: _submitting ? null : _returnToTopics,
                  child: const Text('Back to Topics'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _returnToTopics() async {
    _resultReleaseTimer?.cancel();
    final resultId = currentResultId;
    if (resultId != null && _completedResult == null) {
      try {
        final response = await http
            .post(
              Uri.parse('$apiBaseUrl/results/$resultId/abandon'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'user_id': widget.userId}),
            )
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200 && response.statusCode != 409) {
          throw Exception('HTTP ${response.statusCode}: ${response.body}');
        }
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not close the exam attempt: $error')),
        );
        return;
      }
    }

    countdown?.cancel();
    if (!mounted) return;
    setState(() {
      examStarted = false;
      submitted = false;
      _submitting = false;
      _submissionSaved = false;
      _checkingRelease = false;
      _completedResult = null;
      _completionError = null;
      _releaseCheckError = null;
      questions = [];
      answers.clear();
      currentResultId = null;
      currentIndex = 0;
      remainingSeconds = 5 * 60;
    });
  }
}
