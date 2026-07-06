# agent2agent development guidelines

## Tests
`bin/test` runs the inline tests (scampi) embedded after `__END__` in each lib file. `bin/integration` runs the full protocol test against both bindings (requires Docker).

## Canonical Usage
The parent Rails project (repository root, two directories up) is the canonical downstream consumer: `config/routes.rb` mounts A2A agents in Rails routes, and `test/integration/a2a_client_test.rb` exercises `A2A::Client` over both bindings against a real async HTTP server. Keep docs and examples consistent with the usage patterns there.

## Running Examples
There are a plethora of examples in the ./examples directory. They are run with docker-compose... if you make changes to a running example such as changes to the examples, or the library code... then you must rebuild with `docker compose up -d --build` or sometimes `docker compose build --no-cache`.
