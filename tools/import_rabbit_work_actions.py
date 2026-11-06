"""Archive rabbit assembly clips, preserving every supplied PNG and GIF frame hold.

python tools/import_rabbit_work_actions.py E:/Work/小兔子组装动作
Build rabbit_work_actions with the shared build_atlas.gd after archiving.
"""
from pathlib import Path
import argparse
import json
from import_work_actions import archive


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    root = parser.parse_args().root
    result = archive(root, "rabbit_work_actions", [
        ("work_front", "小兔子正面组装关键帧"),
        ("work_right", "小兔子侧面组装关键帧"),
        ("work_back_right", "小兔子背侧45组装关键帧"),
    ], [128, 244], 228, "res://art/rabbit_actions/rabbit_actions_frames.tres")
    print(json.dumps(result, ensure_ascii=True, indent=2))


if __name__ == "__main__":
    main()
