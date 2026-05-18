FROM ruby:3.4

WORKDIR /app

# Copy the gem source first (for path dependency)
COPY . /app/gem/

# Copy integration test files
COPY test/integration/Gemfile test/integration/config.ru test/integration/falcon.rb test/integration/agent_card.yml /app/

RUN bundle install --jobs 4

EXPOSE 9292

CMD ["bundle", "exec", "falcon", "host"]
