import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import '../util/i18n.dart';

/// The privacy policy, in the app's language. The same text is published at
/// web/privacy.html for the store listing; change both together.
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const _contact = 'https://github.com/AbdallahSaeed0/3alshebbak/issues';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr('سياسة الخصوصية', 'Privacy policy'),
          style: AppText.display(24),
        ),
        backgroundColor: AppColors.background,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
        children: [
          Text(
            tr('آخر تحديث: 11 نوفمبر 2026', 'Last updated 11 November 2026'),
            style: AppText.body(13, color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          _Para(
            tr(
              'عالشباك بيجمع مواعيد حفلات السينما في مصر في مكان واحد. التطبيق مالوش حسابات ولا تسجيل دخول، وأغلب اللي بتعمله فيه بيفضل على موبايلك.',
              '3al Shebbak brings Egypt\'s cinema showtimes into one place. The app has no accounts or sign-in, and most of what you do in it stays on your phone.',
            ),
          ),
          _Title(tr('اللي بيتحفظ على موبايلك بس', 'Kept on your phone only')),
          _Bullet(
            tr(
              'السينمات اللي اخترتها، والأفلام اللي بتتابعها، وإعداداتك (اللغة والشكل والمدينة).',
              'The cinemas you pick, the films you follow, and your settings (language, appearance, city).',
            ),
          ),
          _Bullet(
            tr(
              'مكانك لو سمحت بيه: بنستخدمه على الموبايل عشان نرتب السينمات من الأقرب، ومش بيتبعت لينا ولا لأي حد.',
              'Your location, if you allow it: used on the phone to sort cinemas nearest first. It is never sent to us or anyone else.',
            ),
          ),
          _Bullet(
            tr(
              'اسكرينات التذاكر اللي بتضيفها في «تذاكري»: بتتحفظ في فولدر التطبيق على الموبايل، ومش بتترفع في أي مكان.',
              'Ticket screenshots you add under "My tickets": stored in the app\'s folder on your phone and never uploaded.',
            ),
          ),
          _Para(
            tr(
              'لو مسحت التطبيق، كل ده بيتمسح معاه.',
              'Uninstalling the app deletes all of it.',
            ),
          ),
          _Title(tr('الإشعارات', 'Notifications')),
          _Para(
            tr(
              'لو شغّلت إشعارات «التذاكر نزلت»، بنحفظ على السيرفر بتاعنا (Supabase): رقم تعريف الإشعارات بتاع الجهاز، والأفلام اللي بتتابعها، والسينمات اللي اخترتها، عشان نعرف نبعتلك لما الحجز يفتح. مفيش اسم ولا رقم تليفون ولا مكان. الإشعارات بتتبعت عن طريق Firebase Cloud Messaging من Google. لو مسحت التطبيق، الرقم ده بيبطّل يشتغل وبيتمسح من عندنا لوحده. ولو عايز تمسحه فورًا كلّمنا.',
              'If you turn on "tickets are out" alerts, our server (Supabase) stores your device\'s notification token, the films you follow and the cinemas you picked, so we can tell you when booking opens. No name, phone number or location. Notifications are delivered through Google\'s Firebase Cloud Messaging. If you uninstall the app, the token stops working and is deleted from our side automatically. To have it deleted right away, contact us.',
            ),
          ),
          _Para(
            tr(
              'عشان نعرف كام واحد بيستخدم التطبيق: أول مرة تفتحه كل يوم، بيبعت للسيرفر رقم عشوائي اتعمل على موبايلك (مش مربوط بيك ولا بأي حساب)، ونوع الموبايل (أندرويد أو آيفون)، ونسخة التطبيق. بس كده.',
              'To count how many people use the app: the first time you open it each day, it sends our server a random number made up on your phone (not tied to you or any account), the kind of phone (Android or iPhone) and the app version. Nothing else.',
            ),
          ),
          _Para(
            tr(
              'عشان إعداداتك ترجع لو مسحت التطبيق ونزّلته تاني على نفس الموبايل: بنحفظ على السيرفر السينمات اللي اخترتها، والأفلام اللي بتتابعها، واختيارات الإشعارات، واللغة والشكل، مربوطين برقم متشفّر بيتعمل على موبايلك ومالوش علاقة بيك ولا برقم تليفونك. مكانك عمره ما بيتحفظ.',
              'So your settings come back if you delete the app and install it again on the same phone: our server keeps the cinemas you picked, the films you follow, your alert choices, language and look, under a scrambled code made on your phone that isn\'t tied to you or your phone number. Your location is never kept.',
            ),
          ),
          _Para(
            tr(
              'لو بعتلنا رأيك أو شكوى من التطبيق: بنحفظ رسالتك، ونوعها، ونوع الموبايل ونسخة التطبيق، وطريقة التواصل لو كتبتها، عشان نقراها ونرد عليك.',
              'If you send us feedback from the app: we keep your message, its kind, the kind of phone and app version, and contact details if you give them, so we can read it and reply.',
            ),
          ),
          _Title(tr('المصادر', 'Sources')),
          _Para(
            tr(
              'المواعيد من مواقع السينمات نفسها ومن elCinema.com، والسينمات اللي جاية من elCinema مكتوب جنبها كده.',
              'Showtimes come from the cinemas\' own websites and from elCinema.com; cinemas listed via elCinema say so.',
            ),
          ),
          // TMDB's terms ask apps using its API to say so.
          _Para(
            tr(
              'بيانات وصور الأفلام من TMDB. التطبيق بيستخدم TMDB API ومش معتمد منهم.',
              'Film data and images from TMDB. This product uses the TMDB API but is not endorsed or certified by TMDB.',
            ),
          ),
          _Title(tr('اللي مش بنعمله', 'What we don\'t do')),
          _Bullet(
            tr(
              'مفيش إعلانات، ولا تتبّع، ولا تحليلات استخدام.',
              'No ads, no tracking, no usage analytics.',
            ),
          ),
          _Bullet(
            tr(
              'مش بنبيع ولا بنشارك أي بيانات مع حد.',
              'We don\'t sell or share any data with anyone.',
            ),
          ),
          _Title(tr('التواصل', 'Contact')),
          _Para(
            tr(
              'لأي سؤال عن الخصوصية كلّمنا على GitHub. لو غيّرنا السياسة دي هنحدّث التاريخ اللي فوق.',
              'Questions about privacy? Reach us on GitHub. If this policy changes, we\'ll update the date above.',
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(_contact),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: const Text('github.com/AbdallahSaeed0/3alshebbak'),
              style: TextButton.styleFrom(foregroundColor: AppColors.gold),
            ),
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 22, bottom: 6),
    child: Text(text, style: AppText.display(21, color: AppColors.gold)),
  );
}

class _Para extends StatelessWidget {
  const _Para(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: AppText.body(15).copyWith(height: 1.7)),
  );
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(top: 9, end: 10),
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: AppColors.gold,
              shape: BoxShape.circle,
            ),
          ),
        ),
        Expanded(
          child: Text(text, style: AppText.body(15).copyWith(height: 1.7)),
        ),
      ],
    ),
  );
}
