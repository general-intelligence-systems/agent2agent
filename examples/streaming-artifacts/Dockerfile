FROM ruby:3.4

RUN apt-get update && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy gem source (changes less often = better layer caching)
COPY a2a.gemspec ./
COPY lib/ lib/
COPY data/ data/
COPY Gemfile ./Gemfile.gem

# Copy example
COPY examples/streaming-artifacts/Gemfile examples/streaming-artifacts/config.ru examples/streaming-artifacts/falcon.rb ./examples/streaming-artifacts/

WORKDIR /app/examples/streaming-artifacts

RUN bundle install --jobs 4

EXPOSE 9292

CMD ["bundle", "exec", "falcon", "host"]
