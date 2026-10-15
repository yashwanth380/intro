-- ============================================================================
-- CAMPUS CONNECT — COMPLETE SUPABASE POSTGRESQL SCHEMA & SECURITY
-- ============================================================================
-- Safe, normalized, idempotent migration script with Row Level Security (RLS),
-- triggers, indexes, and initial community & activity seeds.
-- ============================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ----------------------------------------------------------------------------
-- 2. TABLES DEFINITIONS
-- ----------------------------------------------------------------------------

-- PROFILES: Student profiles linked to auth.users
CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT NOT NULL,
  username TEXT UNIQUE,
  bio TEXT DEFAULT 'Campus Connect Student',
  major TEXT DEFAULT 'General Studies',
  avatar_url TEXT,
  interests TEXT[] DEFAULT ARRAY['Campus Life'],
  skills TEXT[] DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- COMMUNITIES: Interest & academic clubs
CREATE TABLE IF NOT EXISTS public.communities (
  id TEXT PRIMARY KEY, -- Slug identifier (e.g. 'coding', 'dance')
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  description TEXT NOT NULL,
  category TEXT NOT NULL,
  icon TEXT NOT NULL,
  tags TEXT[] DEFAULT '{}',
  guidelines TEXT[] DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- COMMUNITY MEMBERS: Joins between students and communities
CREATE TABLE IF NOT EXISTS public.community_members (
  community_id TEXT NOT NULL REFERENCES public.communities(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
  PRIMARY KEY (community_id, user_id)
);

-- MESSAGES: Real-time community discussion posts
CREATE TABLE IF NOT EXISTS public.messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  community_id TEXT NOT NULL REFERENCES public.communities(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMPTZ
);

-- MESSAGE LIKES: Peer reactions to community messages
CREATE TABLE IF NOT EXISTS public.message_likes (
  message_id UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
  PRIMARY KEY (message_id, user_id)
);

-- QUESTIONS: Peer-to-peer academic doubts
CREATE TABLE IF NOT EXISTS public.questions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  subject TEXT NOT NULL,
  tags TEXT[] DEFAULT '{}',
  is_solved BOOLEAN DEFAULT false NOT NULL,
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- ANSWERS: Explanations posted to questions
CREATE TABLE IF NOT EXISTS public.answers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  question_id UUID NOT NULL REFERENCES public.questions(id) ON DELETE CASCADE,
  author_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- HELPFUL VOTES: Peer votes for quality answers
CREATE TABLE IF NOT EXISTS public.helpful_votes (
  answer_id UUID NOT NULL REFERENCES public.answers(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
  PRIMARY KEY (answer_id, user_id)
);

-- ACTIVITIES: Low-pressure student events and meetups
CREATE TABLE IF NOT EXISTS public.activities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  title TEXT NOT NULL,
  description TEXT NOT NULL,
  category TEXT NOT NULL,
  date_label TEXT NOT NULL,
  starts_at TIMESTAMPTZ,
  location_label TEXT NOT NULL,
  capacity INTEGER,
  created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- ACTIVITY MEMBERS: RSVPs to campus activities
CREATE TABLE IF NOT EXISTS public.activity_members (
  activity_id UUID NOT NULL REFERENCES public.activities(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
  PRIMARY KEY (activity_id, user_id)
);

-- ----------------------------------------------------------------------------
-- 3. PERFORMANCE INDEXES
-- ----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_profiles_username ON public.profiles(username);
CREATE INDEX IF NOT EXISTS idx_community_members_user ON public.community_members(user_id);
CREATE INDEX IF NOT EXISTS idx_community_members_comm ON public.community_members(community_id);
CREATE INDEX IF NOT EXISTS idx_messages_community ON public.messages(community_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_user ON public.messages(user_id);
CREATE INDEX IF NOT EXISTS idx_message_likes_user ON public.message_likes(user_id);
CREATE INDEX IF NOT EXISTS idx_questions_subject ON public.questions(subject, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_questions_author ON public.questions(author_id);
CREATE INDEX IF NOT EXISTS idx_answers_question ON public.answers(question_id, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_answers_author ON public.answers(author_id);
CREATE INDEX IF NOT EXISTS idx_helpful_votes_user ON public.helpful_votes(user_id);
CREATE INDEX IF NOT EXISTS idx_activities_category ON public.activities(category, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_activities_creator ON public.activities(creator_id);
CREATE INDEX IF NOT EXISTS idx_activity_members_user ON public.activity_members(user_id);
CREATE INDEX IF NOT EXISTS idx_activity_members_act ON public.activity_members(activity_id);

-- ----------------------------------------------------------------------------
-- 4. TRIGGERS & AUTOMATION FUNCTIONS
-- ----------------------------------------------------------------------------

-- Auto-update updated_at timestamp function
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = timezone('utc'::text, now());
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for profiles updated_at
DROP TRIGGER IF EXISTS trigger_profiles_updated_at ON public.profiles;
CREATE TRIGGER trigger_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Trigger for questions updated_at
DROP TRIGGER IF EXISTS trigger_questions_updated_at ON public.questions;
CREATE TRIGGER trigger_questions_updated_at
  BEFORE UPDATE ON public.questions
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Trigger for answers updated_at
DROP TRIGGER IF EXISTS trigger_answers_updated_at ON public.answers;
CREATE TRIGGER trigger_answers_updated_at
  BEFORE UPDATE ON public.answers
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Auto-create student profile on user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  extracted_name TEXT;
  extracted_major TEXT;
  extracted_username TEXT;
BEGIN
  extracted_name := COALESCE(
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'name',
    split_part(NEW.email, '@', 1)
  );

  extracted_major := COALESCE(
    NEW.raw_user_meta_data->>'major',
    'Undergraduate Student'
  );

  extracted_username := COALESCE(
    NEW.raw_user_meta_data->>'username',
    split_part(NEW.email, '@', 1) || '_' || substr(NEW.id::text, 1, 4)
  );

  INSERT INTO public.profiles (id, display_name, username, bio, major, avatar_url, interests)
  VALUES (
    NEW.id,
    extracted_name,
    extracted_username,
    'Passionate student connecting with campus peers, clubs, and study groups.',
    extracted_major,
    upper(substr(extracted_name, 1, 2)),
    ARRAY['Web Development', 'Algorithms', 'Campus Life']
  )
  ON CONFLICT (id) DO UPDATE SET
    display_name = EXCLUDED.display_name,
    updated_at = timezone('utc'::text, now());

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Enforce activity capacity limit safely
CREATE OR REPLACE FUNCTION public.check_activity_capacity()
RETURNS TRIGGER AS $$
DECLARE
  act_capacity INTEGER;
  current_count INTEGER;
BEGIN
  SELECT capacity INTO act_capacity FROM public.activities WHERE id = NEW.activity_id;
  IF act_capacity IS NOT NULL THEN
    SELECT count(*) INTO current_count FROM public.activity_members WHERE activity_id = NEW.activity_id;
    IF current_count >= act_capacity THEN
      RAISE EXCEPTION 'Activity capacity reached (Limit: % students).', act_capacity;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_check_activity_capacity ON public.activity_members;
CREATE TRIGGER trigger_check_activity_capacity
  BEFORE INSERT ON public.activity_members
  FOR EACH ROW EXECUTE FUNCTION public.check_activity_capacity();

-- ----------------------------------------------------------------------------
-- 5. ROW LEVEL SECURITY (RLS) POLICIES
-- ----------------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.communities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.community_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.message_likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.answers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.helpful_votes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activity_members ENABLE ROW LEVEL SECURITY;

-- PROFILES POLICIES
DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.profiles;
CREATE POLICY "Public profiles are viewable by everyone"
  ON public.profiles FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;
CREATE POLICY "Users can insert their own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
CREATE POLICY "Users can update their own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

-- COMMUNITIES POLICIES
DROP POLICY IF EXISTS "Communities are viewable by everyone" ON public.communities;
CREATE POLICY "Communities are viewable by everyone"
  ON public.communities FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Authenticated users can create communities" ON public.communities;
CREATE POLICY "Authenticated users can create communities"
  ON public.communities FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- COMMUNITY MEMBERS POLICIES
DROP POLICY IF EXISTS "Community memberships viewable by everyone" ON public.community_members;
CREATE POLICY "Community memberships viewable by everyone"
  ON public.community_members FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Students can join communities" ON public.community_members;
CREATE POLICY "Students can join communities"
  ON public.community_members FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Students can leave communities" ON public.community_members;
CREATE POLICY "Students can leave communities"
  ON public.community_members FOR DELETE
  USING (auth.uid() = user_id);

-- MESSAGES POLICIES
DROP POLICY IF EXISTS "Messages viewable by everyone" ON public.messages;
CREATE POLICY "Messages viewable by everyone"
  ON public.messages FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Authenticated students can post messages" ON public.messages;
CREATE POLICY "Authenticated students can post messages"
  ON public.messages FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Authors can update their messages" ON public.messages;
CREATE POLICY "Authors can update their messages"
  ON public.messages FOR UPDATE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Authors can delete their messages" ON public.messages;
CREATE POLICY "Authors can delete their messages"
  ON public.messages FOR DELETE
  USING (auth.uid() = user_id);

-- MESSAGE LIKES POLICIES
DROP POLICY IF EXISTS "Message likes viewable by everyone" ON public.message_likes;
CREATE POLICY "Message likes viewable by everyone"
  ON public.message_likes FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Authenticated students can like messages" ON public.message_likes;
CREATE POLICY "Authenticated students can like messages"
  ON public.message_likes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Students can remove their own like" ON public.message_likes;
CREATE POLICY "Students can remove their own like"
  ON public.message_likes FOR DELETE
  USING (auth.uid() = user_id);

-- QUESTIONS POLICIES
DROP POLICY IF EXISTS "Questions viewable by everyone" ON public.questions;
CREATE POLICY "Questions viewable by everyone"
  ON public.questions FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Authenticated students can ask questions" ON public.questions;
CREATE POLICY "Authenticated students can ask questions"
  ON public.questions FOR INSERT
  WITH CHECK (auth.uid() = author_id);

DROP POLICY IF EXISTS "Authors can update their questions" ON public.questions;
CREATE POLICY "Authors can update their questions"
  ON public.questions FOR UPDATE
  USING (auth.uid() = author_id);

DROP POLICY IF EXISTS "Authors can delete their questions" ON public.questions;
CREATE POLICY "Authors can delete their questions"
  ON public.questions FOR DELETE
  USING (auth.uid() = author_id);

-- ANSWERS POLICIES
DROP POLICY IF EXISTS "Answers viewable by everyone" ON public.answers;
CREATE POLICY "Answers viewable by everyone"
  ON public.answers FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Authenticated students can answer questions" ON public.answers;
CREATE POLICY "Authenticated students can answer questions"
  ON public.answers FOR INSERT
  WITH CHECK (auth.uid() = author_id);

DROP POLICY IF EXISTS "Authors can update their answers" ON public.answers;
CREATE POLICY "Authors can update their answers"
  ON public.answers FOR UPDATE
  USING (auth.uid() = author_id);

DROP POLICY IF EXISTS "Authors can delete their answers" ON public.answers;
CREATE POLICY "Authors can delete their answers"
  ON public.answers FOR DELETE
  USING (auth.uid() = author_id);

-- HELPFUL VOTES POLICIES
DROP POLICY IF EXISTS "Helpful votes viewable by everyone" ON public.helpful_votes;
CREATE POLICY "Helpful votes viewable by everyone"
  ON public.helpful_votes FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Authenticated students can vote helpful" ON public.helpful_votes;
CREATE POLICY "Authenticated students can vote helpful"
  ON public.helpful_votes FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Students can withdraw helpful vote" ON public.helpful_votes;
CREATE POLICY "Students can withdraw helpful vote"
  ON public.helpful_votes FOR DELETE
  USING (auth.uid() = user_id);

-- ACTIVITIES POLICIES
DROP POLICY IF EXISTS "Activities viewable by everyone" ON public.activities;
CREATE POLICY "Activities viewable by everyone"
  ON public.activities FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Authenticated students can create activities" ON public.activities;
CREATE POLICY "Authenticated students can create activities"
  ON public.activities FOR INSERT
  WITH CHECK (auth.uid() = creator_id);

DROP POLICY IF EXISTS "Creators can update their activities" ON public.activities;
CREATE POLICY "Creators can update their activities"
  ON public.activities FOR UPDATE
  USING (auth.uid() = creator_id);

DROP POLICY IF EXISTS "Creators can delete their activities" ON public.activities;
CREATE POLICY "Creators can delete their activities"
  ON public.activities FOR DELETE
  USING (auth.uid() = creator_id);

-- ACTIVITY MEMBERS POLICIES
DROP POLICY IF EXISTS "Activity RSVPs viewable by everyone" ON public.activity_members;
CREATE POLICY "Activity RSVPs viewable by everyone"
  ON public.activity_members FOR SELECT
  USING (true);

DROP POLICY IF EXISTS "Students can RSVP to activities" ON public.activity_members;
CREATE POLICY "Students can RSVP to activities"
  ON public.activity_members FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Students can cancel their RSVP" ON public.activity_members;
CREATE POLICY "Students can cancel their RSVP"
  ON public.activity_members FOR DELETE
  USING (auth.uid() = user_id);

-- ----------------------------------------------------------------------------
-- 6. REALTIME SUBSCRIPTIONS SETUP
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.messages;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'message_likes'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.message_likes;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'questions'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.questions;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'answers'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.answers;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'helpful_votes'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.helpful_votes;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'activities'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.activities;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'activity_members'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.activity_members;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'community_members'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.community_members;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 7. SEED DATA FOR THE 10 COMMUNITIES
-- ----------------------------------------------------------------------------
INSERT INTO public.communities (id, name, slug, description, category, icon, tags, guidelines)
VALUES
  (
    'dance',
    'Dance Room',
    'dance-room',
    'A vibrant, welcoming studio community for dancers of all levels. From hip-hop and freestyle to classical and choreography.',
    'Arts & Culture',
    '💃',
    ARRAY['Hip-Hop', 'Freestyle', 'Choreography', 'Beginners Welcome'],
    ARRAY['All skill levels are warmly celebrated — zero intimidation.', 'Arrive on time for studio warm-ups and wear comfortable sneakers.', 'Support your fellow dancers with constructive hype and encouragement.']
  ),
  (
    'doubt-solving',
    'Doubt Solving',
    'doubt-solving',
    'Peer-to-peer academic support network. Ask tough assignment questions, clarify lecture concepts, and share study notes.',
    'Academics',
    '💡',
    ARRAY['Math', 'Algorithms', 'Physics', 'Circuits', 'Assignments'],
    ARRAY['Explain what you have already tried before asking for the solution.', 'Respect academic integrity: focus on conceptual clarity, not cheating.', 'Upvote clear, helpful answers to reward peer contributors.']
  ),
  (
    'coding',
    'Coding Community',
    'coding-community',
    'Collaborate on open source, practice LeetCode and DSA, build hackathon projects, and discuss software engineering trends.',
    'Technology',
    '💻',
    ARRAY['Web Dev', 'Python', 'Algorithms', 'Open Source', 'Hackathons'],
    ARRAY['Format code snippets cleanly using markdown formatting.', 'Beginners are sacred: never make anyone feel small for simple questions.', 'Team recruitment posts must include project stack and timeline.']
  ),
  (
    'gaming',
    'Gaming Lounge',
    'gaming-lounge',
    'Casual gaming sessions, campus esports scrims, board games, and friendly banter across PC, consoles, and mobile titles.',
    'Recreation',
    '🎮',
    ARRAY['Valorant', 'Chess', 'BGMI', 'Steam', 'Console Meetups'],
    ARRAY['Good sportsmanship at all times. Toxic behavior results in an immediate ban.', 'Include game rank and region when searching for party teammates.', 'Casual players and high-rank competitive players are both respected.']
  ),
  (
    'music',
    'Music Corner',
    'music-corner',
    'Acoustic jam circles, band rehearsals, songwriting, and discovering new music genres together on campus lawns.',
    'Arts & Culture',
    '🎵',
    ARRAY['Guitar', 'Vocals', 'Indie Rock', 'Jam Sessions', 'Production'],
    ARRAY['Respect shared jam room equipment and pack up chords neatly.', 'Feedback on original music must be encouraging and empathetic.', 'Open jams welcome all instruments from ukulele to synthesizers.']
  ),
  (
    'art-creativity',
    'Art and Creativity',
    'art-and-creativity',
    'Sketching, painting, digital illustration, origami, calligraphy, and creative design workshops for expressive minds.',
    'Arts & Culture',
    '🎨',
    ARRAY['Digital Art', 'Sketching', 'Watercolor', 'Crafts', 'UI/UX'],
    ARRAY['Always credit original reference artists when sharing studies.', 'Constructive critiques are welcomed only when explicitly requested by the artist.', 'Have fun experimenting without fear of perfection.']
  ),
  (
    'placement',
    'Placement Preparation',
    'placement-preparation',
    'Interview preparation, aptitude drills, resume teardowns, behavioral mock interviews, and career opportunity sharing.',
    'Academics',
    '💼',
    ARRAY['Resumes', 'Aptitude', 'System Design', 'Mock Interviews', 'Internships'],
    ARRAY['Anonymize personal contact info before sharing resumes for public review.', 'Share accurate interview experiences to help incoming juniors.', 'Keep discussions professional and supportive.']
  ),
  (
    'sports',
    'Sports Community',
    'sports-community',
    'Football, basketball pick-up games, badminton ladders, morning runs, and campus athletics leagues.',
    'Athletics',
    '⚽',
    ARRAY['Football', 'Badminton', 'Basketball', 'Morning Runs', 'Fitness'],
    ARRAY['Fair play over winning: safety and camaraderie come first.', 'Clean up courts and return balls to the equipment counter.', 'Confirm RSVP numbers so matches can be scheduled accurately.']
  ),
  (
    'project-collab',
    'Project Collaboration',
    'project-collaboration',
    'Find teammates with complementary skills for engineering capstone projects, startup ideas, and research initiatives.',
    'Technology',
    '🚀',
    ARRAY['Capstones', 'Startups', 'Teammates', 'Hardware', 'UI Design'],
    ARRAY['Clearly state project goals, needed roles, and weekly time commitment.', 'Honor commitments made to team members.', 'Open communication and equal credit for all contributors.']
  ),
  (
    'make-friends',
    'Make New Friends',
    'make-new-friends',
    'Low-pressure, casual social space for hostelers and day scholars. Grab lunch, find study buddies, or chat about campus life.',
    'Social',
    '☕',
    ARRAY['Casual Chats', 'Campus Walks', 'Coffee Meets', 'Introvert Friendly'],
    ARRAY['Judgment-free space: everyone here was once looking for a friend too.', 'No creepy or inappropriate direct messages.', 'Feel free to propose casual meetups like library breaks or cafeteria lunches.']
  )
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name,
  slug = EXCLUDED.slug,
  description = EXCLUDED.description,
  category = EXCLUDED.category,
  icon = EXCLUDED.icon,
  tags = EXCLUDED.tags,
  guidelines = EXCLUDED.guidelines;

-- ----------------------------------------------------------------------------
-- 8. INITIAL ACTIVITIES SEED (Non-creator bound for general discovery)
-- ----------------------------------------------------------------------------
INSERT INTO public.activities (id, title, description, category, date_label, location_label, capacity)
VALUES
  (
    '11111111-1111-1111-1111-111111111101',
    'Hip-Hop & Freestyle Dance Workshop',
    'Beginner-friendly groove and rhythm drill session hosted by the Dance Room. Clean indoor footwear required!',
    'Creative',
    'Wednesday · 5:00 PM',
    'SAC Studio 2 (Student Activity Center)',
    40
  ),
  (
    '11111111-1111-1111-1111-111111111102',
    'Algorithms & LeetCode Sprint Study Group',
    'Solve 3 curated medium problems together in small pairs with peer explanations afterwards. Zero pressure!',
    'Tech',
    'Every Tuesday · 6:30 PM',
    'Computer Lab 4 / Discord Hybrid',
    50
  ),
  (
    '11111111-1111-1111-1111-111111111103',
    'Campus Golden Hour Photography Walk',
    'Walk around campus botanical gardens and the reflection pond capturing golden hour light. DSLR, mirrorless, or phone cameras all welcome.',
    'Creative',
    'Saturday · 5:15 PM',
    'Meet at North Quad Sundial',
    30
  ),
  (
    '11111111-1111-1111-1111-111111111104',
    'Discrete Mathematics Midterm Study Jam',
    'Working through practice exams on Set Theory, Graph Theory, and Combinatorics with senior peer tutors available for questions.',
    'Academic',
    'Sunday · 2:00 PM',
    'Library 2nd Floor Study Room 204',
    35
  ),
  (
    '11111111-1111-1111-1111-111111111105',
    'Hackathon Ideation & Team Pitch Night',
    'Have an innovative app or hardware idea? Pitch it in 2 minutes and find designers and developers to build it with you this weekend.',
    'Tech',
    'Friday · 7:00 PM',
    'Engineering Hub Seminar Hall',
    60
  )
ON CONFLICT (id) DO NOTHING;
