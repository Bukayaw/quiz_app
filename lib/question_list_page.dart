import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class QuestionListPage extends StatefulWidget {
  final bool embedded;

  const QuestionListPage({super.key, this.embedded = false});

  @override
  State<QuestionListPage> createState() => _QuestionListPageState();
}

class _QuestionListPageState extends State<QuestionListPage> {
  static const String apiUrl = 'http://127.0.0.1:8000/questions';

  List<Map<String, dynamic>> questions = [];
  bool isLoading = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    fetchQuestions();
  }

  Future<void> fetchQuestions() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final response = await http
          .get(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final list = data['questions'] as List<dynamic>? ?? [];

      if (!mounted) return;

      setState(() {
        questions = list
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isLoading = false;
        errorMessage = 'Could not load questions: $e';
      });
    }
  }

  Future<void> addQuestion() => _showQuestionDialog();

  Future<void> editQuestion(Map<String, dynamic> question) =>
      _showQuestionDialog(question);

  Future<void> _showQuestionDialog([Map<String, dynamic>? question]) async {
    final existingOptions = (question?['options'] as List<dynamic>? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final topicController = TextEditingController(
      text: question?['topic_id']?.toString() ?? '',
    );
    final questionController = TextEditingController(
      text: question?['question_text']?.toString() ?? '',
    );
    final optionControllers = List.generate(
      4,
      (index) => TextEditingController(
        text: index < existingOptions.length
            ? existingOptions[index]['text']?.toString() ?? ''
            : '',
      ),
    );

    final correctOptions = existingOptions
        .where((option) => option['is_correct'] == true)
        .map((option) => option['label']?.toString() ?? 'A')
        .toList();
    String correctAnswer = correctOptions.isEmpty ? 'A' : correctOptions.first;
    bool saving = false;
    String? formError;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(question == null ? 'Add Question' : 'Edit Question'),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: topicController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Topic ID',
                          hintText: 'Enter an existing active topic ID',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: questionController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Question text',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),

                      for (int i = 0; i < 4; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextField(
                            controller: optionControllers[i],
                            decoration: InputDecoration(
                              labelText:
                                  'Option ${String.fromCharCode(65 + i)}',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),

                      DropdownButtonFormField<String>(
                        initialValue: correctAnswer,
                        decoration: const InputDecoration(
                          labelText: 'Correct answer',
                        ),
                        items: ['A', 'B', 'C', 'D']
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() => correctAnswer = value);
                          }
                        },
                      ),

                      if (formError != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          formError!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final topicId = int.tryParse(
                            topicController.text.trim(),
                          );
                          final questionText = questionController.text.trim();

                          final optionTexts = optionControllers
                              .map((c) => c.text.trim())
                              .toList();

                          if (topicId == null || topicId <= 0) {
                            setDialogState(() {
                              formError = 'Enter a valid Topic ID.';
                            });
                            return;
                          }

                          if (questionText.isEmpty ||
                              optionTexts.any((text) => text.isEmpty)) {
                            setDialogState(() {
                              formError =
                                  'Enter the question and all four options.';
                            });
                            return;
                          }

                          setDialogState(() {
                            saving = true;
                            formError = null;
                          });

                          try {
                            final payload = {
                              'topic_id': topicId,
                              'question_text': questionText,
                              'options': List.generate(4, (index) {
                                final label = String.fromCharCode(65 + index);
                                return {
                                  'label': label,
                                  'text': optionTexts[index],
                                  'is_correct': label == correctAnswer,
                                };
                              }),
                            };

                            final request = question == null
                                ? http.post(
                                    Uri.parse(apiUrl),
                                    headers: {
                                      'Content-Type': 'application/json',
                                    },
                                    body: jsonEncode(payload),
                                  )
                                : http.put(
                                    Uri.parse(
                                      '$apiUrl/${question['question_id']}',
                                    ),
                                    headers: {
                                      'Content-Type': 'application/json',
                                    },
                                    body: jsonEncode(payload),
                                  );
                            final response = await request.timeout(
                              const Duration(seconds: 15),
                            );

                            if (response.statusCode != 201 &&
                                response.statusCode != 200) {
                              throw Exception(
                                'HTTP ${response.statusCode}: '
                                '${response.body}',
                              );
                            }

                            if (!dialogContext.mounted) return;
                            Navigator.pop(dialogContext);

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    question == null
                                        ? 'Question added successfully'
                                        : 'Question updated successfully',
                                  ),
                                ),
                              );
                              fetchQuestions();
                            }
                          } catch (e) {
                            setDialogState(() {
                              saving = false;
                              formError =
                                  'Could not ${question == null ? 'add' : 'update'} '
                                  'question: $e';
                            });
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(question == null ? 'Save' : 'Update'),
                ),
              ],
            );
          },
        );
      },
    );

    topicController.dispose();
    questionController.dispose();
    for (final controller in optionControllers) {
      controller.dispose();
    }
  }

  Future<void> deleteQuestion(Map<String, dynamic> question) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete question?'),
        content: const Text(
          'This question will no longer be available to users.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final response = await http
          .delete(Uri.parse('$apiUrl/${question['question_id']}'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200 && response.statusCode != 204) {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Question deleted successfully')),
      );
      await fetchQuestions();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete question: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recorded Questions'),
        leading: IconButton(
          tooltip: 'Back to Admin',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh questions',
            icon: const Icon(Icons.refresh),
            onPressed: fetchQuestions,
          ),
          IconButton(
            tooltip: 'Add question',
            icon: const Icon(Icons.add),
            onPressed: addQuestion,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Total questions: ${questions.length}'),
            ),
          ),
          if (isLoading) const LinearProgressIndicator(),

          if (errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Text(
                    errorMessage!,
                    style: const TextStyle(color: Colors.red),
                  ),
                  TextButton.icon(
                    onPressed: fetchQuestions,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            ),

          Expanded(
            child: questions.isEmpty
                ? Center(
                    child: isLoading
                        ? const CircularProgressIndicator()
                        : Text(
                            errorMessage == null
                                ? 'No questions recorded'
                                : 'Unable to display questions',
                          ),
                  )
                : ListView.builder(
                    itemCount: questions.length,
                    itemBuilder: (context, index) {
                      final question = questions[index];
                      final options =
                          question['options'] as List<dynamic>? ?? [];

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 5,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Question ${question['question_id'] ?? index + 1}'
                                      ' • Topic: ${question['topic_name'] ?? question['topic_id'] ?? '—'}',
                                      style: const TextStyle(
                                        color: Colors.blue,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Edit question',
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: () => editQuestion(question),
                                  ),
                                  IconButton(
                                    tooltip: 'Delete question',
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    onPressed: () => deleteQuestion(question),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                question['question_text']?.toString() ??
                                    'No question text',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...options.map((item) {
                                final option = Map<String, dynamic>.from(
                                  item as Map,
                                );
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 3,
                                  ),
                                  child: Text(
                                    '${option['label'] ?? ''}. '
                                    '${option['text'] ?? ''}',
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
