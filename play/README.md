# عالشباك على Google Play

كل اللي محتاجه عشان ترفع التطبيق: الملف، والصور، والنصوص، وإجابات الفورمز.

## 1. الملفات الجاهزة

| الحاجة | المكان |
|---|---|
| ملف الرفع (AAB) | `D:\3alShebbak-play\3alShebbak-0.2.2-play.aab` |
| أيقونة 512×512 | `play/store/icon-512.png` |
| صورة العرض 1024×500 | `play/store/feature-graphic.png` |
| 8 اسكرينات للموبايل 1080×1920 | `play/store/screenshot-1.png` … `screenshot-8.png` |
| سياسة الخصوصية | https://github.com/AbdallahSaeed0/3alshebbak/blob/main/PRIVACY.md |

نسخة Play مبنية بـ `--dart-define=STORE=play`: مفيهاش تنبيه التحديث من GitHub ولا زرار "دوّر على تحديث"، لأن Play بيمنع إن التطبيق يحدّث نفسه من بره المتجر. Play هو اللي هيحدّثه.

عشان تبني نسخة جديدة لـ Play (زوّد رقم البيلد في `pubspec.yaml` الأول، مثلًا `0.2.3+6`):

```
flutter build appbundle --release --dart-define=STORE=play
```

**المفتاح:** الملف متوقّع بمفتاحك `D:\3alShebbak-keys\shebbak-release.jks` (SHA-256 بيبدأ بـ `50:47:CB:CA`). على Play ده هيبقى **upload key**، وGoogle هتعمل مفتاح التوقيع النهائي (Play App Signing). حافظ على الـ jks والباسورد في مكان آمن: من غيرهم مش هتعرف ترفع تحديثات (ممكن تطلب reset من Google بس بياخد وقت).

ملحوظة: نسخة Play متوقّعة بمفتاح Google، فمش هتتثبّت فوق نسخة GitHub على نفس الموبايل. اللي عنده نسخة GitHub يمسحها الأول.

## 2. بيانات المتجر (Store listing)

**اسم التطبيق** (30 حرف بالكتير):
```
عالشباك - مواعيد السينما
```

**الوصف القصير** (80 حرف بالكتير):
```
مواعيد حفلات كل سينمات مصر في مكان واحد، وإشعار أول ما حجز فيلمك يفتح.
```

**الوصف الكامل:**
```
عالشباك بيجمعلك مواعيد حفلات السينمات في مصر كلها في مكان واحد: فوكس، وسين، ورينيسانس، وبريميير، وجلاكسي، وزاوية، وسينمات تانية كتير في القاهرة وإسكندرية والمحافظات.

🎬 كل المواعيد في مكان واحد
شوف الجاي في سينماتك، والأفلام اللي حجزها لسه نازل، وكل حفلات النهارده، من غير ما تلف على كل موقع لوحده.

🎟️ دوس على الميعاد واحجز
كل ميعاد بيوريك السينما والقاعة ونوع العرض (IMAX، 4DX، VIP…)، وزرار بيوديك تحجز على موقع السينما نفسها على طول.

🔔 إشعار أول ما الحجز يفتح
تابع الفيلم اللي مستنيه، وأول ما التذاكر تنزل أو تنزل مواعيد جديدة هيوصلك إشعار.

💬 اسأل عالشباك
شات بالاختيارات بس، من غير كتابة: اختار المدينة والفيلم واليوم، وهو يقولك المواعيد في كل سينما، الأقرب الأول.

📍 أقرب سينما ليك
كل السينمات على الخريطة، ومترتبة من الأقرب لمكانك.

👫 نروح سوا؟
علّم على كام ميعاد وابعتهم لصحابك في صورة شكلها حلو، يختاروا منها.

بدون حساب ولا تسجيل دخول، ومن غير إعلانات. الحجز والدفع بيتم على موقع السينما نفسه.

بيانات وصور الأفلام من TMDB. التطبيق مش تابع لأي سينما من السينمات المذكورة.
```

