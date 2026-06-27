# ==============================================================================
# ZoomGate Docker Image
# Pure Elixir — no C++ SDK, no browser, ~80MB image
# ==============================================================================

# --- Stage 1: Build ----------------------------------------------------------
FROM hexpm/elixir:1.19.5-erlang-28.4.1-debian-trixie-20260223-slim AS builder

RUN apt-get update -y && \
    apt-get install -y build-essential git && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod

# Install hex + rebar
RUN mix local.hex --force && mix local.rebar --force

# Cache deps
COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && mix deps.compile

# Copy app source
COPY config config
COPY lib lib
COPY rel rel

# Compile and build release
RUN mix compile && mix release

# --- Stage 2: Runner ---------------------------------------------------------
FROM debian:trixie-20260223-slim AS runner

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

WORKDIR /app

# Non-root user
RUN useradd --system --create-home --shell /bin/bash zoomgate
USER zoomgate

# Copy Elixir release
COPY --from=builder --chown=zoomgate:zoomgate /app/_build/prod/rel/zoom_gate ./

# HTTP API
EXPOSE 4000
# EPMD + distributed Erlang ports (for BEAM cluster)
EXPOSE 4369
EXPOSE 9100-9200

ENV PHX_HOST=localhost \
    PORT=4000

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD curl -sf http://localhost:${PORT}/health || exit 1

CMD ["bin/zoom_gate", "start"]
