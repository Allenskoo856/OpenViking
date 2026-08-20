"""Automatically enable the OpenViking UOS Python egress guard."""

from network_policy import install_socket_guard

install_socket_guard()
