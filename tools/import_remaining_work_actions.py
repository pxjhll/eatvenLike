"""Archive the pending hamster and gray-cat operation sets, ignoring completed folders.

python tools/import_remaining_work_actions.py E:/Work
Build hamster_actions and gray_cat_work_actions with the shared build_atlas.gd.
"""
from pathlib import Path
import argparse
import json
from import_work_actions import PROJECT, archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    root = parser.parse_args().root
    # Explicit pending paths: never traverse the completed archive or unpack duplicate 7z files.
    imported = [
        archive(root, "hamster_actions", [
            ("walk_right", "小仓鼠/小仓鼠行走"),
            ("idle_back_right", "小仓鼠/小仓鼠背侧45待机"),
            ("sit_front_right", "小仓鼠/小仓鼠坐立待机"),
        ], [128, 243], 222),
        archive(root, "gray_cat_work_actions", [
            ("work_right", "小灰猫操作/小灰猫侧面操作"),
            ("work_back_right", "小灰猫操作/小灰猫背侧操作"),
        ], [128, 247], 240, "res://art/gray_cat_actions/gray_cat_actions_frames.tres"),
    ]
    audit = {"external_source": str(root.resolve()), "imported": imported,
             "skipped": ["已经配置进游戏的", "小仓鼠.7z", "小灰猫操作.7z"],
             "excluded": "Videos, GIF previews, JPG overviews and 1024px concept PNGs are not runtime frames. Existing assets are reused unchanged."}
    (PROJECT / "art_src/remaining_work_actions_inventory.json").write_text(
        json.dumps(audit, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(audit, ensure_ascii=True, indent=2))


if __name__ == "__main__":
    main()
