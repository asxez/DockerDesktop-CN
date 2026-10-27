import json
import re
from io import StringIO
from pathlib import Path
from typing import List, Tuple, Generator, Union, Dict

import black

from common import log
from lib.define import Config
from lib.extract_config import config
from lib.extract_config_manually import config_manually

config_dict: Dict[str, Config] = {item.src: item for item in config}

_re_text_vars = re.compile(r"(\{\d+})")
# 捕获组需要包含 [], 以找到正确的字符串结尾
"""
_re_children_1_external 寻找第一个 child 为英文文本(大写开头)的 children, 例如:
children:["Settings",(0,N.jsx)(U.A,{feedbackUrl:ne,sourcePage:"settings"})]
_re_children_1_external 也允许第一个 child 为空, 第二个 child 为英文文本(大写开头), 例如:
children:[" ","If the error persists, please",...]
"""
_re_children_1_external = re.compile(r"""children:(\[(?:" ",)?(?<!\\)(['"`])[A-Z].*?(?<!\\)\2.*?])""")
"""
_re_children_1_internal 寻找嵌套 children 中的 children, 与 _re_children_1 类似但不要求大写开头
"""
_re_children_1_internal = re.compile(r"""children:(\[(?:" ",)?(?<!\\)(['"`])([a-zA-Z].*?)(?<!\\)\2.*?])""")
"""
_re_children_2_external 寻找最后一个 child 为字符串的 children, 同时排除 _re_children_1, 例如:
children:[(0,B.jsx)(ke.A,{fontSize:"xs",sx:{marginRight:"4px"}}),"Installing update..."]
"""
_re_children_2_external = re.compile(r'children:(\[(?!"[A-Z])[^\[\]]*?,"[^\[\]]*?"])')
"""
_re_nested_children_text 寻找嵌套 children 中的字符串, 理论上属于父级 text 的一部分, 因此不限制大写开头. 例如:
children:[..., children:"contact your administrator", ...]
"""
_re_nested_children_text = re.compile(r'children:"(.*?[a-zA-Z]+?.*?)"')
"""
_re_text 寻找指定 tag 的英文文本(大写开头), 例如:
label:"Docker Home"
children:`Last refresh: ${l}`
"""
_re_text = re.compile(
    r"""(label|title|content|secondary|description|placeholder|children|reason|buttonTitle|helperText|message|detail|checkboxLabel|caption|alt|headerName|tooltip|primary|notificationTitle|warningText):(?<!\\)(['"`])([A-Z].*?)(?<!\\)\2"""
)
"""
_re_array_text 寻找指定 tag 的数组文本 (",messages"是为了干掉 AI 提示词), 例如: 
,messages:[`${o.path} already exists.`,"Please remove it and retry."]
buttons:["Switch","Cancel"]
"""
_re_array_text = re.compile(r'(,messages|buttons):(\[["`].+?["`]])')
"""
_re_children_all_lower_text 判断 children 是否为纯小写文本 (由 _re_children_2_external 提取), 这种情况应该走 array text, 例如:
head:{children:["title","base","link","style","meta","script","noscript","command"]}
"""
_re_children_all_lower_text = re.compile(r'children:\["[a-z]+"(?:,"[a-z]+")+]')


class Dst:
    src: str  # without args
    dst: str
    args: List[str]

    def __init__(self, src: str):
        buf, group, arg_buf, args, dep = StringIO(), 0, StringIO(), [], 0
        for i, c in enumerate(src):
            if c == "$" and i < len(src) and src[i + 1] == "{":
                arg_buf.write(c)
                dep += 1
            elif dep > 0 and c == "}":
                arg_buf.write(c)
                dep -= 1
                if dep == 0:
                    args.append(arg_buf.getvalue())
                    arg_buf = StringIO()
                    buf.write(f"{{{group}}}")
                    group += 1
            elif dep == 0:
                buf.write(c)
            else:
                arg_buf.write(c)

        self.src = buf.getvalue()
        conf = config_dict.get(self.src)
        self.dst = conf.dst if conf else ""
        self.args = args

    def __bool__(self):
        return bool(self.dst)

    def format(self) -> str:
        if self.args:
            return self.dst.format(*self.args)
        return self.dst


