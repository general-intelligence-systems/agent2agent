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
COPY examples/async-jobs/Gemfile examples/async-jobs/config.ru examples/async-jobs/falcon.rb ./examples/async-jobs/

WORKDIR /app/examples/async-jobs

RUN bundle install --jobs 4

EXPOSE 9292

CMD ["bundle", "exec", "falcon", "host"]
