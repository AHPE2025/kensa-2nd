-- 同じフロアの draft inspections を1件に制限する。
-- テスト案件 2F の重複補正は実行済みのため、このファイルにはインデックス作成だけを残す。
-- draft の (site_id, floor_id) 重複が 0 件であることを確認してから実行する。
-- 物理 DELETE / DROP は行わない。

CREATE UNIQUE INDEX IF NOT EXISTS inspections_site_floor_uidx
  ON public.inspections (site_id, floor_id)
  WHERE status = 'draft';
