@echo off
setlocal

if "%~1"=="" (
  docker compose run --rm --entrypoint /usr/local/bin/local_crack.sh wpa-sec
) else (
  docker compose run --rm --entrypoint /usr/local/bin/local_crack.sh wpa-sec %*
)
