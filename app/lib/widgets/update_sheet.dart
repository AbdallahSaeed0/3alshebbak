import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_version.dart';
import '../theme.dart';
import '../util/i18n.dart';

/// "There's a new version": a sheet you can't miss, with what's new in it
/// and a big button that downloads the APK.
Future<void> showUpdatePrompt(BuildContext context, AppUpdate update) async {
  final current = await appVersion();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => UpdateSheet(update: update, current: current),
  );
}

class UpdateSheet extends StatelessWidget {
  const UpdateSheet({super.key, required this.update, required this.current});

  final AppUpdate update;
  final String current;

  @override
  Widget build(BuildContext context) {
    final notes = update.notes.take(4).toList();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.hairline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Center(
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.gold.withValues(alpha: 0.14),
                  border: Border.all(color: AppColors.goldEdge, width: 1.5),
                ),
                child: Icon(
                  Icons.system_update_rounded,
                  size: 38,
                  color: AppColors.gold,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              tr('فيه نسخة جديدة! 🎉', 'A new version is out! 🎉'),
              textAlign: TextAlign.center,
              style: AppText.display(30),
            ),
            const SizedBox(height: 10),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.raised,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Text(
                  tr(
                    'عندك $current ← الجديدة ${update.version}',
                    'You have $current → new ${update.version}',
                  ),
                  textDirection: TextDirection.rtl,
                  style: AppText.body(
                    13,
                    weight: FontWeight.w700,
                    color: AppColors.gold,
                  ),
                ),
              ),
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.raised,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('الجديد', "What's new"),
                      style: AppText.body(
                        13,
                        weight: FontWeight.w800,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final n in notes)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          n,
                          style: AppText.body(14, weight: FontWeight.w500),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                launchUrl(
                  update.download,
                  mode: LaunchMode.externalApplication,
                );
              },
              icon: const Icon(Icons.download_rounded),
              label: Text(tr('نزّلها دلوقتي', 'Download now')),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.onGold,
                minimumSize: const Size.fromHeight(54),
                textStyle: AppText.body(16, weight: FontWeight.w800),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                tr('بعدين', 'Later'),
                style: AppText.body(14, color: AppColors.muted),
              ),
            ),
            Text(
              tr(
                'بعد ما تنزل افتح الملف وثبّته فوق النسخة اللي عندك.',
                'Once it downloads, open the file and install it over this version.',
              ),
              textAlign: TextAlign.center,
              style: AppText.body(12, color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}