class Text:
    """
    对于简单文本: fmt='label:"{}"', src='Close', dst='关闭', args=None.
    对于 children:
        fmt='children:[{}]',
        src="The {0} element...",
        dst="该 {0} 元素...",
        raw='"The ",(0,y.jsx)("strong",{children:"volumes"}),' element...''
        args=['(0,y.jsx)("strong",{children:"volumes"})'],
        args_len=40,
    对于 array:
        fmt='buttons:["{}","{}"]',
        src=["Switch", "Cancel"],
        dst=["切换", "取消"],
        args=None,
    """

    start: int
    fmt: str  # label:"{}"
    src: Union[str, List[str]]  # Close | ["Switch", "Cancel"]
    dst: Union[Dst, List[Dst]]  # 关闭 | ["切换", "关闭"]
    """children"""
    raw: str = None
    args: List[str] = None
    args_len: int = 0

    def __init__(
            self,
            start: int,
            fmt: str,
            src: Union[str, List[str]],
            raw: str = None,
            args: List[str] = None,
            args_len: int = 0,
    ):
        self.start = start
        self.fmt = fmt
        self.src = src
        if isinstance(src, list):
            self.dst = [Dst(v) for v in src]
        else:
            self.dst = Dst(src)
        self.raw = raw
        self.args = args
        self.args_len = args_len

    def _format_args(self) -> str:
        dst = self.dst.format()
        rst, accessed = [], [False] * len(self.args)
        for part in _re_text_vars.split(dst):
            if not part:
                continue
            if _re_text_vars.match(part):
                idx = int(part[1:-1])
                value, accessed[idx] = self.args[idx], True
            elif '"' in part:
                value = f"'{part}'"
            else:
                value = f'"{part}"'
            rst.append(value)
        not_accessed = [f"{{{idx}}}" for idx, v in enumerate(accessed) if not v]
        if not_accessed:
            log.warn(f"翻译文本中缺少变量值: {','.join(not_accessed)}, 文本: {self.dst}")
        return f'[{",".join(rst)}]'

    def config(self):
        """
        获取配置文件中的字符串元组
        :return: (src, dst), src 是英文文本, dst 是中文文本, 其中 children src 已优化
        """
        if isinstance(self.src, list):
            for dst in self.dst:
                yield dst.src, dst.dst
        else:
            yield self.dst.src, self.dst.dst

    def has_dst(self) -> bool:
        if isinstance(self.src, list):
            return self.dst and any(self.dst)
        return bool(self.dst)

    def format(self) -> Tuple[str, str]:
        """
        获取格式化之后的字符串元组
        :return: (src, dst), src 是原始文件中的字符串, dst 是替换后的字符串
        """
        # children
        if self.raw:
            return self.fmt.format(self.raw), self.fmt.format(self._format_args())
        # array
        if isinstance(self.src, list):
            return self.fmt.format(*self.src), self.fmt.format(*[d.format() for d in self.dst])
        # simple
        return self.fmt.format(self.src), self.fmt.format(self.dst.format())


def extract(code: str) -> Generator[Text, None, None]:
    """
    extract 使用正则从代码段中提取文本, 并进行进一步解析
    :param code: 代码段
    """
    yield from extract_children(code)
    # extract array
    for match in _re_array_text.finditer(code):
        prefix, src = match.groups()
        yield from _extract_array(prefix, src, match.start())
    # extract text
    for match in _re_text.finditer(code):
        start = match.start()
        fmt, sep, src = match.groups()
        fmt += ":" + sep + "{}" + sep
        if sep == "`":
            l, r = src.count("{"), src.count("}")
            if r < l:
                start, end = match.span(3)
                while r < l:
                    if code[end] == "{":
                        l += 1
                    elif code[end] == "}":
                        r += 1
                    end += 1
                while code[end] != "`":
                    end += 1
                src = code[start:end]
        yield Text(start=start, fmt=fmt, src=src)


def extract_children(code: str, code_start: int = 0, nested: bool = False) -> Generator[Text, None, None]:
    """
    extract_children 使用正则从代码段中提取 children 内容, 并进行进一步解析
    :param code: 代码段
    :param code_start: 代码段起始位置
    :param nested: code 代码段是否是 children 代码段, 即当前提取是否为嵌套 children.
    """
    _re_children_1 = _re_children_1_internal if nested else _re_children_1_external
    for match in _re_children_1.finditer(code):
        start = match.start()
        src = match.groups()[0]
        rc = src.count("[")
        if rc > 1:
            start, end = match.span(1)
            while rc > 1:
                if code[end] == "[":
                    rc += 1
                elif code[end] == "]":
                    rc -= 1
                end += 1
            src = code[start:end]
        yield from _extract_children(src, code_start + start)

    if not nested:
        for match in _re_children_2_external.finditer(code):
            if _re_children_all_lower_text.match(match.group()):
                yield from _extract_array("children", match.group()[0], match.start())
            else:
                yield from _extract_children(match.groups()[0], code_start + match.start())


