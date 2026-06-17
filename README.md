# Restaurant Nutrition App

A mobile app for the Israeli market: type a restaurant name → the app fetches
and stores its real menu → pick dishes into an "assessment" → an AI returns an
estimated nutrition breakdown per dish and combined. All numbers are
**AI estimates shown as ranges — not medical advice.**

The full product plan and session-by-session breakdown live in
[restaurant-nutrition-app-build-plan_1.md](restaurant-nutrition-app-build-plan_1.md).

## Repo layout

```
/app                         Flutter client (Android + iOS + web, Hebrew/RTL)
  /lib
    /config                  AppConfig — reads SUPABASE_URL/ANON_KEY from --dart-define
    /services                supabase_service.dart — anon client init + accessor
    /features/{search,menu,assessment,home}
    /models
  dart_define.example.json   Template for client config (copy → dart_define.json)
/supabase
  /functions/{fetch-menu,estimate-dishes,resolve-restaurant}
  /functions/_shared         shared CORS helper
  /functions/.env.example    Template for server-side function secrets
  /migrations                SQL schema
```

## Non-negotiable security rule

The Flutter client only ever holds the **Supabase URL + anon key**. Every
privileged key (AI / Google Places / web-search, and the Supabase service-role
key) lives **only** in Supabase Edge Function secrets. All model calls go:
client → Edge Function → model API → back.

## Toolchain (already installed on this machine)

- Flutter `3.44.2` (Dart `3.12.2`) at `C:\src\flutter`
- Android SDK 36 + build-tools 36 (`flutter doctor` Android toolchain green)
- Supabase CLI `2.107.0` at `C:\src\supabase`
- JDK 17 (Adoptium) — Flutter configured via `flutter config --jdk-dir`

> iOS builds require macOS, so on Windows we develop/test on **Android + web**.
> The `ios/` folder is generated and kept for later Mac builds.

## Getting started

### 1. Client config

```bash
cd app
cp dart_define.example.json dart_define.json    # then fill in real values
```

`dart_define.json` is gitignored. Fill it with your Supabase project URL and
anon key (Project Settings → API).

### 2. Run the app

```bash
cd app
flutter pub get
flutter run -d chrome --dart-define-from-file=dart_define.json
# or an Android device/emulator:
flutter run -d <device-id> --dart-define-from-file=dart_define.json
```

The Session 0 home screen has a **"בדיקת חיבור ל-Supabase"** button that
round-trips a row through the `pings` table to confirm connectivity.

### 3. Backend (Supabase)

```bash
# Apply migrations to your linked project
supabase link --project-ref <your-project-ref>
supabase db push

# Function secrets (server-side only)
cp supabase/functions/.env.example supabase/functions/.env   # fill in, for local serve
supabase functions serve --env-file supabase/functions/.env  # local
# or deploy:
supabase functions deploy fetch-menu estimate-dishes resolve-restaurant
supabase secrets set ANTHROPIC_API_KEY=... GOOGLE_PLACES_API_KEY=... SEARCH_API_KEY=...
```

## Status

**Session 0 (setup & foundations) — in progress.** Flutter app scaffolded with
Hebrew/RTL, Supabase client wiring, three Edge Function stubs that read their
secrets server-side, and a `pings` connectivity-test table. Next: Session 1
(full Postgres schema).
