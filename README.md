# Campus Connect — Supabase Backend Guide

This document describes the complete backend architecture, PostgreSQL database schema, security rules, and setup instructions for **Campus Connect**.

---

## 1. Architecture Overview

- **Primary Backend:** [Supabase](https://supabase.com) (PostgreSQL 15+, Supabase Auth, Row Level Security, Realtime).
- **Client Technology:** Vanilla JavaScript (ES6+), official `@supabase/supabase-js@2` via CDN.
- **Access Control:** PostgreSQL Row Level Security (RLS) on all 10 application tables.
- **Session Management:** Persistent Supabase JWT sessions stored in browser `localStorage`.
- **Realtime Updates:** Supabase Realtime websocket channels for instant feed and Q&A sync.

---

## 2. Database Schema (`supabase/schema.sql`)

### Tables & Relationships

| Table Name | Primary Key | Description | Foreign Keys / Constraints |
| :--- | :--- | :--- | :--- |
| `profiles` | `id (UUID)` | Student profile details (name, major, bio, interests, avatar) | References `auth.users(id)` ON DELETE CASCADE |
| `communities` | `id (TEXT)` | 10 Campus clubs & interest communities | Unique `slug` |
| `community_members` | `(community_id, user_id)` | Student club memberships | References `communities(id)`, `profiles(id)` |
| `messages` | `id (UUID)` | Community feed discussion posts | References `communities(id)`, `profiles(id)` |
| `message_likes` | `(message_id, user_id)` | Peer reactions to community messages | References `messages(id)`, `profiles(id)` |
| `questions` | `id (UUID)` | Academic doubts posted by students | References `profiles(id)` |
| `answers` | `id (UUID)` | Explanations and peer solutions to doubts | References `questions(id)`, `profiles(id)` |
| `helpful_votes` | `(answer_id, user_id)` | Upvotes for clear academic explanations | References `answers(id)`, `profiles(id)` |
| `activities` | `id (UUID)` | Campus events, study jams, and meetups | References `profiles(id)` |
| `activity_members` | `(activity_id, user_id)` | Student RSVPs to campus activities | References `activities(id)`, `profiles(id)` |

---

## 3. Row Level Security (RLS) Policies

Every table has RLS enabled:

- **`profiles`**:
  - `SELECT`: Publicly readable so students can identify authors and peer members.
  - `INSERT` / `UPDATE`: Restricted strictly to `auth.uid() = id`.
- **`communities`**:
  - `SELECT`: Publicly readable by all students.
  - `INSERT`: Restricted to authenticated users.
- **`community_members`**:
  - `SELECT`: Publicly readable (powers community member count & directory).
  - `INSERT` / `DELETE`: Restricted strictly to `auth.uid() = user_id`.
- **`messages`**:
  - `SELECT`: Publicly readable.
  - `INSERT`: Restricted to authenticated users (`auth.uid() = user_id`).
  - `UPDATE` / `DELETE`: Author-only (`auth.uid() = user_id`).
- **`message_likes`**:
  - `SELECT`: Publicly readable.
  - `INSERT` / `DELETE`: Authenticated user's own like (`auth.uid() = user_id`).
- **`questions` & `answers`**:
  - `SELECT`: Publicly readable.
  - `INSERT`: Authenticated author (`auth.uid() = author_id`).
  - `UPDATE` / `DELETE`: Author-only.
- **`helpful_votes`**:
  - `SELECT`: Publicly readable.
  - `INSERT` / `DELETE`: 1 vote per student per answer (`auth.uid() = user_id`).
- **`activities` & `activity_members`**:
  - `SELECT`: Publicly readable.
  - `INSERT` / `DELETE`: Authenticated user's own RSVP (`auth.uid() = user_id`).
  - Trigger `trigger_check_activity_capacity` enforces capacity limits safely before insert.

---

## 4. Setup Instructions (3 Steps)

### Step 1: Create a Supabase Project
1. Log in to [supabase.com](https://supabase.com) and click **"New Project"**.
2. Give your project a name (e.g. `campus-connect`) and choose a strong database password.
3. Once provisioned, go to **Project Settings** → **API**.
4. Copy your **Project URL** (`https://xyzcompany.supabase.co`) and **Project API Key** (`anon` `public`).

### Step 2: Execute Schema & Seed Script
1. In your Supabase Dashboard, click on the **SQL Editor** icon in the left navigation.
2. Click **"New query"**.
3. Copy the entire contents of [`supabase/schema.sql`](schema.sql) and paste into the editor.
4. Click **Run** (`Ctrl+Enter`).
5. Confirm that tables, triggers, policies, and the 10 seeded communities are created successfully.

### Step 3: Connect Frontend to Supabase
You can connect the frontend using either of these two methods:

#### Method A: In-App UI (Fastest)
1. Open `index.html` in your browser.
2. Click the **"Backend Status"** badge or the **"⚙️ Backend Settings"** button in the top navigation or footer.
3. Paste your **Supabase URL** and **Anon Key**.
4. Click **"Test & Save Credentials"**.
5. The badge will turn green (**"🟢 Connected to Supabase"**), and all features will immediately start syncing with your live database.

#### Method B: Configuration File
1. Open `supabase-config.js` in your code editor.
2. Update the `DEFAULT_CONFIG` object with your project credentials:
   ```javascript
   const DEFAULT_CONFIG = {
     SUPABASE_URL: 'https://your-project.supabase.co',
     SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIsIn...'
   };
   ```
3. Refresh `index.html`.

---

## 5. Authentication Configuration (Supabase Dashboard)

1. In Supabase Dashboard, navigate to **Authentication** → **Providers** → **Email**.
2. Verify **Enable Email provider** is turned **ON**.
3. (Optional) For rapid development or local hackathon testing, you can disable **"Confirm email"** to allow students to log in immediately upon sign up without clicking an email link.
4. If **"Confirm email"** is kept ON, Campus Connect detects unconfirmed accounts and displays a clear alert asking the student to check their inbox.

---

## 6. Realtime Verification

The schema automatically publishes changes on `messages`, `questions`, `answers`, `helpful_votes`, `activities`, and `activity_members` to the `supabase_realtime` publication.

To verify:
1. Open two separate browser windows (or one incognito window).
2. Log in with different student accounts in each.
3. Post a message in the **Coding Community** or ask a doubt in **Doubt Solving**.
4. Observe the post appearing instantaneously in the second window without refreshing.
