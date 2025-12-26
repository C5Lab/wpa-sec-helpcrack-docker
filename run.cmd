@echo off
setlocal

if "%~1"=="" (
  docker compose run --rm wpa-sec -co="--backend-ignore-opencl"
) else (
  docker compose run --rm wpa-sec -co="--backend-ignore-opencl" %*
)
