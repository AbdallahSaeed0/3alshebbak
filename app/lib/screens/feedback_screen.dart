import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../data/supabase_repository.dart';
import '../services/app_version.dart';
import '../services/usage.dart';
import '../theme.dart';
import '../util/i18n.dart';

void openFeedback(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const FeedbackScreen()));

/// "Send us your thoughts": a complaint, an idea, a wrong showtime. It goes
/// to Supabase (`submit_feedback`); the developer reads it with
/// `npm run feedback` in scraper/.
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key, this.client});

  @visibleForTesting
  final http.Client? client;

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _message = TextEditingController();
  final _contact = TextEditingController();
  String _kind = 'idea';
  bool _sending = false;

  static List<(String, String, IconData)> get _kinds => [
    ('idea', tr('اقتراح', 'Idea'), Icons.lightbulb_outline),
    (
      'complaint',
      tr('شكوى', 'Complaint'),
      Icons.sentiment_dissatisfied_outlined,
    ),
    ('showtimes', tr('ميعاد غلط', 'Wrong showtime'), Icons.event_busy_outlined),
    ('other', tr('حاجة تانية', 'Something else'), Icons.chat_bubble_outline),
  ];

  @override
  void dispose() {
    _message.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (text.length < 3) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(tr('اكتب رسالتك الأول', 'Write your message first')),
        ),
      );
      return;
    }
    setState(() => _sending = true);
    final client = widget.client ?? http.Client();
    var ok = false;
    try {
      final res = await client
          .post(
            Uri.parse(
              '${SupabaseShowtimesRepository.url}/rest/v1/rpc/submit_feedback',
            ),
            headers: {
              ...SupabaseShowtimesRepository.headers,
              'Content-Profile': 'shebbak',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'p_kind': _kind,
              'p_message': text,
              'p_contact': _contact.text.trim(),
              'p_platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
              'p_version': await appVersion().catchError((_) => ''),
              'p_install': await Usage.installId(),
            }),
          )
          .timeout(const Duration(seconds: 20));
      ok = res.statusCode < 300 && res.body.trim() == 'true';
    } catch (e) {
      debugPrint('Feedback not sent: $e');
    } finally {
      if (widget.client == null) client.close();
    }
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'وصلتنا، شكرًا إنك قلتلنا 🙏',
              'Got it, thank you for telling us 🙏',
            ),
          ),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            tr(
              'ما اتبعتتش. اتأكد من النت وجرّب تاني.',
              'Not sent. Check your connection and try again.',
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final field = InputDecoration(
      filled: true,
      fillColor: AppColors.raised,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('ابعتلنا رأيك', 'Send feedback'),
          style: AppText.display(22),
        ),
        backgroundColor: AppColors.background,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          Text(
            tr(
              'عندك شكوى، أو فكرة تخلّي التطبيق أحسن، أو لقيت ميعاد غلط؟ قولنا وهنقراها كلها.',
              'A complaint, an idea to make the app better, or a wrong showtime? Tell us — we read every one.',
            ),
            style: AppText.body(14, color: AppColors.muted),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (id, label, icon) in _kinds)
                ChoiceChip(
                  selected: _kind == id,
                  onSelected: (_) => setState(() => _kind = id),
                  avatar: Icon(icon, size: 18),
                  label: Text(label),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _message,
            minLines: 5,
            maxLines: 10,
            maxLength: 4000,
            textInputAction: TextInputAction.newline,
            decoration: field.copyWith(
              hintText: _kind == 'showtimes'
                  ? tr(
                      'أنهي فيلم وأنهي سينما، والميعاد الصح إيه؟',
                      'Which film and cinema, and what is the right time?',
                    )
                  : tr('اكتب هنا…', 'Write here…'),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _contact,
            maxLength: 200,
            keyboardType: TextInputType.emailAddress,
            decoration: field.copyWith(
              hintText: tr(
                'إيميلك أو رقمك لو عايزنا نرد عليك (اختياري)',
                'Your email or number if you\'d like a reply (optional)',
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _sending ? null : _send,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.onGold,
              minimumSize: const Size.fromHeight(52),
              textStyle: AppText.body(15, weight: FontWeight.w700),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: _sending
                ? SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.onGold,
                    ),
                  )
                : const Icon(Icons.send_rounded, size: 18),
            label: Text(tr('ابعت', 'Send')),
          ),
        ],
      ),
    );
  }
}
