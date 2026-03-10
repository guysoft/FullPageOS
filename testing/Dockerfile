FROM ptrsr/pi-ci:latest

ENV LIBGUESTFS_BACKEND=direct

RUN apt-get update && apt-get install -y --no-install-recommends \
    sshpass openssh-client curl socat imagemagick \
    && rm -rf /var/lib/apt/lists/*

# Shared framework from CustomPiOS (copied into build context by CI)
COPY custompios/scripts/ /test/scripts/
COPY custompios/tests/ /test/tests/

# FullPageOS-specific tests and hooks
COPY tests/ /test/tests/
COPY hooks/ /test/hooks/

RUN chmod +x /test/scripts/*.sh /test/tests/*.sh; \
    chmod +x /test/hooks/*.sh 2>/dev/null || true

ENTRYPOINT ["/test/scripts/entrypoint.sh"]
