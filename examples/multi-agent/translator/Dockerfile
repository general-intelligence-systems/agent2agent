FROM ruby:3.4

WORKDIR /app

COPY Gemfile ./
RUN bundle install --jobs 4

COPY . .

CMD ["bundle", "exec", "falcon", "host"]
