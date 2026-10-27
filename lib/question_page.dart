import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String apiBaseUrl = 'http://127.0.0.1:8000';

class QuestionPage extends StatefulWidget {
  const QuestionPage({super.key});

  @override
  State<QuestionPage> createState() => _QuestionPageState();
}

class _QuestionPageState extends State<QuestionPage> {
  final _formKey = GlobalKey<FormState>();
  final _questionController = TextEditingController();
  final _optionControllers = List.generate(4, (_) => TextEditingController());

  List<Map<String, dynamic>> topics = [];
  int? selectedTopicId;
  String correctAnswer = 'A';
  bool loadingTopics = true;
  bool saving = false;
  String? message;
  bool success = false;

  @override
  void initState() {
    super.initState();
    loadTopics();
  }

  Future<void> loadTopics() async {
    try {
      final response = await http.get(Uri.parse('$apiBaseUrl/topics'));

      if (response.statusCode != 200) {
        throw Exception(response.body);
      }

      final data = jsonDecode(response.body);
      final List list = data is List ? data : data['topics'];

      if (!mounted) return;
      setState(() {
        topics = list.cast<Map<String, dynamic>>();
        selectedTopicId = topics.isNotEmpty
            ? (topics.first['topic_id'] as num).toInt()
            : null;
        loadingTopics = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loadingTopics = false;
        message = 'Could not load topics. Check FastAPI and GET /topics.';
      });
    }
  }

  Future<void> saveQuestion() async {
    if (!_formKey.currentState!.validate()) return;

    if (selectedTopicId == null) {
      setState(() => message = 'Please create/select a topic first.');
      return;
    }

    setState(() {
      saving = true;
      message = null;
    });

    final payload = {
      'topic_id': selectedTopicId,
      'question_text': _questionController.text.trim(),
      'options': List.generate(4, (i) {
        final label = String.fromCharCode(65 + i);
        return {
          'label': label,
          'text': _optionControllers[i].text.trim(),
          'is_correct': label == correctAnswer,
        };
      }),
    };

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/questions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        _questionController.clear();
        for (final controller in _optionControllers) {
          controller.clear();
        }

        if (!mounted) return;
        setState(() {
          correctAnswer = 'A';
          success = true;
          message = 'Question saved successfully!';
        });
      } else {
        if (!mounted) return;
        setState(() {
          success = false;
          message =
              'Save failed (${response.statusCode}): '
              '${response.body}';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        success = false;
        message = 'Cannot connect to the API. Is FastAPI running?';
      });
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    _questionController.dispose();
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const labels = ['A', 'B', 'C', 'D'];

    return Scaffold(
      appBar: AppBar(title: const Text('Add Questions')),
      body: loadingTopics
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 750),
                child: Form(
                  key: _formKey,
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(
                        'Add New Question',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 20),
                      if (topics.isEmpty)
                        const Text(
                          'No topics available. Create a topic in the database first.',
                        )
                      else
                        DropdownButtonFormField<int>(
                          initialValue: selectedTopicId,
                          decoration: const InputDecoration(
                            labelText: 'Topic',
                            border: OutlineInputBorder(),
                          ),
                          items: topics.map((topic) {
                            return DropdownMenuItem<int>(
                              value: (topic['topic_id'] as num).toInt(),
                              child: Text(topic['topic_name'].toString()),
                            );
                          }).toList(),
                          onChanged: (value) =>
                              setState(() => selectedTopicId = value),
                        ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _questionController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Question',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Enter the question'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      for (int i = 0; i < 4; i++) ...[
                        TextFormField(
                          controller: _optionControllers[i],
                          decoration: InputDecoration(
                            labelText: 'Option ${labels[i]}',
                            border: const OutlineInputBorder(),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Enter option ${labels[i]}'
                              : null,
                        ),
                        const SizedBox(height: 12),
                      ],
                      DropdownButtonFormField<String>(
                        initialValue: correctAnswer,
                        decoration: const InputDecoration(
                          labelText: 'Correct Answer',
                          border: OutlineInputBorder(),
                        ),
                        items: labels.map((label) {
                          return DropdownMenuItem(
                            value: label,
                            child: Text('Option $label'),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setState(() => correctAnswer = value);
                          }
                        },
                      ),
                      const SizedBox(height: 20),
                      if (message != null) ...[
                        Text(
                          message!,
                          style: TextStyle(
                            color: success ? Colors.green : Colors.red,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      ElevatedButton.icon(
                        onPressed: saving || topics.isEmpty
                            ? null
                            : saveQuestion,
                        icon: const Icon(Icons.save),
                        label: Text(saving ? 'Saving...' : 'Save Question'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
