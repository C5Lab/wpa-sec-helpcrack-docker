param(
  [string]$ArgsLine = ""
)

if ($ArgsLine -ne "") {
  docker compose run --rm wpa-sec -co="--backend-ignore-opencl" $ArgsLine
} else {
  docker compose run --rm wpa-sec -co="--backend-ignore-opencl"
}
