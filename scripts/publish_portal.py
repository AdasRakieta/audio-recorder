#!/usr/bin/env python3
"""Publish an unsigned IPA as a private SideStore source and download page."""

import argparse
import hashlib
import html
import ipaddress
import json
import os
import plistlib
import re
import shutil
import tempfile
import urllib.parse
import zipfile
from datetime import datetime, timezone
from pathlib import Path


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as out:
        out.write(data)
        temporary = Path(out.name)
    temporary.chmod(0o644)
    os.replace(temporary, path)


def package_info(ipa: Path) -> dict:
    with zipfile.ZipFile(ipa) as archive:
        plists = [name for name in archive.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)]
        if len(plists) != 1:
            raise ValueError("IPA must contain exactly one app Info.plist")
        return plistlib.loads(archive.read(plists[0]))


def publish(ipa: Path, output: Path, base_url: str) -> None:
    parsed = urllib.parse.urlparse(base_url)
    if not parsed.netloc or parsed.query or parsed.fragment or parsed.username or parsed.password:
        raise ValueError("base URL must be a directory URL without credentials or query")
    is_lan = parsed.scheme == "http"
    if is_lan:
        try:
            address = ipaddress.IPv4Address(parsed.hostname)
        except (ipaddress.AddressValueError, TypeError) as error:
            raise ValueError("HTTP requires an RFC1918 IPv4 address") from error
        local_ranges = ("10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16")
        if not any(address in ipaddress.IPv4Network(network) for network in local_ranges):
            raise ValueError("HTTP is allowed only on a private LAN address")
    elif parsed.scheme != "https":
        raise ValueError("base URL must use HTTPS or private-LAN HTTP")
    base_url = base_url.rstrip("/")
    info = package_info(ipa)
    bundle = info["CFBundleIdentifier"]
    version = info["CFBundleShortVersionString"]
    build = info["CFBundleVersion"]
    if bundle != "io.github.audiorecorder.probe":
        raise ValueError(f"unexpected bundle identifier: {bundle}")
    if not re.fullmatch(r"[0-9][0-9A-Za-z.]*", version) or not re.fullmatch(r"[0-9][0-9A-Za-z.]*", build):
        raise ValueError("invalid IPA version or build number")
    digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
    name = f"RecorderProbe-{version}-{build}-unsigned.ipa"
    release = output / "releases" / name
    if release.exists() and hashlib.sha256(release.read_bytes()).hexdigest() != digest:
        raise ValueError("same version already published with different content; bump build number")
    release.parent.mkdir(parents=True, exist_ok=True)
    if not release.exists():
        shutil.copyfile(ipa, release)
    atomic_write(release.with_suffix(".ipa.sha256"), f"{digest}  {name}\n".encode())

    source_path = output / "source.json"
    versions = []
    if source_path.exists():
        previous = json.loads(source_path.read_text(encoding="utf-8"))
        apps = previous.get("apps", [])
        if len(apps) != 1 or apps[0].get("bundleIdentifier") != bundle:
            raise ValueError("existing source belongs to another app")
        versions = apps[0].get("versions", [])
        previous_base = previous.get("website", "").rstrip("/")
        if previous_base and previous_base != base_url:
            for item in versions:
                old_url = item.get("downloadURL", "")
                if old_url.startswith(previous_base + "/releases/"):
                    item["downloadURL"] = base_url + old_url[len(previous_base):]
    download_url = f"{base_url}/releases/{name}"
    current = next((item for item in versions if item["version"] == version and item["buildVersion"] == build), None)
    if current and current["downloadURL"] != download_url:
        raise ValueError("existing version points to a different URL")
    entry = {
        "version": version,
        "buildVersion": build,
        "date": datetime.now(timezone.utc).date().isoformat(),
        "localizedDescription": "Prototyp sprawdzający nagrywanie dźwięku z Teams na iPadOS 27.",
        "downloadURL": download_url,
        "size": ipa.stat().st_size,
        "minOSVersion": "27.0",
    }
    if current:
        current.update({"size": entry["size"], "downloadURL": download_url})
    else:
        versions.insert(0, entry)
    microphone = info.get("NSMicrophoneUsageDescription")
    privacy = {"NSMicrophoneUsageDescription": microphone} if microphone else {}
    source = {
        "name": "Recorder Probe",
        "subtitle": "Prywatne wydania na iPada",
        "website": base_url + "/",
        "iconURL": base_url + "/icon.png",
        "apps": [{
            "name": "Recorder Probe",
            "bundleIdentifier": bundle,
            "developerName": "Audio Recorder",
            "subtitle": "Test nagrywania Teams",
            "localizedDescription": "Prototyp techniczny. Nagrywa wyłącznie dźwięk i zapisuje raport z testu.",
            "iconURL": base_url + "/icon.png",
            "tintColor": "#315AA8",
            "category": "utilities",
            "versions": versions,
            "appPermissions": {"entitlements": [], "privacy": privacy},
        }],
    }
    atomic_write(source_path, (json.dumps(source, ensure_ascii=False, indent=2) + "\n").encode())
    shutil.copyfile(Path(__file__).with_name("icon.png"), output / "icon.png")
    source_link = "sidestore://source?url=" + urllib.parse.quote(base_url + "/source.json", safe="")
    install_link = "sidestore://install?url=" + urllib.parse.quote(download_url, safe="")
    if is_lan:
        buttons = f'''<a class="button" href="{html.escape(source_link, quote=True)}">Dodaj źródło w SideStore</a><a class="button secondary" href="{html.escape(install_link, quote=True)}">Zainstaluj w SideStore</a><a class="button secondary" href="releases/{name}" download>Pobierz IPA do Plików</a>'''
        instructions = '''<li>Połącz iPada z domowym Wi-Fi i włącz LocalDevVPN. Tailscale może pozostać wyłączony.</li><li>Dodaj źródło w SideStore i wybierz Recorder Probe. SideStore powinno pobrać IPA przez sieć domową.</li><li>Jeśli pobieranie z URL zawiedzie, pobierz IPA do Plików i wybierz je przez SideStore → My Apps → +.</li><li>Przed końcem 7 dni odśwież podpis w SideStore przy włączonym LocalDevVPN.</li>'''
        network_note = "To źródło działa tylko w domowym Wi-Fi. Lokalny HTTP służy wyłącznie do dystrybucji niepodpisanego prototypu; zgodność z SideStore wymaga testu na iPadzie."
    else:
        buttons = f'''<a class="button" href="releases/{name}" download>Pobierz IPA do Plików</a><a class="button secondary" href="{html.escape(source_link, quote=True)}">Dodaj źródło w SideStore</a><a class="button secondary" href="{html.escape(install_link, quote=True)}">Otwórz IPA w SideStore</a>'''
        instructions = '''<li>Włącz Tailscale i pobierz IPA z tej strony. Zachowaj plik w aplikacji Pliki.</li><li>Przełącz z Tailscale na LocalDevVPN, pozostaw Wi-Fi włączone.</li><li>W SideStore otwórz My Apps → + i wybierz pobrany IPA z Plików. SideStore podpisze go i zainstaluje.</li><li>Przed końcem 7 dni odśwież podpis w SideStore przy włączonym LocalDevVPN.</li>'''
        network_note = "Na tym iPadzie Tailscale i LocalDevVPN nie działają jednocześnie, więc przyciski źródła i instalacji z URL mogą nie pobrać pliku w SideStore."
    page = f'''<!doctype html>
<html lang="pl"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark"><title>Recorder Probe · wydania</title>
<style>
:root {{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color-scheme:light dark}}
* {{box-sizing:border-box}} body {{margin:0;background:#f3f5fa;color:#17233c}} main {{max-width:760px;margin:auto;padding:40px 24px 80px}}
.top {{display:flex;align-items:center;gap:20px}} .icon {{width:76px;height:76px;border-radius:18px}}
h1 {{font-size:clamp(2rem,5vw,3rem);letter-spacing:-.04em;margin:.15em 0}} .eyebrow {{color:#4d5f83;font-weight:650;font-size:.8rem;letter-spacing:.1em;text-transform:uppercase}}
.lead {{font-size:1.2rem;line-height:1.5;color:#405171}} .card {{background:white;border:1px solid #e0e5ee;border-radius:22px;padding:24px;margin-top:20px;box-shadow:0 8px 30px #17233c0a}}
h2 {{margin:0 0 14px;font-size:1.25rem}} p,li {{line-height:1.6}} .meta {{color:#536482}} .actions {{display:flex;flex-wrap:wrap;gap:10px;margin-top:20px}}
a.button {{display:inline-block;padding:13px 18px;border-radius:12px;background:#315aa8;color:white;text-decoration:none;font-weight:650;min-height:44px}}
a.secondary {{background:#e8edf7;color:#244887}} a {{color:#244f9e}} code {{word-break:break-all;font-size:.85em}} .note {{font-size:.94rem;color:#536482}}
@media(prefers-color-scheme:dark) {{body {{background:#101522;color:#ecf0fa}} .lead,.meta,.note {{color:#b0bfdb}} .card {{background:#1a2233;border-color:#32405b;box-shadow:none}} a {{color:#a7c5ff}} a.secondary {{background:#2b3c5a;color:#c8dcff}} .eyebrow {{color:#b0bfdb}}}}
</style></head><body><main>
<div class="top"><img class="icon" src="icon.png" alt=""><div><div class="eyebrow">Prywatna dystrybucja</div><h1>Recorder Probe</h1></div></div>
<p class="lead">Prototyp testowy nagrywania dźwięku na iPadzie. Wydania są dostępne przez Twoją prywatną sieć.</p>
<section class="card"><h2>Aktualne wydanie</h2><p class="meta">Wersja {html.escape(version)} · build {html.escape(build)} · iPadOS 27 lub nowszy · {ipa.stat().st_size / 1024:.0f} KB</p>
<div class="actions">{buttons}</div>
<p class="note">SHA-256: <code>{digest}</code> · <a href="releases/{name}.sha256">plik sumy</a></p></section>
<section class="card"><h2>Instalacja</h2><ol>{instructions}</ol>
<p class="note">{network_note} Malina nie podpisuje aplikacji. <a href="https://github.com/AdasRakieta/audio-recorder/blob/main/docs/TEST_NA_IPADZIE.md">Dokładna instrukcja i plan testów</a>.</p></section>
<section class="card"><h2>Stan prototypu</h2><p>Instalacja przez SideStore została wykonana. Nadal trzeba sprawdzić odnowienie podpisu oraz zapis głosu drugiego uczestnika podczas zwykłego spotkania Teams. Test połączenia z autosekretarką dał ciszę także we wbudowanym nagrywaniu ekranu iPada.</p></section>
</main></body></html>'''
    atomic_write(output / "index.html", page.encode())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--base-url", required=True)
    args = parser.parse_args()
    publish(args.ipa, args.output, args.base_url)
