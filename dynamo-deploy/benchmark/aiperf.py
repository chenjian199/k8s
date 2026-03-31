#!/usr/bin/env python3
# SPDX-FileCopyrightText: Copyright (c) 2025 NVIDIA CORPORATION & AFFILIATES. All rights reserved.
# SPDX-License-Identifier: Apache-2.0

"""
Disaggregated serving benchmark script using aiperf.
This script starts the disaggregated serving setup and runs performance tests.
"""

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import List, Optional

# Default configuration
DEFAULT_MODEL_PATH = "/models/deepseek-ai/DeepSeek-R1-Distill-Llama-8B"
DEFAULT_SERVED_MODEL_NAME = "/nfs/nfs/models/deepseek-ai/DeepSeek-R1-Distill-Llama-8B"
DEFAULT_ISL = 500
DEFAULT_OSL = 20
DEFAULT_STDDEV = 0
DEFAULT_CONCURRENCIES = list(range(101, 501, 100))
DEFAULT_SERVICE_URL = "http://127.0.0.1:8001"
DEFAULT_DURATION = 120
# Default output under project root: /home/.../dynamo/cjworkspace/temp/sglangv2/disagg
DEFAULT_OUTPUT_DIR = Path(__file__).resolve().parents[1] / "temp/vllm/disagg"


def parse_args():
    """Parse command line arguments"""
    parser = argparse.ArgumentParser(
        description="Run disaggregated serving benchmark with aiperf"
    )
    parser.add_argument(
        "--model-path",
        type=str,
        default=DEFAULT_MODEL_PATH,
        help=f"Path to the model (default: {DEFAULT_MODEL_PATH})",
    )
    parser.add_argument(
        "--served-model-name",
        type=str,
        default=DEFAULT_SERVED_MODEL_NAME,
        help=f"Served model name (default: {DEFAULT_SERVED_MODEL_NAME})",
    )
    parser.add_argument(
        "--service-url",
        type=str,
        default=DEFAULT_SERVICE_URL,
        help=f"Service URL (default: {DEFAULT_SERVICE_URL})",
    )
    parser.add_argument(
        "--isl",
        type=int,
        default=DEFAULT_ISL,
        help=f"Input sequence length mean (default: {DEFAULT_ISL})",
    )
    parser.add_argument(
        "--osl",
        type=int,
        default=DEFAULT_OSL,
        help=f"Output sequence length mean (default: {DEFAULT_OSL})",
    )
    parser.add_argument(
        "--stddev",
        type=int,
        default=DEFAULT_STDDEV,
        help=f"Input sequence length standard deviation (default: {DEFAULT_STDDEV})",
    )
    parser.add_argument(
        "--concurrencies",
        type=str,
        default=",".join(map(str, DEFAULT_CONCURRENCIES)),
        help=f"Comma-separated concurrency levels (default: {','.join(map(str, DEFAULT_CONCURRENCIES))})",
    )
    parser.add_argument(
        "--output-dir",
        type=str,
        default=str(DEFAULT_OUTPUT_DIR),
        help=f"Output directory for benchmark results (default: {DEFAULT_OUTPUT_DIR})",
    )
    parser.add_argument(
        "--deployment-name",
        type=str,
        default="disagg",
        help="Deployment name (default: disagg)",
    )
    parser.add_argument(
        "--use-server-token-count",
        action="store_true",
        default=False,
        help="Use server-side token counting instead of local tokenizer (skips tokenizer loading, disables synthetic input generation)",
    )
    return parser.parse_args()


def check_health(service_url: str, max_retries: int = 30, retry_interval: int = 2) -> bool:
    """Check if frontend service is healthy"""
    import urllib.request
    import urllib.error

    url = f"{service_url}/health"
    for i in range(max_retries):
        try:
            response = urllib.request.urlopen(url, timeout=2)
            if response.getcode() == 200:
                print(f"✅ Frontend health check passed on service URL {service_url}")
                return True
        except (urllib.error.URLError, OSError) as e:
            if i < max_retries - 1:
                print(f"⏳ Waiting for service to be ready... ({i+1}/{max_retries})")
                time.sleep(retry_interval)
            else:
                print(f"❌ Service health check failed: {e}")
                return False
    return False



