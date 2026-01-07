FROM elixir:1.16-otp-26-slim AS builder

WORKDIR /app

RUN apt-get update && \
    apt-get install -y --no-install-recommends git build-essential && \
    rm -rf /var/lib/apt/lists/*

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix local.hex --force && \
    mix local.rebar --force && \
    mix deps.get --only prod && \
    mix deps.compile

COPY config config
COPY lib lib

RUN mix compile && \
    mix release

FROM debian:bookworm-slim AS runner

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libstdc++6 \
        libncurses6 \
        openssl \
        ca-certificates \
        locales && \
    rm -rf /var/lib/apt/lists/* && \
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && \
    locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /app

RUN groupadd -g 1000 malachimq && \
    useradd -u 1000 -g malachimq -s /bin/bash -m malachimq

COPY --from=builder --chown=malachimq:malachimq /app/_build/prod/rel/malachimq ./

USER malachimq

ENV MALACHIMQ_TCP_PORT=4040
ENV MALACHIMQ_DASHBOARD_PORT=4041
ENV MALACHIMQ_LOCALE=en_US

EXPOSE 4040 4041

CMD ["bin/malachimq", "start"]
