param(
  [string]$ArgsLine = ""
)

if ($ArgsLine -ne "") {
  docker compose run --rm --entrypoint /usr/local/bin/local_crack.sh wpa-sec $ArgsLine
} else {
  docker compose run --rm --entrypoint /usr/local/bin/local_crack.sh wpa-sec
}
