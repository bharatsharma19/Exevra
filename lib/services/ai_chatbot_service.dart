import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import '../models/expense_model.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/currency_formatter.dart';

/// Chunk emitted during streaming AI responses
class AiStreamChunk {
  final String text;
  final String? modelUsed;
  final bool isComplete;

  const AiStreamChunk({
    required this.text,
    this.modelUsed,
    this.isComplete = false,
  });
}

/// Multi-Model Failover Financial Assistant Service
/// Waterfall: Google Gemini (2.5/1.5 Flash) -> OpenAI gpt-4o-mini -> Anthropic Claude 3.5 Haiku -> DeepSeek -> Heuristic Engine
class AiChatbotService {
  static AiChatbotService? _instance;
  static AiChatbotService get instance => _instance ??= AiChatbotService._();

  AiChatbotService._();

  static const _secureStorage = FlutterSecureStorage();

  // API Keys retrieved from --dart-define or system environment
  final String _envGeminiApiKey = const String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  final String _envOpenAiApiKey = const String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');
  final String _envClaudeApiKey = const String.fromEnvironment('ANTHROPIC_API_KEY', defaultValue: '');
  final String _envDeepseekApiKey = const String.fromEnvironment('DEEPSEEK_API_KEY', defaultValue: '');

  Future<String> getGeminiApiKey() async {
    final dotEnvKey = dotenv.isInitialized ? dotenv.env['GEMINI_API_KEY'] : null;
    if (dotEnvKey != null && dotEnvKey.isNotEmpty) return dotEnvKey;
    if (_envGeminiApiKey.isNotEmpty) return _envGeminiApiKey;
    try {
      final key = await _secureStorage.read(key: AppConstants.keyGeminiApiKey);
      return key ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<String> getOpenAiApiKey() async {
    final dotEnvKey = dotenv.isInitialized ? dotenv.env['OPENAI_API_KEY'] : null;
    if (dotEnvKey != null && dotEnvKey.isNotEmpty) return dotEnvKey;
    if (_envOpenAiApiKey.isNotEmpty) return _envOpenAiApiKey;
    try {
      final key = await _secureStorage.read(key: AppConstants.keyOpenAiApiKey);
      return key ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<String> getClaudeApiKey() async {
    final dotEnvKey = dotenv.isInitialized ? dotenv.env['ANTHROPIC_API_KEY'] : null;
    if (dotEnvKey != null && dotEnvKey.isNotEmpty) return dotEnvKey;
    if (_envClaudeApiKey.isNotEmpty) return _envClaudeApiKey;
    try {
      final key = await _secureStorage.read(key: AppConstants.keyClaudeApiKey);
      return key ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<String> getDeepseekApiKey() async {
    final dotEnvKey = dotenv.isInitialized ? dotenv.env['DEEPSEEK_API_KEY'] : null;
    if (dotEnvKey != null && dotEnvKey.isNotEmpty) return dotEnvKey;
    if (_envDeepseekApiKey.isNotEmpty) return _envDeepseekApiKey;
    try {
      final key = await _secureStorage.read(key: AppConstants.keyDeepseekApiKey);
      return key ?? '';
    } catch (_) {
      return '';
    }
  }

  // Non-Financial Guardrails Regex
  static final RegExp _financialIntentKeywords = RegExp(
    r'\b(expense|spend|spending|budget|money|cost|dollar|save|saving|invest|bill|salary|income|price|debt|loan|tax|finance|financial|category|food|rent|grocery|groceries|shopping|transport|uber|balance|cash|fund|card|subscription)\b',
    caseSensitive: false,
  );

  /// Validates whether the prompt relates to financial or application management
  bool isFinancialQuery(String prompt) {
    if (prompt.trim().length < 3) return true;
    return _financialIntentKeywords.hasMatch(prompt);
  }

  /// Streaming generator with seamless multi-model waterfall failover
  Stream<AiStreamChunk> generateResponseStream({
    required String userPrompt,
    required bool aiConsent,
    required List<Expense> expenses,
    String currencyCode = AppConstants.defaultCurrency,
  }) async* {
    // 1. Strict Guardrail Verification
    if (!isFinancialQuery(userPrompt)) {
      final refusal = '🛡️ **Financial Scope Protection**\n\n'
          'I am your dedicated **Exevra Financial Assistant**. '
          'I specialize exclusively in personal and group finance, expense optimization, '
          'budget planning, and financial wellness.\n\n'
          'Please ask a question related to your spending, budgeting strategies, or expenses.';
      for (final chunk in _simulateWordStream(refusal)) {
        await Future.delayed(const Duration(milliseconds: 20));
        yield AiStreamChunk(text: chunk, modelUsed: 'Guardrail Engine', isComplete: false);
      }
      yield const AiStreamChunk(text: '', modelUsed: 'Guardrail Engine', isComplete: true);
      return;
    }

    // 2. Prepare Context with Data Isolation
    final systemPrompt = _buildSystemPrompt(aiConsent, expenses, currencyCode);

    // Fetch keys dynamically (environment or secure storage)
    final geminiKey = await getGeminiApiKey();
    final openAiKey = await getOpenAiApiKey();
    final claudeKey = await getClaudeApiKey();
    final deepseekKey = await getDeepseekApiKey();

    // 3. Model 1: Google Gemini (Primary Ultra-Low Latency)
    if (geminiKey.isNotEmpty) {
      bool geminiSuccess = false;
      String fullGeminiText = '';
      try {
        final stream = _callGeminiStream(userPrompt, systemPrompt, geminiKey);
        await for (final chunk in stream) {
          geminiSuccess = true;
          fullGeminiText += chunk;
          yield AiStreamChunk(text: chunk, modelUsed: 'Google Gemini 2.5 Flash', isComplete: false);
        }
        if (geminiSuccess && fullGeminiText.isNotEmpty) {
          yield const AiStreamChunk(text: '', modelUsed: 'Google Gemini 2.5 Flash', isComplete: true);
          return;
        }
      } catch (e) {
        debugPrint('[AiChatbotService] Gemini failover triggered: $e');
      }
    }

    // 4. Model 2: OpenAI gpt-4o-mini (Fallback 1)
    if (openAiKey.isNotEmpty) {
      bool openAiSuccess = false;
      String fullOpenAiText = '';
      try {
        final stream = _callOpenAiStream(userPrompt, systemPrompt, openAiKey);
        await for (final chunk in stream) {
          openAiSuccess = true;
          fullOpenAiText += chunk;
          yield AiStreamChunk(text: chunk, modelUsed: 'OpenAI GPT-4o-mini', isComplete: false);
        }
        if (openAiSuccess && fullOpenAiText.isNotEmpty) {
          yield const AiStreamChunk(text: '', modelUsed: 'OpenAI GPT-4o-mini', isComplete: true);
          return;
        }
      } catch (e) {
        debugPrint('[AiChatbotService] OpenAI failover triggered: $e');
      }
    }

    // 5. Model 3: Anthropic Claude 3.5 Haiku (Fallback 2)
    if (claudeKey.isNotEmpty) {
      bool claudeSuccess = false;
      String fullClaudeText = '';
      try {
        final stream = _callClaudeStream(userPrompt, systemPrompt, claudeKey);
        await for (final chunk in stream) {
          claudeSuccess = true;
          fullClaudeText += chunk;
          yield AiStreamChunk(text: chunk, modelUsed: 'Anthropic Claude 3.5 Haiku', isComplete: false);
        }
        if (claudeSuccess && fullClaudeText.isNotEmpty) {
          yield const AiStreamChunk(text: '', modelUsed: 'Anthropic Claude 3.5 Haiku', isComplete: true);
          return;
        }
      } catch (e) {
        debugPrint('[AiChatbotService] Claude failover triggered: $e');
      }
    }

    // 6. Model 4: DeepSeek Financial V3 (Fallback 3)
    if (deepseekKey.isNotEmpty) {
      bool deepseekSuccess = false;
      String fullDeepseekText = '';
      try {
        final stream = _callDeepseekStream(userPrompt, systemPrompt, deepseekKey);
        await for (final chunk in stream) {
          deepseekSuccess = true;
          fullDeepseekText += chunk;
          yield AiStreamChunk(text: chunk, modelUsed: 'DeepSeek Financial V3', isComplete: false);
        }
        if (deepseekSuccess && fullDeepseekText.isNotEmpty) {
          yield const AiStreamChunk(text: '', modelUsed: 'DeepSeek Financial V3', isComplete: true);
          return;
        }
      } catch (e) {
        debugPrint('[AiChatbotService] DeepSeek failover triggered: $e');
      }
    }

    // 7. Resilient On-Device Financial Intelligence Engine (Zero external dependencies)
    // Ensures immediately responsive, high-value guidance even without external API keys
    final intelligentResponse = _generateHeuristicFinancialAdvice(userPrompt, aiConsent, expenses, currencyCode);
    for (final chunk in _simulateWordStream(intelligentResponse)) {
      await Future.delayed(const Duration(milliseconds: 18));
      yield AiStreamChunk(text: chunk, modelUsed: 'Antigravity Intelligence Core', isComplete: false);
    }
    yield const AiStreamChunk(text: '', modelUsed: 'Antigravity Intelligence Core', isComplete: true);
  }

  // ---------------------------------------------------------------------------
  // SYSTEM PROMPT BUILDER & DATA SANITIZATION
  // ---------------------------------------------------------------------------

  String _buildSystemPrompt(bool aiConsent, List<Expense> expenses, String currencyCode) {
    final buffer = StringBuffer();
    buffer.writeln('You are Antigravity Financial Assistant, an elite personal and group financial advisor.');
    buffer.writeln('Respond with crisp formatting, markdown bullets, bold headers, and actionable metrics.');

    if (aiConsent) {
      // Data Isolation & Sanitization: aggregate metrics ONLY, zero PII
      double total = 0;
      final Map<String, double> catTotals = {};
      for (final e in expenses) {
        total += e.amount;
        catTotals[e.category] = (catTotals[e.category] ?? 0) + e.amount;
      }

      buffer.writeln('\n[PRIVACY CONSENT GRANTED - SANITIZED USER SPENDING DATA]');
      buffer.writeln('Active Currency: $currencyCode');
      buffer.writeln('Total Tracked Expenses: ${CurrencyFormatter.format(total, currencyCode: currencyCode)} across ${expenses.length} records.');
      buffer.writeln('Category Totals:');
      catTotals.forEach((cat, amt) {
        final pct = total > 0 ? (amt / total * 100).toStringAsFixed(1) : '0';
        buffer.writeln('- $cat: ${CurrencyFormatter.format(amt, currencyCode: currencyCode)} ($pct%)');
      });
      buffer.writeln('Use these actual numbers to provide hyper-personalized insights.');
    } else {
      buffer.writeln('\n[PRIVACY CONSENT NOT GRANTED]');
      buffer.writeln('The user has NOT consented to database analysis. You have ZERO access to their transaction records.');
      buffer.writeln('Act exclusively as a theoretical financial advisor providing best-practice budgeting techniques.');
    }

    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // API CLIENT STREAMS
  // ---------------------------------------------------------------------------

  Stream<String> _callGeminiStream(String prompt, String systemPrompt, String apiKey) async* {
    // Attempt primary gemini-2.5-flash, fallback to gemini-1.5-flash
    final models = [AppConstants.geminiModel, 'gemini-1.5-flash'];
    http.Response? response;

    for (final model in models) {
      final uri = Uri.parse('${AppConstants.geminiEndpoint}/$model:generateContent?key=$apiKey');
      try {
        final res = await http.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {'text': '$systemPrompt\n\nUser Question: $prompt'}
                ]
              }
            ],
            'generationConfig': {'temperature': 0.7, 'maxOutputTokens': 800}
          }),
        ).timeout(const Duration(seconds: 12));

        if (res.statusCode == 200) {
          response = res;
          break;
        }
      } catch (_) {
        continue;
      }
    }

    if (response != null && response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String?;
      if (text != null && text.isNotEmpty) {
        for (final word in text.split(' ')) {
          yield '$word ';
          await Future.delayed(const Duration(milliseconds: 14));
        }
      }
    } else {
      throw Exception('Gemini request failed');
    }
  }

  Stream<String> _callOpenAiStream(String prompt, String systemPrompt, String apiKey) async* {
    final uri = Uri.parse(AppConstants.openAiEndpoint);
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': AppConstants.openAiModel,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': prompt}
        ],
        'temperature': 0.7,
      }),
    ).timeout(const Duration(seconds: 12));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final text = data['choices']?[0]?['message']?['content'] as String?;
      if (text != null && text.isNotEmpty) {
        for (final word in text.split(' ')) {
          yield '$word ';
          await Future.delayed(const Duration(milliseconds: 14));
        }
      }
    } else {
      throw Exception('OpenAI status: ${response.statusCode}');
    }
  }

  Stream<String> _callClaudeStream(String prompt, String systemPrompt, String apiKey) async* {
    final uri = Uri.parse(AppConstants.claudeEndpoint);
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': '2023-06-01',
      },
      body: jsonEncode({
        'model': AppConstants.claudeModel,
        'max_tokens': 800,
        'system': systemPrompt,
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
      }),
    ).timeout(const Duration(seconds: 12));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final content = data['content'] as List?;
      if (content != null && content.isNotEmpty) {
        final text = content[0]['text'] as String?;
        if (text != null && text.isNotEmpty) {
          for (final word in text.split(' ')) {
            yield '$word ';
            await Future.delayed(const Duration(milliseconds: 14));
          }
        }
      }
    } else {
      throw Exception('Claude status: ${response.statusCode}');
    }
  }

  Stream<String> _callDeepseekStream(String prompt, String systemPrompt, String apiKey) async* {
    final uri = Uri.parse(AppConstants.deepseekEndpoint);
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': AppConstants.deepseekModel,
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': prompt}
        ],
        'temperature': 0.7,
      }),
    ).timeout(const Duration(seconds: 12));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final text = data['choices']?[0]?['message']?['content'] as String?;
      if (text != null && text.isNotEmpty) {
        for (final word in text.split(' ')) {
          yield '$word ';
          await Future.delayed(const Duration(milliseconds: 14));
        }
      }
    } else {
      throw Exception('DeepSeek status: ${response.statusCode}');
    }
  }

  // ---------------------------------------------------------------------------
  // HEURISTIC ENGINE (OFFLINE / ZERO-KEY INSTANT SAFETY NET)
  // ---------------------------------------------------------------------------

  String _generateHeuristicFinancialAdvice(
    String prompt,
    bool aiConsent,
    List<Expense> expenses,
    String currencyCode,
  ) {
    final lower = prompt.toLowerCase();

    if (!aiConsent) {
      if (lower.contains('50/30/20') || lower.contains('rule')) {
        return '### 📊 The 50/30/20 Budgeting Framework\n\n'
            'The **50/30/20 rule** is an intuitive budgeting methodology designed to simplify cash allocation:\n\n'
            '1. **50% Needs**: Essential living expenses (Rent/Mortgage, Groceries, Utilities, Healthcare, Debt minimums).\n'
            '2. **30% Wants**: Lifestyle and discretionary spending (Dining out, Entertainment, Subscriptions, Hobbies).\n'
            '3. **20% Savings & Debt Acceleration**: High-yield savings, emergency buffers, investments, and principal debt payments.\n\n'
            '💡 *Pro-Tip*: Enable **Spending Analysis Consent** in settings to have me map your tracked expenses directly against these three categories!';
      }

      if (lower.contains('cut') || lower.contains('reduce') || lower.contains('save')) {
        return '### ⚡ 3 High-Impact Strategies to Reduce Expenses by 15%\n\n'
            '1. **Audit Recurring Subscriptions**:\n'
            '   Recurring digital subscriptions represent silent cash leaks. Cancel services unused in the last 30 days.\n\n'
            '2. **Implement the 48-Hour Discretionary Rule**:\n'
            '   Before any non-essential purchase over \$50, enforce a 48-hour cooling-off period to prevent impulse buying.\n\n'
            '3. **Batch Meal Planning**:\n'
            '   Dining out and convenience deliveries cost up to 4x more than home-cooked staples. Meal prep on Sundays to trim food bills by up to 25%.\n\n'
            '🔒 *Note: Turn on Privacy Consent to get personalized cut recommendations tailored to your actual category trends!*';
      }

      return '### 💡 Financial Advisor Insights\n\n'
          'Healthy financial architecture starts with consistent cashflow visibility. '
          'Tracking your transactions daily builds behavioral awareness, reducing incidental spending by an average of 12% in the first quarter.\n\n'
          'Key foundational milestones:\n'
          '- **Emergency Fund**: Maintain 3-6 months of essential living expenses in an accessible high-yield account.\n'
          '- **Group Accountability**: Split shared living expenses evenly to avoid end-of-month friction.\n'
          '- **Categorical Limits**: Establish strict ceilings for flexible categories like Dining and Entertainment.';
    }

    // PRIVACY CONSENT GRANTED: Deliver real numbers
    double total = 0;
    final Map<String, double> categorySums = {};
    for (final exp in expenses) {
      total += exp.amount;
      categorySums[exp.category] = (categorySums[exp.category] ?? 0) + exp.amount;
    }

    String topCategory = 'None';
    double topAmount = 0;
    categorySums.forEach((k, v) {
      if (v > topAmount) {
        topAmount = v;
        topCategory = k;
      }
    });

    final topPct = total > 0 ? (topAmount / total * 100).toStringAsFixed(1) : '0';

    if (lower.contains('top') || lower.contains('category') || lower.contains('highest')) {
      final breakdownList = categorySums.entries.map((e) {
        final pct = total > 0 ? (e.value / total * 100).toStringAsFixed(1) : '0';
        return '- **${e.key}**: ${CurrencyFormatter.format(e.value, currencyCode: currencyCode)} (`$pct%`)';
      }).join('\n');

      return '### 🔍 Spending Analysis: Category Breakdown\n\n'
          'Based on your tracked records across **${expenses.length} expenses**:\n\n'
          '- **Total Spending**: **${CurrencyFormatter.format(total, currencyCode: currencyCode)}**\n'
          '- **Dominant Category**: **$topCategory** at **${CurrencyFormatter.format(topAmount, currencyCode: currencyCode)}** ($topPct% of all spending)\n\n'
          '**Top Category Breakdown**:\n$breakdownList\n\n'
          '💡 **Optimization Opportunity**: Your spending in **$topCategory** represents your largest cost center. Trimming this category by just 10% will liberate **${CurrencyFormatter.format(topAmount * 0.1, currencyCode: currencyCode)}** for monthly savings.';
    }

    return '### 📈 Personalized Financial Health Report\n\n'
        'You have currently logged **${CurrencyFormatter.format(total, currencyCode: currencyCode)}** across **${expenses.length} transactions**.\n\n'
        '**Key Findings**:\n'
        '1. **Primary Outflow**: **$topCategory** represents **$topPct%** of your total spending.\n'
        '2. **Daily Average**: You are pacing approximately **${CurrencyFormatter.format(total / 30, currencyCode: currencyCode)}/day** over a 30-day window.\n'
        '3. **Action Step**: Target a 10% reduction in **$topCategory** to preserve capital without sacrificing essential lifestyle standards.';
  }

  Iterable<String> _simulateWordStream(String text) sync* {
    final words = text.split(' ');
    for (int i = 0; i < words.length; i++) {
      yield (i == words.length - 1) ? words[i] : '${words[i]} ';
    }
  }
}
