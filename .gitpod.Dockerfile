FROM hexpm/elixir:1.11.3-erlang-23.2.5-ubuntu-xenial-20201014

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force
