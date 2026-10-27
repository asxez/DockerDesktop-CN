import argparse
from pathlib import Path

from lib.extract import generate_config
from lib.processor import DDProcessor

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--path", type=str, default=None)
    args = parser.parse_args()

    if args.path is None:
        DDProcessor(True)
        path = Path("./app")
    else:
        path = Path(args.path)
    generate_config(path)
