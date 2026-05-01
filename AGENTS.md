# agent2agent development guidelines

## Running Examples
There are a plethora of exmaples in the ./examples directory. They are run with docker-compose... if you make changes a running example such as changes to the examples, or the library code... then you must rebuild with `docker compose up -d --build` or sometimes `docker compose build --no-cache`.
