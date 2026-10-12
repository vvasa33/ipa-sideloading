#!/usr/bin/env python3
"""LAN stats for the iPad control center. Bind is local network only."""

import asyncio
import socket
import time

import psutil
from fastapi import FastAPI
from contextlib import asynccontextmanager
import uvicorn

sample = {
    "cpu": 0.0,
    "per_core": [],
    "rx_bps": 0.0,
    "tx_bps": 0.0,
}


def cpu_temp():
    try:
        temps = psutil.sensors_temperatures() or {}
    except Exception:
        return None
    for key in ("coretemp", "k10temp", "cpu_thermal"):
        entries = temps.get(key) or []
        for entry in entries:
            if entry.current:
                return round(entry.current, 1)
    for entries in temps.values():
        for entry in entries:
            label = (entry.label or "").lower()
            if "package" in label or label.startswith("core"):
                return round(entry.current, 1)
    return None


def disk_stat():
    try:
        disk = psutil.disk_usage("/")
    except Exception:
        return {"total": 0, "used": 0, "percent": 0.0}
    return {"total": disk.total, "used": disk.used, "percent": disk.percent}


async def sampler():
    psutil.cpu_percent(interval=None, percpu=True)
    previous = psutil.net_io_counters()
    previous_time = time.monotonic()
    while True:
        await asyncio.sleep(1)
        cores = psutil.cpu_percent(interval=None, percpu=True) or []
        sample["per_core"] = cores
        sample["cpu"] = (sum(cores) / len(cores)) if cores else 0.0
        now = time.monotonic()
        counters = psutil.net_io_counters()
        elapsed = max(now - previous_time, 0.001)
        sample["rx_bps"] = max(0.0, (counters.bytes_recv - previous.bytes_recv) / elapsed)
        sample["tx_bps"] = max(0.0, (counters.bytes_sent - previous.bytes_sent) / elapsed)
        previous = counters
        previous_time = now


def lan_ip():
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.connect(("8.8.8.8", 80))
        address = sock.getsockname()[0]
        sock.close()
        return address
    except Exception:
        return "127.0.0.1"


@asynccontextmanager
async def lifespan(_app: FastAPI):
    task = asyncio.create_task(sampler())
    print(f"Stats on http://{lan_ip()}:8765/stats", flush=True)
    yield
    task.cancel()


app = FastAPI(lifespan=lifespan)


@app.get("/stats")
def stats():
    memory = psutil.virtual_memory()
    swap = psutil.swap_memory()
    try:
        load = psutil.getloadavg()
    except (OSError, AttributeError):
        load = (0.0, 0.0, 0.0)
    return {
        "hostname": socket.gethostname(),
        "cpu_percent": sample["cpu"],
        "per_core": sample["per_core"],
        "load_avg": [load[0], load[1], load[2]],
        "mem": {"total": memory.total, "used": memory.used, "percent": memory.percent},
        "swap": {"total": swap.total, "used": swap.used, "percent": swap.percent},
        "cpu_temp": cpu_temp(),
        "disk": disk_stat(),
        "net_rx_bps": sample["rx_bps"],
        "net_tx_bps": sample["tx_bps"],
        "uptime_s": time.time() - psutil.boot_time(),
    }


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8765)
