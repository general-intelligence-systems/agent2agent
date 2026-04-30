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
COPY example/Gemfile example/config.ru ./example/

WORKDIR /app/example

RUN bundle install --jobs 4

EXPOSE 9292

CMD ["bundle", "exec", "falcon", "serve", "--bind", "http://0.0.0.0:9292"]
