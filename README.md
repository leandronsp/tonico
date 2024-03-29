# tonico

Uma versão em Ruby puro utilizando async I/O da [rinha do backend 2ª edição](https://github.com/zanfranceschi/rinha-de-backend-2024-q1) 2024/Q1, sem frameworks.

Este projeto contempla o uso de syscall (select/epoll) e multitasking cooperativo com Fibers.

![Screenshot 2024-02-28 at 18 15 48](https://github.com/leandronsp/tonico/assets/385640/8d6ef2a3-232f-4f96-9190-bf91395f07aa)

## Requisitos

* [Docker](https://docs.docker.com/get-docker/)
* [Gatling](https://gatling.io/open-source/), a performance testing tool
* Make (optional)

## Stack

* 2 Ruby 3.3 [+YJIT](https://shopify.engineering/ruby-yjit-is-production-ready) apps
* 1 PostgreSQL
* 1 NGINX

## Usage

```bash
$ make help

Usage: make <target>
  help                       Prints available commands
  start.dev                  Start the rinha in Dev
  start.prod                 Start the rinha in Prod
  docker.stats               Show docker stats
  health.check               Check the stack is healthy
  stress.it                  Run stress tests
  docker.build               Build the docker image
  docker.push                Push the docker image
```

## Inicializando a aplicação

```bash
$ docker compose up -d nginx

# Ou então utilizando Make...
$ make start.dev
```

Testando a app:

```bash
$ curl -v http://localhost:9999/clientes/1/extrato

# Ou então utilizando Make...
$ make health.check
```

## Unleash the madness

Colocando Gatling no barulho:

```bash
$ make stress.it 
$ open stress-test/user-files/results/**/index.html
```

----

[ASCII art generator](http://www.network-science.de/ascii/)
