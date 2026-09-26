#!/usr/bin/env python3
"""Reproducible persistent-MCP versus targeted-shell benchmark runner."""
import argparse, json, math, pathlib, subprocess, time

def metrics(text, elapsed_ms, expected):
    lines = [line for line in text.splitlines() if line.strip() and ":" in line
             and not line.startswith(("freshness=", "trace ", "impact target="))]
    found = [value for value in expected if value.lower() in text.lower()]
    top = lines[:5]
    relevant = sum(any(value.lower() in line.lower() for value in expected) for line in top)
    return {
        "latency_ms": round(elapsed_ms, 2), "characters": len(text),
        "estimated_tokens": math.ceil(len(text) / 4), "lines": len(lines),
        "precision_at_5": round(relevant / max(1, len(top)), 3),
        "recall": round(len(found) / max(1, len(expected)), 3),
        "missing_expected": [value for value in expected if value not in found]
    }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config")
    parser.add_argument("--output", default="tools/SwiftProjectGraph/graph/benchmark-latest.json")
    args = parser.parse_args()
    root = pathlib.Path.cwd().resolve()
    if args.config:
        config_path = root / args.config
    else:
        candidates = sorted((root / "tools/SwiftProjectGraph/Benchmarks").glob("*.json"))
        if not candidates:
            parser.error("no benchmark config found; pass --config")
        config_path = candidates[0]
    suite = json.loads(config_path.read_text())
    command = [str(root / "tools/SwiftProjectGraph/run.sh"), "mcp"]
    started = time.perf_counter()
    server = subprocess.Popen(command, cwd=root, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                              stderr=subprocess.PIPE, text=True, bufsize=1)
    def request(payload):
        begin = time.perf_counter()
        server.stdin.write(json.dumps(payload) + "\n"); server.stdin.flush()
        response = json.loads(server.stdout.readline())
        return response, (time.perf_counter() - begin) * 1000
    request({"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"benchmark","version":"1"}}})
    startup_ms = (time.perf_counter() - started) * 1000
    results = []
    try:
        for index, case in enumerate(suite["cases"], 1):
            response, mcp_ms = request({"jsonrpc":"2.0","id":index,"method":"tools/call",
                                        "params":{"name":case["tool"],"arguments":case["arguments"]}})
            content = response.get("result", {}).get("content", [])
            mcp_text = "\n".join(item.get("text", "") for item in content)
            begin = time.perf_counter()
            baseline = subprocess.run(["/bin/zsh", "-lc", case["baseline"]], cwd=root,
                                      text=True, capture_output=True)
            baseline_ms = (time.perf_counter() - begin) * 1000
            baseline_text = baseline.stdout + baseline.stderr
            results.append({"id":case["id"], "description":case["description"],
                            "expected":case["expected"],
                            "mcp":metrics(mcp_text, mcp_ms, case["expected"]),
                            "non_mcp":metrics(baseline_text, baseline_ms, case["expected"]),
                            "baseline_exit_code":baseline.returncode})
    finally:
        server.terminate(); server.wait(timeout=5)
    report = {"schemaVersion":1, "measuredAt":time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
              "project":suite.get("project", "miataru"), "mcp_startup_ms":round(startup_ms, 2),
              "methodology":"warm persistent stdio MCP; targeted shell baseline; tokens=ceil(chars/4)",
              "results":results}
    output = root / args.output; output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))

if __name__ == "__main__": main()
