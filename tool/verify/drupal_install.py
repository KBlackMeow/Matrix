#!/usr/bin/env python3
"""把 vulhub/drupal:8.5.0 装起来（该镜像设计上是"先手动装"的）。

为什么需要它：Drupal 靶场镜像不带 settings.php，直接访问会 302 到安装向导。
没有这个步骤，Drupal 家族的 exp 只能验证"未安装"的负路径。

流程（Drupal 8.5 的 install.php 表单链）：
  1. 选语言        (install_select_language_form)
  2. 选 profile    (install_select_profile_form) → standard
  3. 数据库配置     (install_settings_form) → sqlite，路径 sites/default/files/.ht.sqlite
  4. 提交后 install.php 自己在服务端跑完批次（一次请求即可）

装完后根路径出现 "Log in" 即视为成功。

已知未解决：即使安装完成，本仓库的 CVE-2018-7600 检测在这个实例上仍然打不中，
exploit POST 返回 Drupal 的通用 500 页。见 docs/exp-unified-architecture.md §9。

用法：
  python3 tool/verify/drupal_install.py http://127.0.0.1:18170
"""

import http.cookiejar
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = sys.argv[1] if len(sys.argv) > 1 else 'http://127.0.0.1:18170'
cj = http.cookiejar.CookieJar()
opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))


def get(path):
    with opener.open(BASE + path, timeout=60) as r:
        return r.read().decode('utf-8', 'replace'), r.geturl()


def post(path, data=None):
    body = urllib.parse.urlencode(data or {}).encode()
    req = urllib.request.Request(
        BASE + path, data=body,
        headers={'Content-Type': 'application/x-www-form-urlencoded'})
    with opener.open(req, timeout=300) as r:
        return r.read().decode('utf-8', 'replace'), r.geturl()


def hidden(html):
    out = {}
    for m in re.finditer(r'<input[^>]*type="hidden"[^>]*>', html):
        tag = m.group(0)
        name = re.search(r'name="([^"]+)"', tag)
        value = re.search(r'value="([^"]*)"', tag)
        if name:
            out[name.group(1)] = value.group(1) if value else ''
    return out


def title(html):
    m = re.search(r'<title>(.*?)</title>', html)
    return m.group(1) if m else '?'


def main():
    html, _ = get('/core/install.php')
    print('[1]', title(html))

    form = hidden(html)
    form.update(langcode='en', op='Save and continue')
    html, _ = post('/core/install.php', form)
    print('[2]', title(html))

    form = hidden(html)
    form.update(profile='standard', op='Save and continue')
    html, url = post('/core/install.php?rewrite=ok&langcode=en', form)
    print('[3]', title(html))

    form = hidden(html)
    form.update({
        'driver': 'sqlite',
        'sqlite[database]': 'sites/default/files/.ht.sqlite',
        'sqlite[prefix]': '',
        'op': 'Save and continue',
    })
    html, url = post(
        '/core/install.php?rewrite=ok&langcode=en&profile=standard', form)
    print('[4]', title(html), url)

    # 安装批次必须用页面里给出的完整 uri 驱动（缺 rewrite/profile/langcode
    # 会退回"选语言"，看起来像安装完成、实际 schema 只建了一小半）。
    def batch_uri_of(page):
        m = re.search(r'"uri":"([^"]+)"', page)
        if not m:
            return None
        return m.group(1).replace('\\/', '/').replace('\\u0026', '&')

    uri = batch_uri_of(html)
    for i in range(60):
        if not uri:
            break
        html, _ = post(uri)
        print('   batch', i, title(html))
        if 'complete' in title(html).lower():
            break
        uri = batch_uri_of(html)

    # 最后一步：Configure site（站点名 + 管理员账号）
    if 'configure site' in title(html).lower():
        form = hidden(html)
        form.update({
            'site_name': 'vulhub',
            'site_mail': 'admin@example.com',
            'account[name]': 'admin',
            'account[mail]': 'admin@example.com',
            'account[pass][pass1]': 'adminadmin',
            'account[pass][pass2]': 'adminadmin',
            'update_status_module[1]': '1',
            'op': 'Save and continue',
        })
        html, url = post('/core/install.php?rewrite=ok&langcode=en&profile=standard&id=1&op=start', form)
        print('[5]', title(html), url)

    # 完成判定：configure 步骤之后首页标题会变成 "Welcome to <site>"。
    # 不能用"出现 Log in"判断——半装状态（只建了 20 多张表）也有登录链接，
    # 上一轮就是因为这个把半装当成装完，得出"exp 打不中"的错误结论。
    html, _ = get('/')
    if 'welcome to' in html.lower():
        print('[+] 安装完成：', title(html))
        return 0
    print('[!] 未确认安装完成，标题：', title(html))
    return 1


if __name__ == '__main__':
    sys.exit(main())
