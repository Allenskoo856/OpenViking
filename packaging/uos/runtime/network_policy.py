#!/usr/bin/env python3
"""Fail-closed Python network policy used by the UOS offline image.

This module intentionally has no third-party dependencies.  It is imported by
``sitecustomize.py`` before OpenViking imports its provider SDKs.
"""

from __future__ import annotations

import ipaddress
import os
import socket
from typing import Iterable


MODE = os.environ.get("OPENVIKING_NETWORK_MODE", "intranet").strip().lower()
VALID_MODES = {"offline", "intranet", "online"}
if MODE not in VALID_MODES:
    raise RuntimeError(
        "OPENVIKING_NETWORK_MODE must be offline, intranet, or online; "
        f"got {MODE!r}"
    )


def _csv(name: str) -> list[str]:
    return [item.strip() for item in os.environ.get(name, "").split(",") if item.strip()]


ALLOWED_HOSTS = {host.rstrip(".").lower() for host in _csv("OPENVIKING_ALLOWED_HOSTS")}

_DEFAULT_NETWORKS = [
    "127.0.0.0/8",
    "::1/128",
]
if MODE == "intranet":
    _DEFAULT_NETWORKS.extend(
        [
            "10.0.0.0/8",
            "172.16.0.0/12",
            "192.168.0.0/16",
            "100.64.0.0/10",
            "169.254.0.0/16",
            "fc00::/7",
            "fe80::/10",
        ]
    )


def _load_networks(values: Iterable[str]) -> tuple[ipaddress._BaseNetwork, ...]:
    networks = []
    for value in values:
        try:
            networks.append(ipaddress.ip_network(value, strict=False))
        except ValueError as exc:
            raise RuntimeError(f"Invalid OPENVIKING_ALLOWED_CIDRS entry: {value!r}") from exc
    return tuple(networks)


ALLOWED_NETWORKS = _load_networks(_DEFAULT_NETWORKS + _csv("OPENVIKING_ALLOWED_CIDRS"))


def _normalize_host(host: object) -> str:
    if isinstance(host, bytes):
        host = host.decode("ascii", errors="strict")
    return str(host).strip().strip("[]").rstrip(".").lower()


def _as_ip(host: str):
    try:
        return ipaddress.ip_address(host.split("%", 1)[0])
    except ValueError:
        return None


def host_is_allowed(host: object) -> bool:
    """Return whether a hostname/IP may be resolved or connected to.

    In ``intranet`` mode, literal RFC1918/ULA/link-local addresses are allowed.
    Hostnames must be named explicitly, preventing a rejected public hostname
    from leaking through DNS before the policy decision is made.
    """

    if MODE == "online":
        return True
    normalized = _normalize_host(host)
    if not normalized:
        return False
    if normalized in {"localhost", "ip6-localhost"}:
        return True
    if normalized in ALLOWED_HOSTS:
        return True
    ip = _as_ip(normalized)
    return ip is not None and any(ip in network for network in ALLOWED_NETWORKS)


def require_allowed_host(host: object, operation: str = "connect") -> None:
    if host_is_allowed(host):
        return
    normalized = _normalize_host(host)
    raise PermissionError(
        f"OpenViking network policy blocked {operation} to {normalized!r} "
        f"(mode={MODE}). Add an audited hostname to OPENVIKING_ALLOWED_HOSTS "
        "or an audited network to OPENVIKING_ALLOWED_CIDRS."
    )


def describe_policy() -> str:
    hosts = ",".join(sorted(ALLOWED_HOSTS)) or "<none>"
    networks = ",".join(str(network) for network in ALLOWED_NETWORKS)
    return f"mode={MODE}; allowed_hosts={hosts}; allowed_cidrs={networks}"


_ORIGINAL_GETADDRINFO = socket.getaddrinfo
_ORIGINAL_CONNECT = socket.socket.connect
_ORIGINAL_CONNECT_EX = socket.socket.connect_ex
_ORIGINAL_CREATE_CONNECTION = socket.create_connection


def _guarded_getaddrinfo(host, *args, **kwargs):
    if host is not None:
        require_allowed_host(host, "DNS resolution")
    return _ORIGINAL_GETADDRINFO(host, *args, **kwargs)


def _address_host(address):
    if isinstance(address, tuple) and address:
        return address[0]
    return None


def _guarded_connect(sock, address):
    host = _address_host(address)
    if host is not None:
        require_allowed_host(host)
    return _ORIGINAL_CONNECT(sock, address)


def _guarded_connect_ex(sock, address):
    host = _address_host(address)
    if host is not None:
        require_allowed_host(host)
    return _ORIGINAL_CONNECT_EX(sock, address)


def _guarded_create_connection(address, *args, **kwargs):
    host = _address_host(address)
    if host is not None:
        require_allowed_host(host)
    # Use the original implementation. Its lookup ultimately calls the patched
    # getaddrinfo too, so both hostname and resolved-address paths are checked.
    return _ORIGINAL_CREATE_CONNECTION(address, *args, **kwargs)


def install_socket_guard() -> None:
    if MODE == "online":
        return
    socket.getaddrinfo = _guarded_getaddrinfo
    socket.socket.connect = _guarded_connect
    socket.socket.connect_ex = _guarded_connect_ex
    socket.create_connection = _guarded_create_connection
