#!/usr/bin/env python3
"""Static, fail-closed validation for an intranet OpenViking ov.conf."""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from urllib.parse import urlsplit

from network_policy import MODE, describe_policy, require_allowed_host


URL_RE = re.compile(r"^[a-z][a-z0-9+.-]*://", re.IGNORECASE)
PLACEHOLDERS = ("change-me", "your-", "<", "${")


def _walk(value, path=""):
    if isinstance(value, dict):
        for key, child in value.items():
            child_path = f"{path}.{key}" if path else str(key)
            yield from _walk(child, child_path)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from _walk(child, f"{path}[{index}]")
    else:
        yield path, value


def _load(path: Path):
    raw = os.path.expandvars(path.read_text(encoding="utf-8-sig"))
    unresolved = sorted(set(re.findall(r"\$\{?[A-Za-z_][A-Za-z0-9_]*\}?", raw)))
    if unresolved:
        raise ValueError("unresolved environment variables: " + ", ".join(unresolved))
    return json.loads(raw)


def _model_endpoint_errors(config):
    errors = []
    sections = [("embedding.dense", ((config.get("embedding") or {}).get("dense") or {}))]
    sections.extend(
        (name, config.get(name) or {}) for name in ("vlm", "query_planner") if config.get(name)
    )
    for name, section in sections:
        provider = str(section.get("provider") or "").strip().lower()
        if provider == "openai-codex":
            errors.append(f"{name}.provider=openai-codex is not allowed in intranet/offline mode")
        if provider and provider != "local" and not section.get("api_base"):
            errors.append(f"{name}.api_base must be explicit in intranet/offline mode")
        for index, credential in enumerate(section.get("credentials") or []):
            if credential.get("provider") == "openai-codex":
                errors.append(f"{name}.credentials[{index}] uses blocked openai-codex provider")
            if not credential.get("api_base") and not section.get("api_base"):
                errors.append(f"{name}.credentials[{index}] needs an explicit api_base")
    rerank = config.get("rerank") or {}
    rerank_configured = any(
        rerank.get(key) for key in ("provider", "api_key", "ak", "sk", "model")
    )
    if rerank_configured and not (rerank.get("api_base") or rerank.get("host")):
        errors.append(
            "rerank must declare an explicit intranet api_base or host; provider defaults are blocked"
        )
    return errors


def validate(config):
    errors = []
    if MODE == "online":
        return errors

    for path, value in _walk(config):
        if not isinstance(value, str) or not value.strip():
            continue
        if URL_RE.match(value):
            parsed = urlsplit(value)
            if parsed.scheme not in {"http", "https", "redis", "rediss"}:
                errors.append(f"{path}: unsupported URL scheme {parsed.scheme!r}")
                continue
            endpoint_host = parsed.hostname
        elif path.rsplit(".", 1)[-1] in {"api_base", "base_url", "endpoint", "host"}:
            # Some upstream SDKs accept a bare host[:port]. Listener addresses
            # are not destinations, so only the server host is excluded.
            if path == "server.host":
                continue
            endpoint_host = value.rsplit("@", 1)[-1].split(":", 1)[0].strip("[]")
        else:
            continue
        if endpoint_host:
            try:
                require_allowed_host(endpoint_host, f"configuration field {path}")
            except PermissionError as exc:
                errors.append(str(exc))

    errors.extend(_model_endpoint_errors(config))

    telemetry = ((config.get("telemetry") or {}).get("tracer") or {})
    if telemetry.get("enabled") is True:
        errors.append("telemetry.tracer.enabled must be false")
    if (config.get("connector") or {}).get("enable") is True:
        errors.append("connector.enable must be false")
    if (config.get("parser_api") or {}).get("enable") is True:
        errors.append("parser_api.enable must be false")
    if config.get("enable_watch_scheduler", False) is not False:
        errors.append("enable_watch_scheduler must be false for the intranet baseline")

    server = config.get("server") or {}
    if server.get("auth_mode") != "api_key":
        errors.append("server.auth_mode must be api_key")
    if "*" in (server.get("cors_origins") or []):
        errors.append("server.cors_origins must not contain '*'")
    root_key = str(server.get("root_api_key") or "")
    if not root_key or any(token in root_key.lower() for token in PLACEHOLDERS):
        errors.append("server.root_api_key must be set to a non-placeholder secret")
    return errors


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("config", type=Path)
    args = parser.parse_args(argv)
    try:
        config = _load(args.config)
        errors = validate(config)
    except Exception as exc:
        print(f"[uos-policy] configuration validation failed: {exc}", file=sys.stderr)
        return 2
    if errors:
        for error in errors:
            print(f"[uos-policy] ERROR: {error}", file=sys.stderr)
        return 2
    print(f"[uos-policy] configuration accepted ({describe_policy()})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
