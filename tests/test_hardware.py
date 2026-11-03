"""Tests de scripts/detect_hardware.sh (faux /proc et /sys via HW_SYSROOT) et de la lecture batterie."""
import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "detect_hardware.sh"
sys.path.insert(0, str(ROOT / "web"))


def _fake_root(tmp_path, *, flags="fpu avx2", mem_kb=8_000_000, battery=False,
               chassis=None, pi=False, wifi=False, hailo=False):
    (tmp_path / "proc").mkdir()
    (tmp_path / "proc/cpuinfo").write_text(f"model name\t: Test CPU\nflags\t\t: {flags}\n")
    (tmp_path / "proc/meminfo").write_text(f"MemTotal:       {mem_kb} kB\n")
    (tmp_path / "etc").mkdir()
    (tmp_path / "etc/os-release").write_text('ID=debian\nVERSION_CODENAME=bookworm\n')
    if pi:
        (tmp_path / "proc/device-tree").mkdir()
        (tmp_path / "proc/device-tree/model").write_text("Raspberry Pi 5 Model B\n")
    if battery:
        b = tmp_path / "sys/class/power_supply/BAT0"
        b.mkdir(parents=True)
        (b / "capacity").write_text("87\n")
        (b / "status").write_text("Discharging\n")
    if chassis:
        d = tmp_path / "sys/class/dmi/id"
        d.mkdir(parents=True)
        (d / "chassis_type").write_text(f"{chassis}\n")
    if wifi:
        (tmp_path / "sys/class/net/wlan0/wireless").mkdir(parents=True)
    if hailo:
        (tmp_path / "dev").mkdir()
        (tmp_path / "dev/hailo0").write_text("")
    return tmp_path


def _detect(root, **env):
    full = {**os.environ, "HW_SYSROOT": str(root), "HW_FORCE_ARCH": env.pop("arch", "x86_64"),
            "HW_FORCE_WIFI_AP": env.pop("wifi_ap", "yes")}
    for k in [k for k in full if k.startswith("SURVIVE_")]:
        del full[k]
    full.update(env)
    out = subprocess.run(["bash", str(SCRIPT), "--json"], capture_output=True, text=True,
                         env=full, check=True).stdout
    return json.loads(out)


def test_old_x86_without_avx2_disables_ai(tmp_path):
    res = _detect(_fake_root(tmp_path, flags="fpu sse2"))
    assert res["modules"]["AI"]["state"] == "off"
    assert "AVX2" in res["modules"]["AI"]["why"]


def test_x86_with_avx2_and_ram_enables_ai(tmp_path):
    res = _detect(_fake_root(tmp_path))
    assert res["modules"]["AI"]["state"] == "on"


def test_low_ram_disables_ai(tmp_path):
    res = _detect(_fake_root(tmp_path, mem_kb=2_000_000))
    assert res["modules"]["AI"]["state"] == "off"
    assert "RAM" in res["modules"]["AI"]["why"]


def test_force_on_overrides_auto(tmp_path):
    res = _detect(_fake_root(tmp_path, flags="fpu"), SURVIVE_MODULE_AI="on")
    assert res["modules"]["AI"]["state"] == "on"


def test_remote_ollama_wins(tmp_path):
    res = _detect(_fake_root(tmp_path, flags="fpu"), SURVIVE_OLLAMA_HOST="http://nas:11434")
    assert res["modules"]["AI"]["state"] == "remote"


def test_laptop_enables_lid_and_battery(tmp_path):
    res = _detect(_fake_root(tmp_path, battery=True, chassis=10, wifi=True))
    assert res["modules"]["LID"]["state"] == "on"
    assert res["modules"]["BATTERY"]["state"] == "on"
    assert res["modules"]["HOTSPOT"]["state"] == "on"
    assert res["modules"]["PI_USB"]["state"] == "off"


def test_desktop_has_no_laptop_modules(tmp_path):
    res = _detect(_fake_root(tmp_path, chassis=3))
    assert res["modules"]["LID"]["state"] == "off"
    assert res["modules"]["BATTERY"]["state"] == "off"
    assert res["modules"]["HOTSPOT"]["state"] == "off"  # pas de Wi-Fi


def test_wifi_without_ap_support_disables_hotspot(tmp_path):
    res = _detect(_fake_root(tmp_path, wifi=True), wifi_ap="no")
    assert res["modules"]["HOTSPOT"]["state"] == "off"
    assert "point d'accès" in res["modules"]["HOTSPOT"]["why"]


def test_raspberry_pi_modules(tmp_path):
    res = _detect(_fake_root(tmp_path, pi=True, hailo=True, wifi=True), arch="aarch64")
    m = res["modules"]
    assert res["hardware"]["HW_PLATFORM"] == "pi"
    assert (m["PI_USB"]["state"], m["HAILO"]["state"], m["AI"]["state"]) == ("on", "on", "on")
    assert m["LID"]["state"] == "off"


def test_env_output_is_sourceable(tmp_path):
    root = _fake_root(tmp_path, flags="fpu")
    env = {**os.environ, "HW_SYSROOT": str(root), "HW_FORCE_ARCH": "x86_64"}
    cmd = f'eval "$(bash {SCRIPT})"; echo "$MOD_AI|$MOD_AI_WHY"'
    out = subprocess.run(["bash", "-c", cmd], capture_output=True, text=True, env=env, check=True).stdout
    assert out.startswith("off|")
    assert "AVX2" in out


def test_read_battery(tmp_path):
    from server import _read_battery  # pylint: disable=import-outside-toplevel
    assert _read_battery(str(tmp_path))["present"] is False
    _fake_root(tmp_path, battery=True)
    assert _read_battery(str(tmp_path)) == {"present": True, "percent": 87, "status": "Discharging"}


def test_ai_chat_returns_503_when_module_disabled(monkeypatch):
    import server  # pylint: disable=import-outside-toplevel
    monkeypatch.setattr(server, "AI_DISABLED", True)
    monkeypatch.setattr(server, "AI_MODULE_WHY", "processeur sans AVX2")
    client = server.app.test_client()
    resp = client.post("/api/ai/chat", json={"message": "bonjour"})
    assert resp.status_code == 503
    assert "AVX2" in resp.get_json()["error"]
    assert "désactivé" in client.get("/ai").get_data(as_text=True)
