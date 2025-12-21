FROM elixir:1.16-otp-26-alpine AS builder

WORKDIR /app

RUN apk add --no-cache git build-base

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

FROM alpine:3.19 AS runner

RUN apk add --no-cache libstdc++ ncurses-libs openssl

WORKDIR /app

RUN addgroup -g 1000 malachimq && \
    adduser -u 1000 -G malachimq -s /bin/sh -D malachimq

COPY --from=builder --chown=malachimq:malachimq /app/_build/prod/rel/malachimq ./

USER malachimq

ENV MALACHIMQ_TCP_PORT=4040
ENV MALACHIMQ_DASHBOARD_PORT=4041
ENV MALACHIMQ_LOCALE=en_US

EXPOSE 4040 4041

CMD ["bin/malachimq", "start"]
