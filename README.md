# Docker Compose Buildkite Plugin ![Build status](https://badge.buildkite.com/d8fd3a4fef8419a6a3ebea79739a09ebc91106538193f99fce.svg)

__This is designed to run with the upcoming version of 3.0 of Buildkite Agent (currently in beta). Plugins are not yet supported in version 2.1. See the [Containerized Builds with Docker](https://buildkite.com/docs/guides/docker-containerized-builds) guide for running builds in Docker with the current stable version of the Buildkite Agent.__

A [Buildkite](https://buildkite.com/) plugin allowing you to create a build system capable of running any project or tool with a [Docker Compose](https://docs.docker.com/compose/) config file in its repository.

* Containers are built, run and linked on demand using Docker Compose
* Containers are namespaced to each build job, and cleaned up after use
* Supports pre-building of images, allowing for fast parallel builds across distributed agents
* Supports pushing tagged images to a repository

## Example

The following pipeline will run `test.sh` inside a `app` service container using Docker Compose, the equivalent to running `docker-compose run app test.sh`:

```yml
steps:
  - command: test.sh
    plugins:
      docker-compose#v1.8.4:
        run: app
```

You can also specify a custom Docker Compose config file and what environment to pass
through if you need:

```yml
steps:
  - command: test.sh
    plugins:
      docker-compose#v1.8.4:
        run: app
        config: docker-compose.tests.yml
        env:
          - BUILDKITE_BUILD_NUMBER
```

or multiple config files:

```yml
steps:
  - command: test.sh
    plugins:
      docker-compose#v1.8.4:
        run: app
        config:
          - docker-compose.yml
          - docker-compose.test.yml
```

## Artifacts

If you’re generating artifacts in the build step, you’ll need to ensure your Docker Compose configuration volume mounts the host machine directory into the container where those artifacts are created.

For example, if you had the following step:

```yml
steps:
  - command: generate-dist.sh
    artifact_paths: "dist/*"
    plugins:
      docker-compose#v1.8.4:
        run: app
```

Assuming your application’s directory inside the container was `/app`, you would need to ensure your `app` service in your Docker Compose config has the following host volume mount:

```yml
volumes:
  - "./dist:/app/dist"
```

## Environment

By default, docker-compose makes whatever environment variables it gets available for
interpolation of docker-compose.yml, but it doesn't pass them in to your containers.

You can use the [environent key in docker-compose.yml](https://docs.docker.com/compose/environment-variables/) to either set specific environment vars or "pass through" environment
variables from outside docker-compose.

If you want to add extra environment above what is declared in your `docker-compose.yml`,
this plugin offers a `environment` block of it's own:

```yml
steps:
  - command: generate-dist.sh
    plugins:
      docker-compose#v1.8.4:
        run: app
        env:
          - BUILDKITE_BUILD_NUMBER
          - BUILDKITE_PULL_REQUEST
          - MY_CUSTOM_ENV=llamas
```

Note how the values in the list can either be just a key (so the value is sourced from the environment) or a KEY=VALUE pair.

## Pre-building the image

To speed up run parallel steps you can add a pre-building step to your pipeline, allowing all the `run` steps to skip image building:

```yml
steps:
  - name: ":docker: Build"
    plugins:
      docker-compose#v1.8.4:
        build: app

  - wait

  - name: ":docker: Test %n"
    command: test.sh
    parallelism: 25
    plugins:
      docker-compose#v1.8.4:
        run: app
```

If you’re running agents across multiple machines and Docker hosts you’ll want to push the pre-built image to a docker image repository using the `image-repository` option. The following example uses this option, along with dedicated builder and runner agent queues:

```yml
steps:
  - name: ":docker: Build"
    agents:
      queue: docker-builder
    plugins:
      docker-compose#v1.8.4:
        build: app
        image-repository: index.docker.io/org/repo

  - wait

  - name: ":docker: Test %n"
    command: test.sh
    parallelism: 25
    agents:
      queue: docker-runner
    plugins:
      docker-compose#v1.8.4:
        run: app
```

## Building multiple images

Sometimes your compose file has multiple services that need building. The example below will build images for the `app` and `tests` service and then the run step will pull them down and use them for the run as needed.

```yml
steps:
  - name: ":docker: Build"
    agents:
      queue: docker-builder
    plugins:
      docker-compose#v1.8.4:
        build:
          - app
          - tests
        image-repository: index.docker.io/org/repo

  - wait

  - name: ":docker: Test %n"
    command: test.sh
    parallelism: 25
    plugins:
      docker-compose#v1.8.4:
        run: tests
```

## Pushing Tagged Images

Prebuilt images are automatically pushed with a `build` step, but often you want to finally push your images, perhaps ready for deployment.

```yml
steps:
  - name: ":docker: Push to final repository"
    plugins:
      docker-compose#v1.8.4:
        push:
        - app:index.docker.io/org/repo/myapp
        - app:index.docker.io/org/repo/myapp:latest
```
## Reusing caches from images

A newly spawned agent won't contain any of the docker caches for the first run which will result in a long build step. To mitigate this you can reuse caches from a previously built image if it was pushed to the repo on a past run

```yaml
steps:
  - name: ":docker Build an image"
    plugins:
      docker-compose#v1.8.4:
        build: app
        image-repository: index.docker.io/org/repo
        cache-from: app:index.docker.io/org/repo/myapp:latest
  - name: ":docker: Push to final repository"
    plugins:
      docker-compose#v1.8.4:
        push:
        - app:index.docker.io/org/repo/myapp
        - app:index.docker.io/org/repo/myapp:latest
```

## Configuration

### `build`

The name of a service to build and store, allowing following pipeline steps to run faster as they won't need to build the image. The step’s `command` will be ignored and does not need to be specified.

Either a single service or multiple services can be provided as an array.

### `run`

The name of the service the command should be run within. If the docker-compose command would usually be `docker-compose run app test.sh` then the value would be `app`.

### `push`

A list of services to push in the format `service:image:tag`. If an image has been pre-built with the build step, that image will be re-tagged, otherwise docker-compose's built in push operation will be used.

### `config` (optional)

The file name of the Docker Compose configuration file to use. Can also be a list of filenames.

Default: `docker-compose.yml`

### `image-repository` (optional, build only)

The repository for pushing and pulling pre-built images, same as the repository location you would use for a `docker push`, for example `"index.docker.io/org/repo"`. Each image is tagged to the specific build so you can safely share the same image repository for any number of projects and builds.

The default is `""`  which only builds images on the local Docker host doing the build.

This option can also be configured on the agent machine using the environment variable `BUILDKITE_PLUGIN_DOCKER_COMPOSE_IMAGE_REPOSITORY`.

### `image-name` (optional, build only)

The name to use when tagging pre-built images.

The default is `${BUILDKITE_PIPELINE_SLUG}-${BUILDKITE_PLUGIN_DOCKER_COMPOSE_BUILD}-build-${BUILDKITE_BUILD_NUMBER}`, for example `my-project-web-build-42`.

Note: this option can only be specified on a `build` step.

### `env` or `environment` (optional, run only)

A list of either KEY or KEY=VALUE that are passed through as environment variables to the container.

### `pull-retries` (optional)

A number of times to retry failed docker pull. Defaults to 0.

This option can also be configured on the agent machine using the environment variable `BUILDKITE_PLUGIN_DOCKER_COMPOSE_PULL_RETRIES`.

### `push-retries` (optional)

A number of times to retry failed docker push. Defaults to 0.

This option can also be configured on the agent machine using the environment variable `BUILDKITE_PLUGIN_DOCKER_COMPOSE_PUSH_RETRIES`.

### `cache-from` (optional)

A list of images to pull caches from in the format `service:index.docker.io/org/repo/image:tag` before building. Requires docker-compose file version `3.2+`. Currently only one image per service is supported. If there's no image present for a service local docker cache will be used.

Note: this option can only be specified on a `build` step.

### `leave-volumes` (optional, run only)

Prevent the removal of volumes after the command has been run.

The default is `false`.

### `no-cache` (optional, build only)

Sets the build step to run with `--no-cache`, causing Docker Compose to not use any caches when building the image.

The default is `false`.

### `tty` (optional, run only)

If set to false, doesn't allocate a TTY. This is useful in some situations where TTY's aren't supported, for instance windows.

The default is `true`.

### `verbose` (optional)

Sets `docker-compose` to run with `--verbose`

The default is `false`.

## Developing

To run the tests:

```bash
docker-compose run --rm tests
```

## License

MIT (see [LICENSE](LICENSE))
