# Exevra — Intelligent Financial Telemetry & Collaborative Expense Tracking

<div align="center">
  <img src="assets/icons/app_icon.png" width="128" height="128" alt="Exevra App Icon" style="border-radius: 28px; box-shadow: 0 10px 30px rgba(0, 229, 255, 0.3);" />
  <h3>Exevra (formerly Antigravity Expenses)</h3>
  <p><em>Elite mobile financial intelligence engine built with Flutter, Riverpod, and Supabase.</em></p>

  [![Flutter](https://img.shields.io/badge/Flutter-3.12+-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
  [![Dart](https://img.shields.io/badge/Dart-3.12+-0175C2?logo=dart&logoColor=white)](https://dart.dev)
  [![Supabase](https://img.shields.io/badge/Backend-Supabase_PostgreSQL-3ECF8E?logo=supabase&logoColor=white)](https://supabase.com)
  [![License](https://img.shields.io/badge/License-Proprietary-blue.svg)]()
</div>

---

## 🌟 Executive Overview

**Exevra** is a 100% production-ready, highly scalable, and beautifully animated financial intelligence and collaborative expense tracking application. Tailored for an initial launch in **India** with native **INR (₹)** currency formatting and Indian numbering notation (Lakhs and Crores), Exevra seamlessly synchronizes personal and collaborative household expenditures with PostgreSQL Row-Level Security, hardware-backed biometric security gates, timezone-aware temporal telemetry, and an automated multi-model AI financial assistant.

---

## ✨ Key Features & Capabilities

### 1. 🇮🇳 Native Indian Rupee (INR) Default
- Default active currency is **INR (₹)** across all profiles, dashboards, and expense entries.
- Native compact Indian number formatting: values above ₹1,00,000 format as **₹1.0L** and values above ₹1,00,00,000 format as **₹1.0Cr**.
- International currency switcher supports USD, EUR, GBP, JPY, CAD, AUD, and SGD.

### 2. 👥 Collaborative Group Budgets & Granular Permission Matrix
- **Admin vs. Member vs. Viewer Permission Hierarchy**:
  - **Group Admin**: Creator of the group. Full control to record expenses, delete any group expense, invite members, and review/approve pending join requests.
  - **Approved Member**: Can record group expenses, edit their own expenses, view group telemetry, and invite friends.
  - **Viewer (Pending Review)**: When a member invites a new user, they join as a **Viewer** with read-only access to group telemetry. They **cannot add group expenses until reviewed and approved by the Group Admin**.
- **In-App Member Review Panel**: Group Admins see pending viewers in their Account & Settings tab with a one-tap `Approve` button that instantly unlocks expense recording access.
- **Enforced at the Database Layer**: PostgreSQL Row-Level Security (RLS) policies mathematically reject group expense inserts from unapproved viewers.

### 3. ⏰ Timezone-Aware Temporal Telemetry
- All expenses record exact hours, minutes, and dates in the user's local timezone.
- Interactive Date & Time picker ensures timestamps capture the exact moment an expenditure occurred.
- Expenses are persisted in UTC / ISO 8601 timestamps and reactively formatted back to the user's local device timezone (`Asia/Kolkata`, etc.).

### 4. 🔒 Hardware-Backed Biometric Security Gate
- App Lock powered by `local_auth` (Face ID / Fingerprint / Device Passcode).
- Background lifecycle protection with a 30-second security timeout window.
- Cold launch and resume validation prevents unauthorized visual snooping.

### 5. 🤖 Multi-Tier AI Financial Assistant with Privacy Firewall
- Resilient waterfall failover:
  1. **Google Gemini API** (`gemini-2.5-flash` streaming)
  2. **OpenAI API** (`gpt-4o-mini`)
  3. **Anthropic Claude API** (`claude-3-5-haiku`)
  4. **DeepSeek API** (`deepseek-chat`)
  5. **On-Device Heuristic Engine** (100% offline safety net)
- **Privacy Firewall**: Zero expense telemetry is sent to AI models when AI Consent is toggled OFF.
- **Financial Scope Guardrails**: Automatically filters out non-financial queries.

### 6. 📧 Custom Branded Supabase Verification Emails
- Includes a dedicated modern, dark glassmorphic HTML email verification template (`supabase/email_templates/confirm_signup.html`).
- Prevents generic unbranded emails and fixes default `localhost:3000` redirect deadlocks.

---

## 🏗️ Architectural Foundation

```
lib/
├── core/
│   ├── constants/       # AppConstants, AppColors, Asset references
│   ├── router/          # GoRouter with strict email & biometric guards
│   ├── theme/           # Tri-mode dark/light/system glassmorphic theme
│   └── utils/           # CurrencyFormatter (INR L/Cr), DateHelpers, Validators, Haptics
├── features/
│   ├── auth/            # Login, Register, Phone OTP, Verify Email, App Lock
│   ├── dashboard/       # Ambient telemetry, category breakdown, quick action FAB
│   ├── expenses/        # Personal & Group expense CRUD, receipt scanning, filters
│   ├── insights/        # FlChart analytics, trend lines, donut breakdown
│   ├── chatbot/         # Streaming AI financial conversation interface
│   └── profile/         # Account management, Group admin review, currency switcher
├── models/              # Immutable data entities (Expense, UserProfile, ExpenseGroup, GroupMember)
├── providers/           # Riverpod state notifiers (Auth, Expense, Insights, Chat, AppLock)
└── services/            # SupabaseService, AuthService, AiChatbotService
```

---

## 🚀 Getting Started

### 1. Prerequisites
- Flutter SDK `^3.12.0`
- Android Studio / Xcode
- Supabase Project

### 2. Environment Configuration
Create a `.env` file in the project root:
```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-supabase-publishable-key
GEMINI_API_KEY=your-gemini-api-key
```

### 3. Database Setup (Supabase PostgreSQL)
1. Open your **Supabase Dashboard** $\rightarrow$ **SQL Editor**.
2. Copy and run the entire contents of [`supabase/schema.sql`](supabase/schema.sql).
3. This creates all 4 tables (`profiles`, `groups`, `group_members`, `expenses`), enables RLS, and sets up triggers.

### 4. Custom Email Verification Template
1. In the Supabase Dashboard, go to **Authentication** $\rightarrow$ **Email Templates** $\rightarrow$ **Confirm signup**.
2. Set the subject: `Verify your email for Exevra | Intelligent Financial Telemetry`
3. Paste the contents of [`supabase/email_templates/confirm_signup.html`](supabase/email_templates/confirm_signup.html) into the body editor and click **Save**.

### 5. Run & Test
```bash
# Analyze code
flutter analyze

# Run unit & widget test suite
flutter test

# Run app on connected device
flutter run

# Build release APK
flutter build apk --release
```

---

## 📱 App Icon Generation
The native launcher icons for Android and iOS are generated using `flutter_launcher_icons`:
```bash
dart run flutter_launcher_icons
```
The master vector assets are located in `assets/icons/app_icon.png` and `assets/icons/app_icon_foreground.png`.

---

## 📄 License
Copyright &copy; 2026 Bharat Sharma. All rights reserved.
