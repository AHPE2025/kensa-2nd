-- PDFゴミ箱移動時に markers / drawing_text_notes / marker_photos の
-- 現在 status を previous_status へ退避し、復元時に戻すための列追加。
-- 既存行の status は変更しない。この SQL は書き出しのみ。Supabase SQL Editor で実行する。
-- DROP / 列型変更 / 物理 DELETE は行わない。

-- 実行前確認: previous_status 列の有無。0 行なら未追加。
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND column_name = 'previous_status'
  AND table_name IN ('markers', 'drawing_text_notes', 'marker_photos')
ORDER BY table_name;

ALTER TABLE public.markers
  ADD COLUMN IF NOT EXISTS previous_status text;

ALTER TABLE public.drawing_text_notes
  ADD COLUMN IF NOT EXISTS previous_status text;

ALTER TABLE public.marker_photos
  ADD COLUMN IF NOT EXISTS previous_status text;

-- 実行後確認: 3 テーブルとも previous_status が text で存在すること。
-- 既存行の status 件数は実行前後で変わらないこと。
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND column_name = 'previous_status'
  AND table_name IN ('markers', 'drawing_text_notes', 'marker_photos')
ORDER BY table_name;

SELECT 'markers' AS table_name, status, COUNT(*) AS row_count
FROM public.markers
GROUP BY status
UNION ALL
SELECT 'drawing_text_notes', status, COUNT(*)
FROM public.drawing_text_notes
GROUP BY status
UNION ALL
SELECT 'marker_photos', status, COUNT(*)
FROM public.marker_photos
GROUP BY status
ORDER BY table_name, status;
