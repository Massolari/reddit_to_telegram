FROM alpine:edge
RUN apk add --no-cache -X http://dl-cdn.alpinelinux.org/alpine/edge/testing \
    build-base erlang gleam rebar3 sqlite
RUN mkdir /app
COPY src /app/src
COPY gleam.toml /app/gleam.toml
COPY manifest.toml /app/manifest.toml
WORKDIR /app
RUN gleam build
ENTRYPOINT ["gleam"]
CMD ["run"]
EXPOSE 8000
