FROM ruby:3.4

RUN apt-get update && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy a2a gem source
COPY a2a.gemspec ./
COPY lib/ lib/
COPY data/ data/
COPY Gemfile ./Gemfile.gem

# Copy brute gem source (sibling directory)
COPY ../brute/brute.gemspec ./brute/
COPY ../brute/lib/ ./brute/lib/

# Copy example
COPY examples/multi-agent/ ./examples/multi-agent/

# Build arg to select which service to run
ARG SERVICE=greeter
ENV SERVICE=${SERVICE}

WORKDIR /app/examples/multi-agent/${SERVICE}

# Symlink to shared Gemfile
RUN ln -sf ../Gemfile Gemfile && bundle install --jobs 4

CMD ["bundle", "exec", "falcon", "host"]
