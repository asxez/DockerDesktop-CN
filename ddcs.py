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
from lib.processor import DDProcessor, FileProcessor


def cost_time(func):
    def fun(*args, **kwargs):
        t = time.perf_counter()
        result = func(*args, **kwargs)
        log.info(f"共耗时：{time.perf_counter() - t:.8f}s")
        return result

    return fun


@cost_time
def run(root_path: str, config_path: str, process_asar: bool):
    log.info("脚本已启动...")
    time.sleep(1)

    if process_asar:
        DDProcessor(True)

    fp = FileProcessor(root_path, config_path)
    file_paths = fp.recursive_listdir()
    log.info("汉化开始")
    for transformation in fp.get_transformations():
        search = transformation["src"]
        replacement = transformation["dest"]
        replaced = fp.process_files(file_paths, search, replacement)
        if not replaced:
            log.warn(search)
        else:
            log.info(f"{search} -> {replacement}")

    if process_asar:
        DDProcessor(False)


@cost_time
def run_v2(root_path: str, process_asar: bool):
    log.info("脚本已启动...")
    time.sleep(1)

    if process_asar:
        DDProcessor(True)
    log.info("汉化开始")
    replace(Path(root_path))
    if process_asar:
        DDProcessor(False)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--legacy", action="store_true")
    parser.add_argument("--v2", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--root_path", type=str, default=None)
    args = parser.parse_args()

    if not args.root_path:
        # 没有传递 root_path, 认为需要从安装目录 cp
        root_path = "./app/build/"
        process_asar = True
    else:
        root_path = args.root_path
        process_asar = False
    print(root_path, process_asar)
    config_path = "./config.json"
    if args.legacy:
        run(root_path, config_path, process_asar)
    else:
        run_v2(root_path, process_asar)
