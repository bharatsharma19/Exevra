-- ==============================================================================
-- ANTIGRAVITY EXPENSE MANAGER - PRODUCTION POSTGRESQL SCHEMA & RLS POLICIES
-- ==============================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. GROUPS TABLE
CREATE TABLE IF NOT EXISTS public.groups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL CHECK (char_length(trim(name)) > 0),
    invite_code TEXT UNIQUE NOT NULL DEFAULT substring(encode(gen_random_bytes(6), 'hex') from 1 for 8),
    admin_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 3. PROFILES TABLE (Linked to auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL DEFAULT 'User',
    avatar_url TEXT,
    phone TEXT,
    email TEXT,
    group_id UUID REFERENCES public.groups(id) ON DELETE SET NULL,
    currency TEXT NOT NULL DEFAULT 'INR',
    theme_mode TEXT NOT NULL DEFAULT 'system' CHECK (theme_mode IN ('system', 'light', 'dark')),
    haptics_enabled BOOLEAN NOT NULL DEFAULT true,
    ai_consent BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- 4. GROUP MEMBERS JUNCTION TABLE
CREATE TABLE IF NOT EXISTS public.group_members (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    group_id UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'viewer' CHECK (role IN ('admin', 'member', 'viewer')),
    invited_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    CONSTRAINT unique_group_user UNIQUE (group_id, user_id)
);

-- 5. EXPENSES TABLE
CREATE TABLE IF NOT EXISTS public.expenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    group_id UUID REFERENCES public.groups(id) ON DELETE CASCADE,
    title TEXT NOT NULL CHECK (char_length(trim(title)) > 0),
    amount NUMERIC(12, 2) NOT NULL CHECK (amount > 0),
    category TEXT NOT NULL,
    date TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    notes TEXT,
    receipt_url TEXT,
    is_personal BOOLEAN GENERATED ALWAYS AS (group_id IS NULL) STORED,
    created_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now()),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT timezone('utc'::text, now())
);

-- INDEXES FOR PERFORMANCE
CREATE INDEX IF NOT EXISTS idx_expenses_user_id ON public.expenses(user_id);
CREATE INDEX IF NOT EXISTS idx_expenses_group_id ON public.expenses(group_id);
CREATE INDEX IF NOT EXISTS idx_expenses_date ON public.expenses(date DESC);
CREATE INDEX IF NOT EXISTS idx_expenses_category ON public.expenses(category);
CREATE INDEX IF NOT EXISTS idx_group_members_user ON public.group_members(user_id);
CREATE INDEX IF NOT EXISTS idx_group_members_group ON public.group_members(group_id);

-- 6. TRIGGERS FOR UPDATED_AT
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = timezone('utc'::text, now());
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_groups_updated_at ON public.groups;
CREATE TRIGGER trigger_groups_updated_at
    BEFORE UPDATE ON public.groups
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trigger_profiles_updated_at ON public.profiles;
CREATE TRIGGER trigger_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS trigger_expenses_updated_at ON public.expenses;
CREATE TRIGGER trigger_expenses_updated_at
    BEFORE UPDATE ON public.expenses
    FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- 7. NEW USER TRIGGER: Auto-create Profile on Auth Sign Up
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.profiles (id, display_name, email, phone, avatar_url)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.raw_user_meta_data->>'name', split_part(COALESCE(NEW.email, 'User'), '@', 1)),
        NEW.email,
        NEW.phone,
        NEW.raw_user_meta_data->>'avatar_url'
    )
    ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        phone = COALESCE(EXCLUDED.phone, public.profiles.phone);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ==============================================================================
-- 8. ROW LEVEL SECURITY (RLS) POLICIES
-- ==============================================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;

-- ------------------------------------------------------------------------------
-- PROFILES RLS
-- ------------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
CREATE POLICY "Users can view own profile"
    ON public.profiles FOR SELECT
    USING (
        auth.uid() = id
        OR (
            group_id IS NOT NULL 
            AND group_id IN (
                SELECT gm.group_id FROM public.group_members gm WHERE gm.user_id = auth.uid()
            )
        )
    );

DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;
CREATE POLICY "Users can insert own profile"
    ON public.profiles FOR INSERT
    WITH CHECK (auth.uid() = id);

