ARG CUSTOMPIOS_TAG=bugfix-e2e
FROM ghcr.io/guysoft/custompios:${CUSTOMPIOS_TAG} AS custompios

FROM ptrsr/pi-ci:latest

ENV LIBGUESTFS_BACKEND=direct

RUN apt-get update && apt-get install -y --no-install-recommends \
    sshpass openssh-client curl socat imagemagick \
    && rm -rf /var/lib/apt/lists/*

COPY --from=custompios /CustomPiOS/distro_testing/scripts/ /test/scripts/
COPY --from=custompios /CustomPiOS/distro_testing/tests/ /test/tests/

COPY tests/ /test/tests/
COPY hooks/ /test/hooks/

RUN chmod +x /test/scripts/*.sh /test/tests/*.sh; \
    chmod +x /test/hooks/*.sh 2>/dev/null || true

ENTRYPOINT ["/test/scripts/entrypoint.sh"]
