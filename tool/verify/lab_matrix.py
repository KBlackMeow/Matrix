#!/usr/bin/env python3
"""逐个启动 vulhub 靶场 -> 跑对应 exp 检测 -> 关闭，输出矩阵结果。"""
import json
import os
import re
import socket
import subprocess
import sys
import time

VULHUB = os.environ.get("VULHUB_DIR", "/Users/illya/Projects/vulhub")
MATRIX = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(os.path.dirname(MATRIX))
DART = os.environ.get("DART_BIN", "dart")

# (lab 相对目录, 检测用例, 额外路径)
LABS = [
    ("struts2/s2-005", "s2005-check", None),
    ("struts2/s2-007", "s2007-check", None),
    ("struts2/s2-032", "s2032-check", None),
    ("struts2/s2-045", "s2045-check", None),
    ("struts2/s2-052", "s2052-check", None),
    ("struts2/s2-053", "s2053-check", None),
    ("struts2/s2-057", "s2057-check", None),
    ("struts2/s2-059", "s2059-check", None),
    ("spring/CVE-2016-4977", "spring-4977", None),
    ("spring/CVE-2017-8046", "spring-8046", None),
    ("spring/CVE-2018-1273", "spring-1273", None),
    ("spring/CVE-2022-22963", "spring-22963", None),
    ("spring/CVE-2022-22965", "spring-22965", None),
    ("php/8.1-backdoor", "php-check", None),
    ("php/CVE-2012-1823", "phpcgi-check", None),
    ("tomcat/CVE-2017-12615", "tomcat-check", None),
    ("httpd/CVE-2021-41773", "httpd-check", None),
    ("drupal/CVE-2018-7600", "drupal-check", None),
    ("nacos/CVE-2021-29441", "nacos-check", None),
    ("xxl-job/unacc", "xxljob-check", 9999),
    ("shiro/CVE-2016-4437", "shiro-check", None),
    ("thinkphp/5.0.23-rce", "thinkphp-check", None),
    ("thinkphp/5-rce", "thinkphp-check", None),
    ("thinkphp/2-rce", "thinkphp-check", None),
]


ENV = dict(os.environ, DOCKER_BUILDKIT="0")


def run(cmd, cwd=None, timeout=600, check=False):
    return subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout,
        check=check, env=ENV
    )


def project_of(lab):
    # 每个靶场独立 compute 项目名：否则服务名相同的靶场会复用同一个容器
    # （MySQL/Tomcat 的容器名都是 struts2/web/...），导致"打错靶场"。
    slug = lab.replace("/", "-").replace("CVE-", "").lower()
    return "mxlab-" + slug


def published_ports(project):
    out = run(["docker", "ps", "--filter",
               f"label=com.docker.compose.project={project}",
               "--format", "{{.Ports}}"]).stdout
    ports = []
    for line in out.splitlines():
        for m in re.finditer(r":(\d+)->", line):
            ports.append(int(m.group(1)))
    return ports


def wait_http(port, timeout=180):
    """等应用真正能回 HTTP（Docker 端口映射会比应用早就绪）。"""
    deadline = time.time() + timeout
    while time.time() < deadline:
        r = run(["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                 "--max-time", "3", f"http://127.0.0.1:{port}/"])
        if r.stdout.strip() not in ("", "000"):
            return True
        time.sleep(2)
    return False


def compose_up(lab):
    path = os.path.join(VULHUB, lab)
    proj = project_of(lab)
    ids = run(["docker", "ps", "-aq", "--filter",
               f"label=com.docker.compose.project={proj}"]).stdout.split()
    if ids:
        run(["docker", "rm", "-f", *ids], timeout=120)
    r = run(["docker", "compose", "-p", proj, "up", "-d"], cwd=path, timeout=1800)
    if r.returncode != 0:
        r = run(["docker", "compose", "-p", proj, "up", "-d", "--build"],
                cwd=path, timeout=1800)
    return r


def compose_down(lab):
    path = os.path.join(VULHUB, lab)
    run(["docker", "compose", "-p", project_of(lab), "down", "-v", "--remove-orphans"],
        cwd=path, timeout=300)


def pick_port(project):
    ports = published_ports(project)
    if 8848 in ports:
        return 8848
    if not ports:
        return None
    # 排除调试/管理端口
    for p in ports:
        if p not in (5005, 3306, 6379):
            return p
    return ports[0]


def main():
    only = sys.argv[1:] if len(sys.argv) > 1 else None
    results = []
    for lab, case, _ in LABS:
        if only and lab not in only and case not in only:
            continue
        print(f"\n===== {lab} -> {case} =====", flush=True)
        compose_down(lab)  # 清掉残留
        up = compose_up(lab)
        if up.returncode != 0:
            results.append({"lab": lab, "case": case, "status": "START_FAIL",
                            "detail": (up.stderr or up.stdout)[-300:]})
            compose_down(lab)
            continue
        port = None
        deadline = time.time() + 240
        forced = _ if isinstance(_, int) else None
        while time.time() < deadline:
            port = forced or pick_port(project_of(lab))
            if port and wait_http(port, timeout=5):
                break
            port = None
            time.sleep(2)
        if not port:
            results.append({"lab": lab, "case": case, "status": "NO_PORT", "detail": ""})
            compose_down(lab)
            continue
        url = f"http://127.0.0.1:{port}"
        # 给应用一点启动时间（Java/Node 类）
        time.sleep(5)
        try:
            line = ""
            for attempt in range(3):
                r = run([DART, "tool/verify/exp_live.dart", case, url],
                        cwd=PROJECT, timeout=240)
                out = (r.stdout or "").strip().splitlines()
                line = out[-1] if out else ""
                if not line:
                    err = (r.stderr or "").strip().splitlines()
                    line = "[stderr] " + (err[-1][:300] if err else "no output")
                if "Broken pipe" not in line and "Connection refused" not in line:
                    break
                time.sleep(5)
            joined = " | ".join(out)
            hit = next((l.strip() for l in out if "vulnerable=true" in l), "")
            skip = next((l.strip() for l in out if "failed=true" in l), "")
            if not hit and "isshiro=true" in joined.lower():
                hit = next(l for l in out if "isShiro=true" in l)
            status = "VULN" if hit else ("SKIP" if skip else "CLEAN")
            results.append({"lab": lab, "case": case, "url": url,
                            "status": status,
                            "detail": (hit or skip or joined)[:220]})
            print(line, flush=True)
        except subprocess.TimeoutExpired:
            results.append({"lab": lab, "case": case, "url": url,
                            "status": "TIMEOUT", "detail": ""})
        compose_down(lab)
        with open("/tmp/lab_matrix.json", "w") as f:
            json.dump(results, f, ensure_ascii=False, indent=2)

    print("\n===== SUMMARY =====")
    for r in results:
        print(f"{r['lab']:28} {r['case']:16} {r['status']:7} {r['detail'][:150]}")
    with open("/tmp/lab_matrix.json", "w") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
