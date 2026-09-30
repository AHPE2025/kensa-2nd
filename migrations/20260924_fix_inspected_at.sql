-- inspections.inspected_at を、同じ site_id の sites.inspection_date で上書きする。
-- アプリが JST 0時を toISOString() で保存していたため、フロアを開くたびに日付が1日戻っていた。
-- sites.inspection_date は "YYYY-MM-DD" のまま保存されており、こちらを正とする。
-- この SQL は書き出しのみ。Supabase SQL Editor で実行する。
-- DROP / 列型変更 / 物理 DELETE は行わない。
-- 比較は日付文字列の先頭10文字（アプリの読込と同じ）。
-- date 型なら "YYYY-MM-DD"、timestamptz ならセッション時刻の文字列になる。
-- Supabase SQL Editor（TimeZone = UTC）で実行する。

-- 実行前確認: 上書き対象の件数。
-- inspected_at が NULL、または先頭10文字が sites.inspection_date と違う行。
SELECT COUNT(*) AS mismatch_count
FROM public.inspections AS i
JOIN public.sites AS s ON s.id = i.site_id
WHERE s.inspection_date IS NOT NULL
  AND (
    i.inspected_at IS NULL
    OR LEFT(i.inspected_at::text, 10) IS DISTINCT FROM LEFT(s.inspection_date::text, 10)
  );

-- 実行前確認: 対象行の中身。この結果の件数と mismatch_count が一致すること。
SELECT
  i.id,
  i.site_id,
  s.site_name,
  LEFT(s.inspection_date::text, 10) AS site_inspection_date,
  i.inspected_at AS inspection_inspected_at
FROM public.inspections AS i
JOIN public.sites AS s ON s.id = i.site_id
WHERE s.inspection_date IS NOT NULL
  AND (
    i.inspected_at IS NULL
    OR LEFT(i.inspected_at::text, 10) IS DISTINCT FROM LEFT(s.inspection_date::text, 10)
  )
ORDER BY i.site_id, i.id;

-- 上書き。検査日の "YYYY-MM-DD" をそのまま入れる（アプリの保存値と同じ）。
UPDATE public.inspections AS i
SET inspected_at = LEFT(s.inspection_date::text, 10)
FROM public.sites AS s
WHERE i.site_id = s.id
  AND s.inspection_date IS NOT NULL
  AND (
    i.inspected_at IS NULL
    OR LEFT(i.inspected_at::text, 10) IS DISTINCT FROM LEFT(s.inspection_date::text, 10)
  );

-- 実行後確認: 不一致が 0 件であること。
SELECT COUNT(*) AS remaining_mismatch_count
FROM public.inspections AS i
JOIN public.sites AS s ON s.id = i.site_id
WHERE s.inspection_date IS NOT NULL
  AND (
    i.inspected_at IS NULL
    OR LEFT(i.inspected_at::text, 10) IS DISTINCT FROM LEFT(s.inspection_date::text, 10)
  );
