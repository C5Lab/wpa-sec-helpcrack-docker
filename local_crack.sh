#!/usr/bin/env bash
set -uo pipefail

PCAP_DIR="/local"
OUT_DIR="/local/hashes"
WORD_DIR="/work"
POTFILE="${PCAP_DIR}/potfile.txt"
RULE_DIR="${PCAP_DIR}/rules"
RESTORE_FILE="${PCAP_DIR}/hashcat.restore"
SUMMARY_FILE="${PCAP_DIR}/summary.txt"

mkdir -p "${OUT_DIR}"

shopt -s nullglob
pcaps=( "${PCAP_DIR}"/*.pcap "${PCAP_DIR}"/*.pcapng "${PCAP_DIR}"/*.cap )

use_color=0
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  use_color=1
fi

color() {
  if [ ${use_color} -eq 1 ]; then
    printf "\033[%sm%s\033[0m" "$1" "$2"
  else
    printf "%s" "$2"
  fi
}

info() {
  printf "%s\n" "$(color "36" "$1")"
}

ok() {
  printf "%s\n" "$(color "32" "$1")"
}

warn() {
  printf "%s\n" "$(color "33" "$1")"
}

if ! command -v hcxpcapngtool >/dev/null 2>&1; then
  warn "hcxpcapngtool not found in container."
  exit 1
fi

if [ ${#pcaps[@]} -eq 0 ]; then
  warn "No capture files found in ${PCAP_DIR} (pcap/pcapng/cap)."
  exit 1
fi

hashfiles=()
for p in "${pcaps[@]}"; do
  base="$(basename "${p}")"
  name="${base%.*}"
  out="${OUT_DIR}/${name}.22000"
  hcxpcapngtool -o "${out}" "${p}" >/dev/null
  if [ -s "${out}" ]; then
    hashfiles+=("${out}")
  else
    warn "No hashes extracted from ${base}."
  fi
done

if [ ${#hashfiles[@]} -eq 0 ]; then
  warn "No 22000 hashes were extracted."
  exit 1
fi

wordlists=( "${WORD_DIR}"/*.txt "${WORD_DIR}"/*.dict "${WORD_DIR}"/*.lst "${WORD_DIR}"/*.gz )
if [ ${#wordlists[@]} -eq 0 ]; then
  warn "No wordlists found in ${WORD_DIR}."
  exit 1
fi

estimate=0
estimate_fast=0
estimate_only=0
speed_khs=""
quiet=0
show_estimate=0
resume=0
status_timer=0
optimized=0
pass_args=()

args=( "$@" )
for ((i=0; i<${#args[@]}; i++)); do
  arg="${args[$i]}"
  case "${arg}" in
    --restore|--resume)
      resume=1
      ;;
    --estimate)
      estimate=1
      ;;
    --estimate-fast)
      estimate=1
      estimate_fast=1
      ;;
    --estimate-only)
      estimate=1
      estimate_only=1
      ;;
    --quiet)
      quiet=1
      ;;
    --status-timer)
      if [ $((i+1)) -lt ${#args[@]} ]; then
        status_timer="${args[$((i+1))]}"
        quiet=1
        i=$((i+1))
      fi
      ;;
    --optimized)
      optimized=1
      ;;
    --show-estimate)
      show_estimate=1
      ;;
    --speed-khs)
      if [ $((i+1)) -lt ${#args[@]} ]; then
        speed_khs="${args[$((i+1))]}"
        show_estimate=1
        i=$((i+1))
      fi
      ;;
    *)
      pass_args+=( "${arg}" )
      ;;
  esac
done

rules=()
if [ -d "${RULE_DIR}" ]; then
  for r in "${RULE_DIR}"/*.rule; do
    [ -e "${r}" ] || continue
    rules+=( -r "${r}" )
  done
fi

count_candidates() {
  python3 - "$1" "$2" <<'PY'
import gzip, os, sys
path = sys.argv[1]
fast = sys.argv[2] == "1"
sample = 20000

def avg_len_text(f):
    total = 0
    n = 0
    for _ in range(sample):
        line = f.readline()
        if not line:
            break
        total += len(line)
        n += 1
    return (total / n) if n else 0

if fast:
    if path.endswith(".gz"):
        with gzip.open(path, "rt", errors="ignore") as f:
            avg = avg_len_text(f)
        try:
            import subprocess
            out = subprocess.check_output(["gzip", "-l", path], text=True).splitlines()
            usize = int(out[-1].split()[1])
        except Exception:
            usize = os.path.getsize(path)
    else:
        with open(path, "r", errors="ignore") as f:
            avg = avg_len_text(f)
        usize = os.path.getsize(path)
    print(int(usize / avg) if avg > 0 else 0)
else:
    if path.endswith(".gz"):
        with gzip.open(path, "rt", errors="ignore") as f:
            c = sum(1 for _ in f)
    else:
        with open(path, "r", errors="ignore") as f:
            c = sum(1 for _ in f)
    print(c)
PY
}

format_seconds() {
  python3 - "$1" <<'PY'
import sys
sec = int(sys.argv[1])
mins, sec = divmod(sec, 60)
hrs, mins = divmod(mins, 60)
if hrs:
    print(f"{hrs}h {mins}m {sec}s")
elif mins:
    print(f"{mins}m {sec}s")
else:
    print(f"{sec}s")
PY
}

total_lists=${#wordlists[@]}
index=0
start_ts=$(date +%s)

if [ ${estimate} -eq 1 ]; then
  if [ ${estimate_fast} -eq 1 ]; then
    info "Estimating total candidates (fast sample, ignores rule expansion)..."
  else
    info "Estimating total candidates (full count, ignores rule expansion)..."
  fi
  total_candidates=0
  for wl in "${wordlists[@]}"; do
    count=$(count_candidates "${wl}" "${estimate_fast}")
    total_candidates=$((total_candidates + count))
  done
  ok "Total candidates: ${total_candidates}"
  if [ -n "${speed_khs}" ]; then
    info "Using provided speed: ${speed_khs} kH/s"
  else
    speed_khs=$(hashcat -b -m 22000 --backend-ignore-opencl 2>/dev/null | python3 - <<'PY' || true
import re, sys
for line in sys.stdin:
    if "Speed.#" in line:
        m = re.search(r"([0-9.]+)\\s*([kMG])?H/s", line)
        if m:
            val = float(m.group(1))
            unit = m.group(2) or ""
            if unit == "M":
                val *= 1000.0
            elif unit == "G":
                val *= 1000000.0
            print(val)
            sys.exit(0)
sys.exit(1)
PY
)
  fi
  if [ -n "${speed_khs}" ]; then
    est_seconds=$(python3 - <<PY
total = float("${total_candidates}")
speed = float("${speed_khs}") * 1000.0
print(int(total / speed) if speed > 0 else 0)
PY
)
    ok "Estimated time (no rules): ~${est_seconds}s at ${speed_khs} kH/s"
  else
    warn "Could not determine speed; rerun with --speed-khs <value> to estimate time."
  fi
  if [ ${estimate_only} -eq 1 ]; then
    exit 0
  fi
fi

if [ ${resume} -eq 1 ]; then
  if [ -f "${RESTORE_FILE}" ]; then
    info "Resuming hashcat session..."
    resume_start_ts=$(date +%s)
    if [ ${quiet} -eq 1 ]; then
      hashcat --restore --session local --restore-file-path "${RESTORE_FILE}" >/dev/null 2>&1
    else
      hashcat --restore --session local --restore-file-path "${RESTORE_FILE}"
    fi
    rc=$?
    resume_end_ts=$(date +%s)
    resume_elapsed=$((resume_end_ts - resume_start_ts))
    if [ ${rc} -ge 3 ]; then
      warn "Resume failed with code ${rc}. Stopping."
      exit ${rc}
    fi
    ok "Resume completed in $(format_seconds "${resume_elapsed}")"
  else
    warn "No restore file found at ${RESTORE_FILE}. Starting fresh."
  fi
fi

for wl in "${wordlists[@]}"; do
  index=$((index + 1))
  info "[${index}/${total_lists}] Wordlist: $(basename "${wl}")"
  wl_start_ts=$(date +%s)
  if [ ${show_estimate} -eq 1 ]; then
    count=$(count_candidates "${wl}" "${estimate_fast}")
    rule_mult=$(( ${#rules[@]} / 2 ))
    if [ ${rule_mult} -gt 0 ]; then
      total_for_list=$((count * rule_mult))
    else
      total_for_list=${count}
    fi
    if [ -n "${speed_khs}" ] && [ ${total_for_list} -gt 0 ]; then
      est_seconds=$(python3 - <<PY
total = float("${total_for_list}")
speed = float("${speed_khs}") * 1000.0
print(int(total / speed) if speed > 0 else 0)
PY
)
      info "  Candidates: ${total_for_list} (rules x${rule_mult:-0})"
      info "  Est time: $(format_seconds "${est_seconds}")"
    else
      info "  Candidates: ${total_for_list} (rules x${rule_mult:-0})"
    fi
  fi
  if [ ${quiet} -eq 1 ]; then
    if [ ${status_timer} -gt 0 ]; then
      hashcat "${pass_args[@]}" $( [ ${optimized} -eq 1 ] && printf "%s" "-O" ) --status --status-timer "${status_timer}" \
        -m 22000 --backend-ignore-opencl -w 3 --potfile-path "${POTFILE}" \
        --session local --restore-file-path "${RESTORE_FILE}" \
        "${rules[@]}" "${hashfiles[@]}" "${wl}"
    else
      hashcat "${pass_args[@]}" $( [ ${optimized} -eq 1 ] && printf "%s" "-O" ) --quiet -m 22000 --backend-ignore-opencl -w 3 --potfile-path "${POTFILE}" \
        --session local --restore-file-path "${RESTORE_FILE}" \
        "${rules[@]}" "${hashfiles[@]}" "${wl}" >/dev/null 2>&1
    fi
  else
    hashcat "${pass_args[@]}" $( [ ${optimized} -eq 1 ] && printf "%s" "-O" ) -m 22000 --backend-ignore-opencl -w 3 --potfile-path "${POTFILE}" \
      --session local --restore-file-path "${RESTORE_FILE}" \
      "${rules[@]}" "${hashfiles[@]}" "${wl}"
  fi
  rc=$?
  if [ ${rc} -ge 3 ]; then
    warn "hashcat exited with code ${rc}. Stopping."
    exit ${rc}
  fi
  wl_end_ts=$(date +%s)
  wl_elapsed=$((wl_end_ts - wl_start_ts))
  total_elapsed=$((wl_end_ts - start_ts))
  ok "Completed [${index}/${total_lists}] in $(format_seconds "${wl_elapsed}") (total: $(format_seconds "${total_elapsed}"))"
done

end_ts=$(date +%s)
elapsed=$((end_ts - start_ts))
rule_count=$(( ${#rules[@]} / 2 ))

{
  echo "Summary"
  echo "  Hash files: ${#hashfiles[@]}"
  echo "  Wordlists: ${total_lists}"
  echo "  Rules: ${rule_count}"
  echo "  Potfile: ${POTFILE}"
  echo "  Restore: ${RESTORE_FILE}"
  echo "  Elapsed: ${elapsed}s"
  if [ ${estimate} -eq 1 ]; then
    echo "  Candidates (estimate): ${total_candidates}"
  fi
  if [ -f "${POTFILE}" ]; then
    found=$(hashcat --show --potfile-path "${POTFILE}" "${hashfiles[@]}" 2>/dev/null | wc -l || true)
    echo "  Recovered lines: ${found}"
  else
    echo "  Recovered lines: 0"
  fi
} | tee "${SUMMARY_FILE}"