def check_tokenizer(tokenizer_path: str) -> bool:
    """Check if the tokenizer can be loaded via transformers."""
    try:
        result = subprocess.run(
            [
                sys.executable, "-c",
                f"from transformers import AutoTokenizer; AutoTokenizer.from_pretrained('{tokenizer_path}')",
            ],
            timeout=30,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        return result.returncode == 0
    except Exception:
        return False


def _build_aiperf_cmd(
    service_url: str,
    served_model_name: str,
    tokenizer_path: str,
    isl: int,
    osl: int,
    stddev: int,
    concurrency: int,
    output_dir: Path,
    use_server_token_count: bool,
) -> list:
    cmd = [
        "aiperf",
        "profile",
        "-m",
        served_model_name,           # API 请求时服务端识别的模型名
        "--endpoint-type",
        "chat",
        "--streaming",
        "-u",
        service_url,
        "--concurrency",
        str(concurrency),
        "--output-tokens-mean",
        str(osl),
        "--request-count",
        str(concurrency * 2),
        # "--benchmark-duration",
        # str(DEFAULT_DURATION),
        "--extra-inputs",
        f"max_tokens:{osl}",
        "--extra-inputs",
        f"min_tokens:{osl}",
        "--extra-inputs",
        "ignore_eos:true",
        "--artifact-dir",
        str(output_dir.resolve()),
    ]
    if use_server_token_count:
        cmd.append("--use-server-token-count")
    else:
        cmd += [
            "--tokenizer",
            tokenizer_path,          # 本地文件路径，用于实际加载 tokenizer
            "--synthetic-input-tokens-mean",
            str(isl),
            "--synthetic-input-tokens-stddev",
            str(stddev),
        ]
    return cmd


def _exec_aiperf_cmd(cmd: list, concurrency: int) -> tuple[bool, str]:
    """Execute an aiperf command and return (success, stdout)."""
    aip_process: Optional[subprocess.Popen] = None
    try:
        aip_process = subprocess.Popen(
            cmd,
            cwd=str(Path.cwd()),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        stdout, _ = aip_process.communicate(timeout=3600)
        if aip_process.returncode == 0:
            return True, stdout
        return False, stdout
    except subprocess.TimeoutExpired:
        print(f"⏱️  Aiperf timed out for concurrency {concurrency}")
        if aip_process is not None:
            aip_process.kill()
            aip_process.wait()
        return False, ""
    except Exception as e:
        print(f"❌ Error running aiperf: {e}")
        return False, ""


def run_aiperf(
    service_url: str,
    model_path: str,
    served_model_name: str,
    isl: int,
    osl: int,
    stddev: int,
    concurrency: int,
    output_dir: Path,
    use_server_token_count: bool = False,
) -> bool:
    """Run aiperf benchmark for a specific concurrency level.

    model_path  : local filesystem path used for --tokenizer (e.g. /models/...)
    served_model_name : model identifier sent to the API via -m (e.g. /nfs/nfs/models/...)
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    cmd = _build_aiperf_cmd(
        service_url, served_model_name, model_path, isl, osl, stddev,
        concurrency, output_dir, use_server_token_count,
    )
    print(f"📊 Running aiperf: ISL={isl}, OSL={osl}, Concurrency={concurrency}", flush=True)
    print(f"🔧 Command: {' '.join(cmd)}", flush=True)

    success, stdout = _exec_aiperf_cmd(cmd, concurrency)

    # Auto-retry with server-side token counting on tokenizer failure
    if not success and not use_server_token_count and "Tokenizer Configuration Error" in stdout:
        print("⚠️  Tokenizer load failed — retrying with --use-server-token-count ...", flush=True)
        cmd = _build_aiperf_cmd(
            service_url, served_model_name, model_path, isl, osl, stddev,
            concurrency, output_dir, use_server_token_count=True,
        )
        print(f"🔧 Retry command: {' '.join(cmd)}", flush=True)
        success, stdout = _exec_aiperf_cmd(cmd, concurrency)

    if success:
        print(f"✅ Aiperf completed successfully for concurrency {concurrency}")
        if stdout:
            print(stdout)
        return True
    else:
        print(f"❌ Aiperf failed for concurrency {concurrency}")
        if stdout:
            print("📋 Output:")
            print(stdout)
        return False


def run_concurrency_sweep(
    service_url: str,
    model_path: str,
    served_model_name: str,
    isl: int,
    osl: int,
    stddev: int,
    concurrencies: List[int],
    output_dir: Path,
    use_server_token_count: bool = False,
) -> None:
    """Run aiperf benchmark across multiple concurrency levels"""
    print(f"🎯 Starting concurrency sweep for {served_model_name}")
    print(f"📁 Results will be saved to: {output_dir}")
    print(f"🔢 Concurrency levels: {concurrencies}")
    print(f"📏 ISL={isl}, OSL={osl}, StdDev={stddev}")
    if use_server_token_count:
        print("ℹ️  Using server-side token counting (tokenizer disabled)")

    for c in concurrencies:
        print(f"\n{'='*60}")
        print(f"🚀 Starting concurrency level {c}")
        print(f"{'='*60}")
        concurrency_dir = output_dir / f"c{c}"
        success = run_aiperf(
            service_url, model_path, served_model_name, isl, osl, stddev, c,
            concurrency_dir, use_server_token_count=use_server_token_count,
        )
        if not success:
            print(f"⚠️  Warning: Benchmark failed for concurrency {c}, continuing...")
        time.sleep(5)  # Brief pause between runs

    print(f"\n✅ Concurrency sweep completed!")
    print(f"📁 All results available at: {output_dir}")


def cleanup_processes(processes: List[subprocess.Popen]) -> None:
    """Clean up all background processes"""
    print("\n🧹 Cleaning up background processes...")
    for process in processes:
        if process and process.poll() is None:
            try:
                process.terminate()
                process.wait(timeout=5)
                print(f"✅ Terminated process {process.pid}")
            except subprocess.TimeoutExpired:
                process.kill()
                print(f"⚠️  Killed process {process.pid}")
            except Exception as e:
                print(f"⚠️  Error terminating process {process.pid}: {e}")


def main():
    """Main function"""
    args = parse_args()
    concurrencies = [int(c.strip()) for c in args.concurrencies.split(",")]
    # Parse model name from path
    model_path = args.model_path
    served_model_name = args.served_model_name
    # Service URL
    service_url = args.service_url
    deployment_name = args.deployment_name
    # Output directory - convert to absolute path early to avoid path issues
    output_dir = Path(args.output_dir).resolve() / f"{deployment_name}_isl{args.isl}_osl{args.osl}"
    output_dir.mkdir(parents=True, exist_ok=True)

    processes: List[subprocess.Popen] = []

    # Determine whether to use server-side token counting.
    # If the user explicitly requested it, honour that; otherwise probe the tokenizer.
    use_server_token_count = args.use_server_token_count
    if not use_server_token_count:
        print(f"🔍 Probing tokenizer at: {model_path}", flush=True)
        if check_tokenizer(model_path):
            print("✅ Tokenizer loaded successfully")
        else:
            print("⚠️  Tokenizer unavailable — switching to --use-server-token-count mode automatically")
            use_server_token_count = True

    try:
        # Check health
        if not check_health(service_url):
            print("❌ Service health check failed, exiting...")
            return 1

        run_concurrency_sweep(
            service_url=service_url,
            model_path=model_path,
            served_model_name=served_model_name,
            isl=args.isl,
            osl=args.osl,
            stddev=args.stddev,
            concurrencies=concurrencies,
            output_dir=output_dir,
            use_server_token_count=use_server_token_count,
        )
    except Exception as e:
        print(f"❌ Error: {e}")
        return 1

    print("\n✅ Script completed successfully!")
    return 0

if __name__ == "__main__":
    main()