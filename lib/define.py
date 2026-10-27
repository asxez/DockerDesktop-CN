from dataclasses import dataclass
from typing import Optional


@dataclass
class Config:
    # src, 英文文本, 可能为包含替换字段(`{0},{1},etc.`)的格式化字符串, 如 `Select {0} in the {1} column to see it running.`
    src: str
    # dst, 中文文本, 应当保留替换字段, 即`在 {1} 列选择 {0} 以查看其运行情况`. 对于不需要翻译的项目, 中文值应为 `None`
    dst: Optional[str] = None
    # 该文本项已被删除的版本, 如果不为 None, 则说明新版本已经不再需要, 用于旧版本的替换
    deleted_at: Optional[str] = None
