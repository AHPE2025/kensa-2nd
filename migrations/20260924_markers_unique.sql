-- markers を (inspection_id, local_marker_id) で upsert するための一意インデックス。
-- アプリの saveMarkersToCloud() は onConflict: "inspection_id,local_marker_id" を使う。
-- この SQL は書き出しのみ。Supabase SQL Editor で、重複確認の結果が 0 件になってから実行する。
-- 物理 DELETE は行わない。重複がある場合はインデックスを作らず、対象行を確認する。

-- 実行前確認: UNIQUE に衝突する重複。0 件であること。
-- PostgreSQL の UNIQUE は NULL を互いに異なる値として扱うため、NULL は対象外。
SELECT
  inspection_id,
  local_marker_id,
  COUNT(*) AS duplicate_count
FROM public.markers
WHERE inspection_id IS NOT NULL
  AND local_marker_id IS NOT NULL
GROUP BY inspection_id, local_marker_id
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC, inspection_id, local_marker_id;

CREATE UNIQUE INDEX IF NOT EXISTS markers_inspection_local_uidx
  ON public.markers (inspection_id, local_marker_id);
