FROM ruby:3.4

WORKDIR /app

COPY Gemfile ./
RUN bundle install --jobs 4

COPY . .

EXPOSE 9292

CMD ["bundle", "exec", "falcon", "host"]
