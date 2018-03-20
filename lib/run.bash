#!/bin/bash

compose_cleanup() {
  if [[ "$(plugin_read_config LOG_ALL 'false')" == "true" ]]; then
    mkdir -p docker-compose-log-all

    for container_name in $(docker_ps_by_project --format '{{.Names}}'); do
      docker logs -t "$container_name" > "docker-compose-log-all/${container_name}.log"
    done

    buildkite-agent artifact upload "docker-compose-log-all/*.log"
  fi

  # Send them a friendly kill
  run_docker_compose kill || true

  # `compose down` doesn't support force removing images
  if [[ "$(plugin_read_config LEAVE_VOLUMES 'false')" == "false" ]]; then
    run_docker_compose rm --force -v || true
  else
    run_docker_compose rm --force || true
  fi

  # Stop and remove all the linked services and network
  if [[ "$(plugin_read_config LEAVE_VOLUMES 'false')" == "false" ]]; then
    run_docker_compose down --volumes || true
  else
    run_docker_compose down || true
  fi
}

# Checks for failed containers and writes logs for them the the provided dir
check_linked_containers_and_save_logs() {
  local logdir="$1"
  local cmdexit="$2"

  mkdir -p "$logdir"

  for container_name in $(docker_ps_by_project --format '{{.ID}}'); do
    container_exit_code=$(docker inspect --format='{{.State.ExitCode}}' "$container_name")

    if [[ $container_exit_code -ne 0 ]] ; then
      echo "+++ :warning: Linked container $container_name exited with $container_exit_code"
    fi

    # Capture logs if the linked container failed OR if the main command failed
    if [[ $container_exit_code -ne 0 ]] || [[ $cmdexit -ne 0 ]] ; then
      plugin_prompt_and_run docker logs --timestamps --tail 500 "$container_name"
      docker logs -t "$container_name" > "${logdir}/${container_name}.log"
    fi
  done
}