def _extract_children(children_code: str, children_start: int = 0) -> Generator[Text, None, None]:
    """
    _extract_children 将 children 内容切割为 list, 文本存储在 src, 代码段存储在 args, 之后嵌套解析 args
    :param children_code: children 代码段, children:[...]
    :param children_start: 代码段起始位置
    """
    buf, group, args, args_len = StringIO(), 0, [], 0
    for code, start, is_str in _split_array(children_code):
        if is_str:
            buf.write(code[1:-1])
            continue

        buf.write(f"{{{group}}}")
        group += 1

        start += children_start
        yield from extract_children(code, start, True)
        # 文本
        for match in _re_nested_children_text.finditer(code):
            yield Text(start=start, fmt='children:"{}"', src=match.groups()[0])
        args.append(code)
        args_len += len(code)
    yield Text(
        start=children_start,
        fmt="children:{}",
        src=buf.getvalue(),
        raw=children_code,
        args=args,
        args_len=args_len,
    )


def _extract_array(prefix: str, array_code: str, array_start: int = 0) -> Generator[Text, None, None]:
    fmt, src = prefix + ":[", []
    for code, _, is_str in _split_array(array_code):
        if not is_str:
            return
        fmt += f"{code[0]}{{}}{code[0]},"
        src.append(code[1:-1])
    if src:
        yield Text(start=array_start, fmt=fmt[:-1] + "]", src=src)


def _split_array(array_code: str) -> Generator[Tuple[str, int, bool], None, None]:
    """
    将 array 代码段切割为 list
    :param array_code: array 代码段
    """
    array_code = array_code[1:-1]  # unwrap []
    start, dep, in_str = 0, 0, None
    for i, c in enumerate(array_code):
        if c in ("[", "(", "{") and in_str is None:
            dep += 1
        elif c in ("]", ")", "}") and in_str is None:
            dep -= 1
        elif c in ('"', "'"):
            if in_str is None:
                in_str = c
            elif in_str == c:
                in_str = None
        elif c == "," and dep == 0 and in_str is None:
            code = array_code[start:i]
            if not code:
                continue
            yield code, start, code[0] in ('"', "'", "`") and code[0] not in code[1:-1]
            start = i + 1
    code = array_code[start:]
    if not code:
        return
    yield code, start, code[0] in ('"', "'", "`") and code[0] not in code[1:-1]


def files(path: Path):
    for file in path.rglob("main.js"):
        yield file
    for file in path.rglob("*js"):
        if file.name == "main.js":
            continue
        yield file


def generate_config(path: Path, include_old: bool = True, output: str = "extract_config.py"):
    # extra version
    package_json = path / "package.json"
    if not package_json.exists():
        log.warn("package.json 不存在")
        return
    with open(package_json) as reader:
        version = json.loads(reader.read())["version"]

    new_config: Dict[str, Config] = {}
    for file in files(path):
        with open(file, "r", encoding="utf-8") as reader:
            content = reader.read()
            for text in extract(content):
                new_config.update({src: Config(src=src, dst=dst) for src, dst in text.config()})

    all_config = {}
    all_config.update(new_config)
    all_config.update(config_dict)
    buf = StringIO()
    buf.write(
        """
from typing import List
from lib.define import Config

config: List[Config] = [
"""
    )
    count = 0
    for src, conf in sorted(all_config.items()):
        if src not in config_dict:
            count += 1
        if src in new_config or include_old:
            buf.write(str(conf))
            buf.write(",\n")
    buf.write("]\n")

    if not new_config:
        log.warn(f"没有提取到任何内容, 请检查路径: {path}")
        return

    fmt_content = black.format_str(buf.getvalue(), mode=black.Mode(line_length=120))
    with open(Path(__file__).parent / output, "w", encoding="utf-8") as writer:
        writer.write(fmt_content)

    log.info(
        f"新增个数: {count}, 汉化进度: {sum(1 for v in new_config.values() if v != '') * 100 / len(new_config):.2f} %"
    )


def replace(path: Path):
    used = {}
    for file in files(path):
        with open(file, "r", encoding="utf-8") as reader:
            content = reader.read()
        # 优先替换 args_len 长的, 否则内部嵌套 children 被替换后, 外部 children 将无法替换
        for text in sorted(extract(content), key=lambda v: (-v.args_len, v.start)):
            if not text.has_dst():
                continue
            src, dst = text.format()
            new_content = content.replace(src, dst)
            if new_content != content:
                used.update(text.config())
            content = new_content

        for src, dst in config_manually:
            content = content.replace(src, dst)

        with open(file, "w", encoding="utf-8") as writer:
            writer.write(content)
    for src, conf in config_dict.items():
        if conf.deleted_at == "" and conf.dst is not None and conf.dst != "" and src not in used:
            log.warn(f"unused: {src}")
