-- Restored from the remote migration history (supabase_migrations.schema_migrations).
-- Already applied on the linked project; kept so local and remote histories match.

-- 1. Alter profiles table to support Hustle Dad fields
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS username TEXT UNIQUE;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS current_level TEXT DEFAULT 'Unverified';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS current_xp INTEGER DEFAULT 0;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS integrity_rate INTEGER DEFAULT 100;

-- 2. Create Dad Configuration table
CREATE TABLE IF NOT EXISTS public.dads (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    personality_type TEXT NOT NULL, -- 'sharma_ji', 'army', 'savage', etc.
    custom_prompt_override TEXT,
    voice_enabled BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- 3. Create Goal Tracking table
CREATE TABLE IF NOT EXISTS public.goals (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    title TEXT NOT NULL,
    category TEXT NOT NULL, -- 'business', 'fitness', 'learning', 'mental_health'
    target_metric TEXT NOT NULL, -- e.g., '3 hours daily', '5 workouts weekly'
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- 4. Create Promise Vault table
CREATE TABLE IF NOT EXISTS public.promises (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    promise_text TEXT NOT NULL,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL,
    is_broken BOOLEAN DEFAULT false,
    confrontation_count INTEGER DEFAULT 0
);

-- 5. Create Daily Logs table
CREATE TABLE IF NOT EXISTS public.daily_logs (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    log_date DATE DEFAULT CURRENT_DATE NOT NULL,
    category TEXT NOT NULL, -- 'work', 'habit', 'mood'
    metric_value INTEGER NOT NULL, -- e.g., minutes of work, workout count
    detail_note TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- 6. Create Excuse Tracker table
CREATE TABLE IF NOT EXISTS public.excuses (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    log_date DATE DEFAULT CURRENT_DATE NOT NULL,
    excuse_text TEXT NOT NULL,
    category TEXT NOT NULL, -- 'tired', 'distracted', 'procrastination', 'other'
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- 7. Create Discipline Scores table
CREATE TABLE IF NOT EXISTS public.discipline_scores (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
    score_date DATE DEFAULT CURRENT_DATE NOT NULL,
    score INTEGER CHECK (score >= 0 AND score <= 100) NOT NULL,
    score_breakdown JSONB NOT NULL DEFAULT '{}'::jsonb,
    dad_feedback TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT TIMEZONE('utc'::text, NOW()) NOT NULL
);

-- 8. Enable RLS on all tables
ALTER TABLE public.dads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promises ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.excuses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discipline_scores ENABLE ROW LEVEL SECURITY;

-- 9. Create RLS Policies
DROP POLICY IF EXISTS "dads_owner_policy" ON public.dads;
CREATE POLICY "dads_owner_policy" ON public.dads
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "goals_owner_policy" ON public.goals;
CREATE POLICY "goals_owner_policy" ON public.goals
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "promises_owner_policy" ON public.promises;
CREATE POLICY "promises_owner_policy" ON public.promises
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "daily_logs_owner_policy" ON public.daily_logs;
CREATE POLICY "daily_logs_owner_policy" ON public.daily_logs
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "excuses_owner_policy" ON public.excuses;
CREATE POLICY "excuses_owner_policy" ON public.excuses
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "discipline_scores_owner_policy" ON public.discipline_scores;
CREATE POLICY "discipline_scores_owner_policy" ON public.discipline_scores
    FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- 10. Trigger function to auto-create profiles on user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, email, name, username, current_level, current_xp, integrity_rate)
  VALUES (
    new.id,
    new.email,
    COALESCE(new.raw_user_meta_data->>'name', new.raw_user_meta_data->>'full_name', ''),
    COALESCE(new.raw_user_meta_data->>'username', SPLIT_PART(new.email, '@', 1)),
    'Unverified',
    0,
    100
  )
  ON CONFLICT (id) DO UPDATE
  SET email = EXCLUDED.email,
      name = COALESCE(profiles.name, EXCLUDED.name),
      username = COALESCE(profiles.username, EXCLUDED.username);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Recreate trigger to avoid duplicates
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
