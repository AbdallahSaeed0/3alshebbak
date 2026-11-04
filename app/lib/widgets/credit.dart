import 'package:flutter/material.dart';

import '../services/app_version.dart';
import '../theme.dart';
import '../util/i18n.dart';

/// Who made the app, at the foot of Settings and the splash screen.
class Credit extends StatelessWidget {
  const Credit({super.key});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        'CRAFTED WITH CARE',
        style: AppText.body(
          11,
          weight: FontWeight.w700,
          color: AppColors.muted,
        ).copyWith(letterSpacing: 2),
      ),
      const SizedBox(height: 6),
      Text(
        'Abdallah Saeed 🍿',
        textDirection: TextDirection.ltr,
        style: AppText.body(16, weight: FontWeight.w800),
      ),
      const SizedBox(height: 4),
      FutureBuilder<String>(
        future: appVersion(),
        builder: (context, version) => Text(
          [
            tr(
              'عالشباك · مواعيد سينمات مصر',
              '3al Shebbak · Egypt\'s showtimes',
            ),
            if (version.data != null) 'v${version.data}',
          ].join(' · '),
          style: AppText.body(12, color: AppColors.muted),
        ),
      ),
    ],
  );
}
