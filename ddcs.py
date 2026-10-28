# -*- coding: utf-8 -*-
#
# Copyright (C) 2024 ASXE  All Rights Reserved
#
# @Time    : 2024/8/9 下午4:17
# @Author  : ASXE

import argparse
import time
from pathlib import Path

from common import log
from lib.extract import replace
from lib.processor import DDProcessor


def cost_time(func):
    def fun(*args, **kwargs):
        t = time.perf_counter()
        result = func(*args, **kwargs)
        log.info(f"共耗时：{time.perf_counter() - t:.8f}s")
        return result

    return fun


@cost_time
def run(root_path: str, process_asar: bool):
    log.info("脚本已启动...")
    time.sleep(1)

    if process_asar:
        DDProcessor(True)
    log.info("汉化开始")
    replace(Path(root_path))
    if process_asar:
        DDProcessor(False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Docker Desktop 汉化脚本")
    parser.add_argument("--root_path", type=str, default=None)
    args = parser.parse_args()

    if not args.root_path:
        # 没有传递 root_path, 认为需要从安装目录 cp
        root_path = "./app/build/"
        process_asar = True
    else:
        root_path = args.root_path
        process_asar = False
    run(root_path, process_asar)