- **التصنيف (Category):** Entertainment
- **Tags:** Movies & TV, Showtimes
- **الإيميل اللي هيظهر في المتجر:** إيميلك (Play بيطلبه إجباري).
- **اللغة الافتراضية:** Arabic – ar

## 3. App content (الفورمز)

**Privacy policy:** الرابط اللي فوق.

**Ads:** No, my app does not contain ads.

**App access:** All functionality is available without special access (مفيش تسجيل دخول).

**Content rating** (استبيان IARC): Category = Reference, News, or Educational، أو Entertainment. جاوب No على كل أسئلة العنف والجنس والمخدرات والمقامرة. "Does the app allow users to interact or exchange content?" = No (المشاركة بتتم عن طريق تطبيقات تانية). النتيجة المتوقعة: 3+ / Everyone.

**Target audience:** 13+ أو 18+ (متختارش أي سن تحت 13، عشان متدخلش في سياسة Families).

**News app:** No.

**Government app:** No. **Financial features:** None. **Health:** No.

**Data safety:**

| السؤال | الإجابة |
|---|---|
| Does your app collect or share any of the required user data types? | Yes |
| Is all of the user data encrypted in transit? | Yes (HTTPS) |
| Do you provide a way for users to request that their data is deleted? | Yes (بالتواصل، والبيانات بتتمسح لوحدها لما التطبيق يتمسح) |
| **Device or other IDs** | Collected، مش Shared. الغرض: App functionality (الإشعارات). Not optional? → Optional (بس لو شغّلت الإشعارات). Processed ephemerally: No |
| **App activity → Other user-generated content** أو **App interactions** | الأفلام اللي بتتابعها والسينمات اللي اخترتها: Collected، مش Shared، الغرض: App functionality، Optional |
| **Location** | **مش Collected**: المكان بيتستخدم على الموبايل بس ومش بيتبعت لأي حد. (Google بتعتبر "collected" بس لو خرج من الجهاز.) |
| **Photos** | **مش Collected**: صور التذاكر بتفضل على الموبايل. |

**Permissions:** التطبيق بيطلب Location (تقريبي ودقيق، والتطبيق مفتوح بس) والإشعارات. مفيش background location، فمش محتاج فورم إضافي.

## 4. الخطوات اللي عليك أنت

1. **اعمل حساب مطوّر:** https://play.google.com/console — رسوم مرة واحدة 25 دولار، وتأكيد الهوية ببطاقتك. اختار **Personal** لو مش شركة.
2. **Create app:** الاسم "عالشباك"، Default language: Arabic، App (مش Game)، Free.
3. **اختبار مقفول (إجباري للحسابات الشخصية الجديدة):** لازم **12 شخص على الأقل** يشتركوا في Closed testing ويفضلوا مشتركين **14 يوم متواصلين** قبل ما تقدر تطلب Production.
   - Testing → Closed testing → Create track → ارفع الـ AAB.
   - ضيف إيميلات Gmail بتاعة الـ 12 (أو Google Group)، وابعتلهم لينك الاشتراك.
4. املأ **Store listing** و**App content** من الأقسام اللي فوق.
5. بعد الـ 14 يوم: **Apply for production**، جاوب على أسئلة الاختبار، وGoogle بتراجع (من كام ساعة لكام يوم).

**ممكن يتسأل:** صور الأفلام من TMDB، ومواعيد السينمات من مواقعها العامة. لو Google سألت عن حقوق المحتوى، قول إن التطبيق بيعرض مواعيد عامة وبيوجّه الحجز لموقع السينما نفسها، ومفيهوش أي بيع تذاكر.

## 5. بعد ما يبقى على Play

- كل تحديث: زوّد رقم البيلد في `pubspec.yaml`، وابني الـ AAB بالأمر اللي فوق، وارفعه في نفس الـ track.
- نسخة GitHub (APK) ممكن تفضل شغالة للتجربة، بس الأحسن توجّه الناس للينك Play بعد ما ينزل.
