ARG BASE_IMAGE=ghcr.io/volcengine/openviking:v0.4.15@sha256:d51ab7167d52c3e9eb0decac1fe21cf9abf709ac49ee8bab097c2947ba74c9a7
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.title="OpenViking UOS intranet runtime" \
      org.opencontainers.image.description="Pinned OpenViking runtime with fail-closed intranet policy" \
      org.opencontainers.image.licenses="AGPL-3.0"

COPY packaging/uos/runtime/ /opt/openviking-uos/
RUN chmod 0555 /opt/openviking-uos/openviking-uos-entrypoint.sh \
        /opt/openviking-uos/validate_config.py \
        /opt/openviking-uos/git \
 && mkdir -p /opt/openviking-uos/bin \
 && ln -s ../git /opt/openviking-uos/bin/git

ENV PYTHONPATH="/opt/openviking-uos" \
    PATH="/opt/openviking-uos/bin:${PATH}" \
    OPENVIKING_NETWORK_MODE="intranet" \
    OPENVIKING_ALLOWED_HOSTS="" \
    OPENVIKING_ALLOWED_CIDRS="" \
    OPENVIKING_WITH_BOT="0"

ENTRYPOINT ["/opt/openviking-uos/openviking-uos-entrypoint.sh"]