-- ------------------------------------------------------------------------------
-- GROUPS RLS
-- ------------------------------------------------------------------------------
DROP POLICY IF EXISTS "Members can view their group" ON public.groups;
CREATE POLICY "Members can view their group"
    ON public.groups FOR SELECT
    USING (
        admin_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.group_members gm
            WHERE gm.group_id = groups.id AND gm.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Authenticated users can create groups" ON public.groups;
CREATE POLICY "Authenticated users can create groups"
    ON public.groups FOR INSERT
    WITH CHECK (auth.uid() = admin_id);

DROP POLICY IF EXISTS "Only admin can update group" ON public.groups;
CREATE POLICY "Only admin can update group"
    ON public.groups FOR UPDATE
    USING (auth.uid() = admin_id)
    WITH CHECK (auth.uid() = admin_id);

DROP POLICY IF EXISTS "Only admin can delete group" ON public.groups;
CREATE POLICY "Only admin can delete group"
    ON public.groups FOR DELETE
    USING (auth.uid() = admin_id);

-- ------------------------------------------------------------------------------
-- GROUP MEMBERS RLS
-- ------------------------------------------------------------------------------
DROP POLICY IF EXISTS "Members can view group membership" ON public.group_members;
CREATE POLICY "Members can view group membership"
    ON public.group_members FOR SELECT
    USING (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.group_members self_m
            WHERE self_m.group_id = group_members.group_id AND self_m.user_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can join or admins can add members" ON public.group_members;
CREATE POLICY "Users can join or admins can add members"
    ON public.group_members FOR INSERT
    WITH CHECK (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.groups g
            WHERE g.id = group_members.group_id AND g.admin_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can leave or admins can remove members" ON public.group_members;
CREATE POLICY "Users can leave or admins can remove members"
    ON public.group_members FOR DELETE
    USING (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.groups g
            WHERE g.id = group_members.group_id AND g.admin_id = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Admins can update group member roles" ON public.group_members;
CREATE POLICY "Admins can update group member roles"
    ON public.group_members FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM public.groups g
            WHERE g.id = group_members.group_id AND g.admin_id = auth.uid()
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.groups g
            WHERE g.id = group_members.group_id AND g.admin_id = auth.uid()
        )
    );

-- ------------------------------------------------------------------------------
-- EXPENSES RLS (STRICT PERMISSION MATRIX)
-- 1. Editing: Any user who created an expense (personal or group) can edit it.
-- 2. Deleting: Personal expenses can only be deleted by the creator.
--              Group expenses can ONLY be deleted by the designated Group Admin.
-- 3. Inserting: Viewers can only view; only approved members & admins can insert group expenses.
-- ------------------------------------------------------------------------------

-- SELECT
DROP POLICY IF EXISTS "Select Expenses Policy" ON public.expenses;
CREATE POLICY "Select Expenses Policy"
    ON public.expenses FOR SELECT
    USING (
        -- Personal expense: creator only
        (group_id IS NULL AND user_id = auth.uid())
        OR
        -- Group expense: any active member in the group
        (
            group_id IS NOT NULL 
            AND EXISTS (
                SELECT 1 FROM public.group_members gm
                WHERE gm.group_id = expenses.group_id AND gm.user_id = auth.uid()
            )
        )
    );

-- INSERT (Viewers cannot insert group expenses until reviewed & approved by Group Admin)
DROP POLICY IF EXISTS "Insert Expenses Policy" ON public.expenses;
CREATE POLICY "Insert Expenses Policy"
    ON public.expenses FOR INSERT
    WITH CHECK (
        user_id = auth.uid()
        AND (
            group_id IS NULL
            OR EXISTS (
                SELECT 1 FROM public.group_members gm
                WHERE gm.group_id = expenses.group_id 
                  AND gm.user_id = auth.uid()
                  AND gm.role IN ('admin', 'member')
            )
        )
    );

-- UPDATE: Any user who created an expense (personal or group) can edit it. Non-creators cannot edit.
DROP POLICY IF EXISTS "Update Expenses Policy" ON public.expenses;
CREATE POLICY "Update Expenses Policy"
    ON public.expenses FOR UPDATE
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

-- DELETE: Personal expenses: creator only. Group expenses: designated Group Admin ONLY.
DROP POLICY IF EXISTS "Delete Expenses Policy" ON public.expenses;
CREATE POLICY "Delete Expenses Policy"
    ON public.expenses FOR DELETE
    USING (
        (group_id IS NULL AND user_id = auth.uid())
        OR
        (
            group_id IS NOT NULL 
            AND EXISTS (
                SELECT 1 FROM public.groups g
                WHERE g.id = expenses.group_id AND g.admin_id = auth.uid()
            )
        )
    );

-- ==============================================================================
-- 9. RPC FUNCTIONS
-- ==============================================================================

-- 9.1 Join Group via Invite Code
CREATE OR REPLACE FUNCTION public.join_group_by_invite(p_invite_code TEXT)
RETURNS JSONB AS $$
DECLARE
    v_group RECORD;
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    SELECT * INTO v_group FROM public.groups WHERE invite_code = trim(p_invite_code);
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid invite code';
    END IF;

    -- Insert into group_members as viewer (must be reviewed by admin before adding expenses)
    INSERT INTO public.group_members (group_id, user_id, role)
    VALUES (v_group.id, v_user_id, CASE WHEN v_group.admin_id = v_user_id THEN 'admin' ELSE 'viewer' END)
    ON CONFLICT (group_id, user_id) DO NOTHING;

    -- Update user profile current group
    UPDATE public.profiles
    SET group_id = v_group.id
    WHERE id = v_user_id;

    RETURN jsonb_build_object(
        'success', true,
        'group_id', v_group.id,
        'group_name', v_group.name,
        'role', CASE WHEN v_group.admin_id = v_user_id THEN 'admin' ELSE 'viewer' END
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 9.2 Approve Group Member (Admin Review & Approval)
CREATE OR REPLACE FUNCTION public.approve_group_member(
    p_group_id UUID,
    p_user_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
    v_admin_id UUID := auth.uid();
BEGIN
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Verify caller is admin of the group
    IF NOT EXISTS (
        SELECT 1 FROM public.groups
        WHERE id = p_group_id AND admin_id = v_admin_id
    ) THEN
        RAISE EXCEPTION 'Only the group admin can review and approve members';
    END IF;

    UPDATE public.group_members
    SET role = 'member'
    WHERE group_id = p_group_id AND user_id = p_user_id;

    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 9.2 Analytics & Financial Insights Engine
CREATE OR REPLACE FUNCTION public.get_expense_insights(
    p_timeframe TEXT DEFAULT 'monthly',
    p_group_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_start_date TIMESTAMPTZ;
    v_total NUMERIC(12, 2) := 0;
    v_count INT := 0;
    v_categories JSONB := '[]'::jsonb;
    v_trends JSONB := '[]'::jsonb;
    v_highest JSONB := '{}'::jsonb;
    v_avg_daily NUMERIC(12, 2) := 0;
    v_days_count INT := 30;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Set timeframe boundaries
    IF p_timeframe = 'weekly' THEN
        v_start_date := timezone('utc'::text, now()) - INTERVAL '7 days';
        v_days_count := 7;
    ELSIF p_timeframe = 'yearly' THEN
        v_start_date := timezone('utc'::text, now()) - INTERVAL '365 days';
        v_days_count := 365;
    ELSE -- monthly default
        v_start_date := timezone('utc'::text, now()) - INTERVAL '30 days';
        v_days_count := 30;
    END IF;

    -- 1. Totals & Count
    SELECT 
        COALESCE(SUM(amount), 0),
        COUNT(*)
    INTO v_total, v_count
    FROM public.expenses
    WHERE date >= v_start_date
      AND (
          (p_group_id IS NULL AND group_id IS NULL AND user_id = v_user_id)
          OR (p_group_id IS NOT NULL AND group_id = p_group_id)
      );

    -- 2. Average Daily
    IF v_days_count > 0 THEN
        v_avg_daily := ROUND(v_total / v_days_count, 2);
    END IF;

    -- 3. Highest Expense
    SELECT jsonb_build_object(
        'id', id,
        'title', title,
        'amount', amount,
        'category', category,
        'date', date
    )
    INTO v_highest
    FROM public.expenses
    WHERE date >= v_start_date
      AND (
          (p_group_id IS NULL AND group_id IS NULL AND user_id = v_user_id)
          OR (p_group_id IS NOT NULL AND group_id = p_group_id)
      )
    ORDER BY amount DESC
    LIMIT 1;

    -- 4. Category Breakdown
    SELECT jsonb_agg(cat_row)
    INTO v_categories
    FROM (
        SELECT 
            category,
            SUM(amount) AS total,
            COUNT(*) AS count,
            CASE WHEN v_total > 0 THEN ROUND((SUM(amount) / v_total) * 100, 2) ELSE 0 END AS percentage
        FROM public.expenses
        WHERE date >= v_start_date
          AND (
              (p_group_id IS NULL AND group_id IS NULL AND user_id = v_user_id)
              OR (p_group_id IS NOT NULL AND group_id = p_group_id)
          )
        GROUP BY category
        ORDER BY total DESC
    ) cat_row;

    -- 5. Trend Points
    SELECT jsonb_agg(trend_row)
    INTO v_trends
    FROM (
        SELECT 
            to_char(date, CASE WHEN p_timeframe = 'yearly' THEN 'Mon YYYY' ELSE 'YYYY-MM-DD' END) AS label,
            date_trunc(CASE WHEN p_timeframe = 'yearly' THEN 'month' ELSE 'day' END, date) AS point_date,
            SUM(amount) AS total,
            COUNT(*) AS count
        FROM public.expenses
        WHERE date >= v_start_date
          AND (
              (p_group_id IS NULL AND group_id IS NULL AND user_id = v_user_id)
              OR (p_group_id IS NOT NULL AND group_id = p_group_id)
          )
        GROUP BY 1, 2
        ORDER BY point_date ASC
    ) trend_row;

    RETURN jsonb_build_object(
        'timeframe', p_timeframe,
        'total_amount', v_total,
        'expense_count', v_count,
        'average_daily', v_avg_daily,
        'highest_expense', COALESCE(v_highest, '{}'::jsonb),
        'category_breakdown', COALESCE(v_categories, '[]'::jsonb),
        'trend_data', COALESCE(v_trends, '[]'::jsonb)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 9.3 Delete User Account (App Store & Play Store Compliance)
CREATE OR REPLACE FUNCTION public.delete_user_account()
RETURNS BOOLEAN AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    -- Clean up user created groups where user is admin
    DELETE FROM public.groups WHERE admin_id = v_user_id;

    -- Delete user profile
    DELETE FROM public.profiles WHERE id = v_user_id;

    -- Delete user from auth schema
    DELETE FROM auth.users WHERE id = v_user_id;

    RETURN true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
