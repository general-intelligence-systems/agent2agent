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
COPY examples/basic/Gemfile examples/basic/config.ru examples/basic/falcon.rb ./examples/basic/

WORKDIR /app/examples/basic

RUN bundle install --jobs 4

EXPOSE 9292

CMD ["bundle", "exec", "falcon", "host"]
