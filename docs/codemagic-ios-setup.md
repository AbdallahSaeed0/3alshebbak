# iOS build on Codemagic: manual setup checklist

The build config is `codemagic.yaml` in the repo root (workflow `ios-testflight`).
Do these steps once, in order. Never paste the `.p8` key into chat or commit it.

1. **Sign up.** Go to codemagic.io, click **Sign up** / **Log in** and choose **GitHub**. Authorize Codemagic.
2. **Add the repo.** Codemagic > **Applications** > **Add application**. Pick the GitHub account, select `AbdallahSaeed0/3alshebbak`, choose **Flutter App** as the project type, then finish. Codemagic will detect `codemagic.yaml` at the repo root. (Commit and push the file to `main` first, since Codemagic reads it from GitHub.)
3. **Create the App Store Connect API key.** In App Store Connect: **Users and Access** > **Integrations** > **App Store Connect API** > **Team Keys** > **Generate API Key** (the + button). Name it `Codemagic`, set access to **App Manager**. Download the `.p8` file (you can download it only once). Note the **Key ID** and the **Issuer ID** shown at the top of the page.
   - The `.p8` is a secret. Keep it out of chat, email and git.
4. **Upload the key to Codemagic.** Codemagic > **Teams** > your team > **Integrations** > **Developer Portal** (Apple) > **Connect**. Set the integration name to exactly `Codemagic` (capital C, must match `integrations: app_store_connect: Codemagic` in the yaml). If a key with that name already exists, skip creating a new one, enter Issuer ID, Key ID, and upload the `.p8`. Save.
5. **Create the app record** in App Store Connect: **Apps** > **+** > **New App**, platform iOS, bundle ID `com.shebbak.shebbak`, pick a name and SKU.
6. **Put the app's Apple ID in the yaml.** App Store Connect > your app > **App Information** > **General Information** > **Apple ID** (a ~10-digit number). Replace `APP_STORE_APPLE_ID: "0000000000"` in `codemagic.yaml`, or add `APP_STORE_APPLE_ID` as an environment variable in Codemagic (app > **Environment variables**). Without it the build number lookup fails.
7. **Start the first build.** Codemagic > your app > **Start new build**, choose branch `main` and workflow **iOS TestFlight**. Codemagic creates the distribution certificate and App Store provisioning profile automatically.
8. **Find it in TestFlight.** After the build finishes and Apple processes it (often 5 to 30 minutes), open App Store Connect > your app > **TestFlight** > **iOS Builds**. Add yourself as an internal tester under **Internal Testing**, then install via the TestFlight app on your iPhone.

Notes
- Builds are manual only; no build starts on push.
- Each run uses the latest TestFlight build number + 1 and the version from `app/pubspec.yaml`.
- Push notifications (Firebase) are not set up on iOS; the app runs without them.
