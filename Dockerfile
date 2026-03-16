# ==============================================================================
# ZoomGate Docker Image — Multi-stage build
# Target: Linux x86_64 (Zoom SDK requirement)
# ==============================================================================

# --- Stage 1: Elixir build ---------------------------------------------------
FROM hexpm/elixir:1.18.3-erlang-27.3-debian-bookworm-20250224-slim AS builder

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

# --- Stage 2: C++ SDK build (placeholder) ------------------------------------
# Uncomment when native/zoom_worker is ready:
#
# FROM debian:bookworm-slim AS sdk-builder
# RUN apt-get update -y && \
#     apt-get install -y cmake g++ && \
#     apt-get clean && rm -rf /var/lib/apt/lists/*
# WORKDIR /build
# COPY native/ ./
# RUN mkdir -p build && cd build && cmake .. && make

# --- Stage 3: Runner ----------------------------------------------------------
FROM debian:bookworm-slim AS runner

RUN apt-get update -y && \
    apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8

WORKDIR /app

# Create non-root user
RUN useradd --system --create-home --shell /bin/bash zoomgate
USER zoomgate

# Copy Elixir release
COPY --from=builder --chown=zoomgate:zoomgate /app/_build/prod/rel/zoom_gate ./

# Copy C++ worker binary + SDK shared libraries (when ready):
# COPY --from=sdk-builder --chown=zoomgate:zoomgate /build/build/zoom_worker /app/bin/zoom_worker
# COPY --from=sdk-builder --chown=zoomgate:zoomgate /build/zoom-meeting-sdk/lib/ /app/lib/zoom_sdk/
# ENV LD_LIBRARY_PATH=/app/lib/zoom_sdk:$LD_LIBRARY_PATH

EXPOSE 4000

# EPMD + distributed Erlang ports
EXPOSE 4369
EXPOSE 9100-9200

ENV PHX_HOST=localhost \
    PORT=4000

CMD ["bin/zoom_gate", "start"]
