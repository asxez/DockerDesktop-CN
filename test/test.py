# -*- coding: utf-8 -*-
#
# Copyright (C) 2024 ASXE  All Rights Reserved
#
# @Time    : 2024/8/9 下午4:21
# @Author  : ASXE

from lib.extract import extract_children


def test_extract_nested_children():
    code = 'children:["The Extensions Marketplace is managed by your organization. See"," ",(0,O.jsx)(s.G,{href:"https://hub.docker.com/search?q=&type=extension",children:"public marketplace"}),r?(0,O.jsxs)(O.Fragment,{children:[" ","and"," ",(0,O.jsx)(s.G,{href:r,children:"contact your administrator"})," ","for requests."]}):"."]'
    srcs = set(text.src for text in extract_children(code))
    assert srcs == {
        "The Extensions Marketplace is managed by your organization. See {0}{1}",
        "public marketplace",
        " and {0} for requests.",
        "contact your administrator",
    }

    code = 'children:[(0,B.jsx)(be.N,{name:"CREATED",value:(0,Ce.P1)(1e3*e.Created)}),(0,B.jsx)(be.N,{name:"SIZE",value:(0,Ce.z3)(e.Size)})]'
    for text in extract_children(code):
        print(text.src)


def test_extract_children():
    def _test_extract_children(code: str, src: str, dst: str, expected_dst: str):
        text = sorted(extract_children(code), key=lambda x: x.start)[0]
        assert text.src == src
        text.dst = dst
        replace_src, replace_dst = text.format()
        assert replace_src == code
        assert replace_dst == expected_dst

    _test_extract_children(
        'children:["The ",(0,y.jsx)("strong",{children:"volumes"})," element tells Compose to mount the local folder ",(0,y.jsx)("strong",{children:"./app"})," to"," ",(0,y.jsx)("strong",{children:"/usr/src/app"})," in the container for the"," ",(0,y.jsx)("strong",{children:"todo-app"})," service. This particular bind mount overwrites the static contents of the"," ",(0,y.jsx)("strong",{children:"/usr/src/app"})," directory in the container and creates what is known as a development container. The second instruction, ",(0,y.jsx)("strong",{children:"/usr/src/app/node_modules"}),", prevents the bind mount from overwriting the container\'s"," ",(0,y.jsx)("strong",{children:"node_modules"})," directory to preserve the packages installed in the container."]',
        "The {0} element tells Compose to mount the local folder {1} to {2} in the container for the {3} service. This particular bind mount overwrites the static contents of the {4} directory in the container and creates what is known as a development container. The second instruction, {5}, prevents the bind mount from overwriting the container's {6} directory to preserve the packages installed in the container.",
        "该 {0} 元素告诉 Compose to 挂载本地文件夹 {1} 到 {3} 服务容器中的 {2} 文件夹。这个特定的绑定挂载将覆盖容器中的静态内容 {4} 目录，并创建为开发容器。第二条指令 {5}，可以防止绑定挂载覆盖容器的 {6} 目录，以保留容器中安装的软件包。",
        'children:["该 ",(0,y.jsx)("strong",{children:"volumes"})," 元素告诉 Compose to 挂载本地文件夹 ",(0,y.jsx)("strong",{children:"./app"})," 到 ",(0,y.jsx)("strong",{children:"todo-app"})," 服务容器中的 ",(0,y.jsx)("strong",{children:"/usr/src/app"})," 文件夹。这个特定的绑定挂载将覆盖容器中的静态内容 ",(0,y.jsx)("strong",{children:"/usr/src/app"})," 目录，并创建为开发容器。第二条指令 ",(0,y.jsx)("strong",{children:"/usr/src/app/node_modules"}),"，可以防止绑定挂载覆盖容器的 ",(0,y.jsx)("strong",{children:"node_modules"})," 目录，以保留容器中安装的软件包。"]',
    )
    _test_extract_children(
        'children:["Terminal has exited",(0,k.jsx)(M.A,{variant:"outlined",size:"small",sx:{height:30},onClick:()=>{desktopIpcClient.terminal.exit(p.id)},children:"Close"})]',
        "Terminal has exited{0}",
        "终端已经退出{0}",
        'children:["终端已经退出",(0,k.jsx)(M.A,{variant:"outlined",size:"small",sx:{height:30},onClick:()=>{desktopIpcClient.terminal.exit(p.id)},children:"Close"})]',
    )
    _test_extract_children(
        'children:[(0,B.jsx)(ke.A,{fontSize:"xs",sx:{marginRight:"4px"}}),"Installing update..."]',
        "{0}Installing update...",
        "{0}安装更新中...",
        'children:[(0,B.jsx)(ke.A,{fontSize:"xs",sx:{marginRight:"4px"}}),"安装更新中..."]',
    )
    _test_extract_children(
        'children:["The \'",t[0],"\' ",e," is selected for deletion.",i?` ${i}`:null]',
        "The '{0}' {1} is selected for deletion.{2}",
        "'{0}' {1} 被选中删除。{2}",
        'children:["\'",t[0],"\' ",e," 被选中删除。",i?` ${i}`:null]',
    )
    _test_extract_children(
        'children:["You can check it out in the ",(0,y.jsx)("strong",{children:"Containers"})," tab (",(0,y.jsx)("strong",{children:"welcome-to-docker"}),")."]',
        "You can check it out in the {0} tab ({1}).",
        "你可以在 {0} 页面查看（{1}）。",
        'children:["你可以在 ",(0,y.jsx)("strong",{children:"Containers"})," 页面查看（",(0,y.jsx)("strong",{children:"welcome-to-docker"}),"）。"]',
    )
    _test_extract_children(
        'children:["You can search images by selecting the bar at the top, or by using the ","Mac"===e?"⌘ + K":"Ctrl + K"," shortcut. Search for"," ",(0,y.jsx)("strong",{children:"welcome-to-docker"})," to find the image used in this guide."]',
        "You can search images by selecting the bar at the top, or by using the {0} shortcut. Search for {1} to find the image used in this guide.",
        "你可以通过选择顶部的搜索栏，或使用 {0} 快捷键搜索。搜索 {1} 以找到该指南中使用的镜像。",
        'children:["你可以通过选择顶部的搜索栏，或使用 ","Mac"===e?"⌘ + K":"Ctrl + K"," 快捷键搜索。搜索 ",(0,y.jsx)("strong",{children:"welcome-to-docker"})," 以找到该指南中使用的镜像。"]',
    )
    _test_extract_children(
        """children:["When installing Docker Desktop with the ",t,", in-app updates are disabled to ensure your organization maintains the required version. To update, download the latest installer from the"," ",(0,f.jsx)(s.G,{href:"https://app.docker.com/admin",children:"Docker Admin Console"})," ",'under "Security and Access"']""",
        'When installing Docker Desktop with the {0}, in-app updates are disabled to ensure your organization maintains the required version. To update, download the latest installer from the {1} under "Security and Access"',
        '使用 {0} 安装 Docker Desktop 时，将禁用应用内更新以确保您的组织维护所需的版本。更新请从"安全和访问"下的 {1} 下载最新的安装程序',
        """children:["使用 ",t,' 安装 Docker Desktop 时，将禁用应用内更新以确保您的组织维护所需的版本。更新请从"安全和访问"下的 ',(0,f.jsx)(s.G,{href:"https://app.docker.com/admin",children:"Docker Admin Console"})," 下载最新的安装程序"]""",
    )
    _test_extract_children(
        """children:["Repository ",s?"has been":"will be",' cloned into "',x,'" within the path above.']""",
        'Repository {0} cloned into "{1}" within the path above.',
        '存储库{0}克隆到上述路径内的"{1}"中。',
        """children:["存储库",s?"has been":"will be",'克隆到上述路径内的"',x,'"中。']""",
    )
