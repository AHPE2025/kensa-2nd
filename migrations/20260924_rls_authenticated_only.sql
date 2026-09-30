-- P0-8: anon からのアクセスを閉じる。
-- authenticated 用の4ポリシー（select / insert / update / delete）は既に DB に追加済みのため、
-- この SQL では以下だけを行う。
--   1. 対象テーブルで RLS を有効化する（既に有効なら何も起きない）。
--   2. 対象テーブルの anon / public 向けポリシーを削除する。
--   3. storage.objects の inspection-drawings / marker-photos 向け anon / public ポリシーを削除する。
--   4. 両バケットを private にする。
-- この SQL は書き出しのみ。Supabase SQL Editor で実行する。
-- DROP COLUMN / 列型変更 / 行の物理 DELETE は行わない。
-- 再実行可: 削除対象が無ければ何もしない。
--
-- 対象テーブル: sites, site_floors, inspection_floors, inspections, drawings, drawing_pages,
--   markers, marker_photos, drawing_text_notes, inspection_vendors, inspection_categories,
--   inspection_category_vendor_assignments, export_logs
-- inspection_floors はコードから直接参照されていないため、存在しない場合はスキップする。

-- ---------------------------------------------------------------------------
-- 実行前確認
-- ---------------------------------------------------------------------------

-- 実行前確認 1: 対象テーブルに残っている全ポリシー。
SELECT schemaname, tablename, policyname, roles, cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = ANY (ARRAY[
    'sites',
    'site_floors',
    'inspection_floors',
    'inspections',
    'drawings',
    'drawing_pages',
    'markers',
    'marker_photos',
    'drawing_text_notes',
    'inspection_vendors',
    'inspection_categories',
    'inspection_category_vendor_assignments',
    'export_logs'
  ])
ORDER BY tablename, policyname;

-- 実行前確認 2: このうち削除対象になる anon / public ポリシー（roles に anon または public を含むもの）。
SELECT schemaname, tablename, policyname, roles, cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = ANY (ARRAY[
    'sites',
    'site_floors',
    'inspection_floors',
    'inspections',
    'drawings',
    'drawing_pages',
    'markers',
    'marker_photos',
    'drawing_text_notes',
    'inspection_vendors',
    'inspection_categories',
    'inspection_category_vendor_assignments',
    'export_logs'
  ])
  AND (roles && ARRAY['anon', 'public']::name[])
ORDER BY tablename, policyname;

-- 実行前確認 3: 対象テーブルの RLS 有効状態。
SELECT c.relname AS tablename, c.relrowsecurity AS rls_enabled
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND c.relname = ANY (ARRAY[
    'sites',
    'site_floors',
    'inspection_floors',
    'inspections',
    'drawings',
    'drawing_pages',
    'markers',
    'marker_photos',
    'drawing_text_notes',
    'inspection_vendors',
    'inspection_categories',
    'inspection_category_vendor_assignments',
    'export_logs'
  ])
ORDER BY c.relname;

-- 実行前確認 4: バケットの公開設定。
SELECT id, name, public
FROM storage.buckets
WHERE id IN ('inspection-drawings', 'marker-photos')
ORDER BY id;

-- 実行前確認 5: 両バケットに触れている storage.objects ポリシーのうち、anon / public 向けのもの（削除対象）。
SELECT policyname, roles, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
  AND (roles && ARRAY['anon', 'public']::name[])
  AND (
    COALESCE(qual, '') ILIKE '%inspection-drawings%'
    OR COALESCE(qual, '') ILIKE '%marker-photos%'
    OR COALESCE(with_check, '') ILIKE '%inspection-drawings%'
    OR COALESCE(with_check, '') ILIKE '%marker-photos%'
    OR policyname ILIKE '%inspection-drawings%'
    OR policyname ILIKE '%marker-photos%'
    OR policyname ILIKE '%inspection_drawings%'
    OR policyname ILIKE '%marker_photos%'
  )
ORDER BY policyname;

-- ---------------------------------------------------------------------------
-- 変更
-- ---------------------------------------------------------------------------

-- 1. RLS 有効化 + 2. anon / public ポリシー削除（authenticated 向けポリシーには触れない）。
DO $$
DECLARE
  tables text[] := ARRAY[
    'sites',
    'site_floors',
    'inspection_floors',
    'inspections',
    'drawings',
    'drawing_pages',
    'markers',
    'marker_photos',
    'drawing_text_notes',
    'inspection_vendors',
    'inspection_categories',
    'inspection_category_vendor_assignments',
    'export_logs'
  ];
  t text;
  r record;
