#!/bin/bash

set -e

export ERLANG_VERSION="18.2"
export ELIXIR_VERSION="1.3.2"

export ERLANG_EXTRA_CONFIGURE_OPTIONS="--without-javac"

# Check for asdf
if ! asdf | grep version; then
  # Install asdf into ~/.asdf if not previously installed
  git clone https://github.com/asdf-vm/asdf.git ~/.asdf --branch v0.1.0
fi

# Install or update erlang plugin
if ! asdf plugin-list | grep erlang; then
  asdf plugin-add erlang https://github.com/asdf-vm/asdf-erlang.git
else
  asdf plugin-update erlang
fi

# Install or update elixir plugin
if ! asdf plugin-list | grep elixir; then
  asdf plugin-add elixir https://github.com/asdf-vm/asdf-elixir.git
else
  asdf plugin-update elixir
fi

# Write .tool-versions for asdf
echo "erlang $ERLANG_VERSION" >> .tool-versions
echo "elixir $ELIXIR_VERSION" >> .tool-versions

# Install everything
asdf install

# Get dependencies
yes | mix local.hex
yes | mix local.rebar

# Fetch and compile dependencies and application code (and include testing tools)
mix do deps.get, deps.compile, compile