BEGIN
  FOREACH t IN ARRAY tables LOOP
    IF to_regclass(format('public.%I', t)) IS NULL THEN
      RAISE NOTICE 'skip: public.% does not exist', t;
      CONTINUE;
    END IF;
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    FOR r IN
      SELECT policyname
      FROM pg_policies
      WHERE schemaname = 'public'
        AND tablename = t
        AND (roles && ARRAY['anon', 'public']::name[])
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', r.policyname, t);
      RAISE NOTICE 'dropped policy % on public.%', r.policyname, t;
    END LOOP;
  END LOOP;
END $$;

-- 3. storage.objects の anon / public 向けポリシー削除（両バケットに関係するものだけ）。
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT policyname, qual, with_check
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND (roles && ARRAY['anon', 'public']::name[])
  LOOP
    IF COALESCE(r.qual, '') ILIKE '%inspection-drawings%'
       OR COALESCE(r.qual, '') ILIKE '%marker-photos%'
       OR COALESCE(r.with_check, '') ILIKE '%inspection-drawings%'
       OR COALESCE(r.with_check, '') ILIKE '%marker-photos%'
       OR r.policyname ILIKE '%inspection-drawings%'
       OR r.policyname ILIKE '%marker-photos%'
       OR r.policyname ILIKE '%inspection_drawings%'
       OR r.policyname ILIKE '%marker_photos%'
    THEN
      EXECUTE format('DROP POLICY IF EXISTS %I ON storage.objects', r.policyname);
      RAISE NOTICE 'dropped storage policy %', r.policyname;
    END IF;
  END LOOP;
END $$;

-- 4. 両バケットを private にする。
UPDATE storage.buckets
SET public = false
WHERE id IN ('inspection-drawings', 'marker-photos')
  AND public = true;

-- ---------------------------------------------------------------------------
-- 実行後確認
-- ---------------------------------------------------------------------------

-- 実行後確認 1: anon / public を含むポリシーが対象テーブルに残っていないこと。件数は 0。
SELECT COUNT(*) AS anon_policy_count
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = ANY (ARRAY[
    'sites',
    'site_floors',
    'inspection_floors',
    'inspections',
    'drawings',
    'drawing_pages',
    'markers',
    'marker_photos',
    'drawing_text_notes',
    'inspection_vendors',
    'inspection_categories',
    'inspection_category_vendor_assignments',
    'export_logs'
  ])
  AND (roles && ARRAY['anon', 'public']::name[]);

-- 実行後確認 2: 各テーブルに authenticated 向けポリシーが残っていること（既存分。テーブルごとに 4 件）。
SELECT tablename, policyname, roles, cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = ANY (ARRAY[
    'sites',
    'site_floors',
    'inspection_floors',
    'inspections',
    'drawings',
    'drawing_pages',
    'markers',
    'marker_photos',
    'drawing_text_notes',
    'inspection_vendors',
    'inspection_categories',
    'inspection_category_vendor_assignments',
    'export_logs'
  ])
ORDER BY tablename, cmd;

-- 実行後確認 3: 対象テーブルの RLS がすべて true であること。
SELECT c.relname AS tablename, c.relrowsecurity AS rls_enabled
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relkind = 'r'
  AND c.relname = ANY (ARRAY[
    'sites',
    'site_floors',
    'inspection_floors',
    'inspections',
    'drawings',
    'drawing_pages',
    'markers',
    'marker_photos',
    'drawing_text_notes',
    'inspection_vendors',
    'inspection_categories',
    'inspection_category_vendor_assignments',
    'export_logs'
  ])
ORDER BY c.relname;

-- 実行後確認 4: 両バケットが private（public = false）であること。
SELECT id, public
FROM storage.buckets
WHERE id IN ('inspection-drawings', 'marker-photos')
ORDER BY id;

-- 実行後確認 5: 両バケットに触れている storage.objects ポリシーが authenticated のみであること（anon / public は 0 件）。
SELECT policyname, roles, cmd
FROM pg_policies
WHERE schemaname = 'storage'
  AND tablename = 'objects'
  AND (
    COALESCE(qual, '') ILIKE '%inspection-drawings%'
    OR COALESCE(qual, '') ILIKE '%marker-photos%'
    OR COALESCE(with_check, '') ILIKE '%inspection-drawings%'
    OR COALESCE(with_check, '') ILIKE '%marker-photos%'
    OR policyname ILIKE '%inspection-drawings%'
    OR policyname ILIKE '%marker-photos%'
    OR policyname ILIKE '%inspection_drawings%'
    OR policyname ILIKE '%marker_photos%'
  )
ORDER BY policyname;
