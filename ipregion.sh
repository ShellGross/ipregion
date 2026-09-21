#!/bin/bash
# ipregion-berkut
# Fork of Davoyan/ipregion (upstream vernette/ipregion)
# Node-oriented IP region checker.
set -o pipefail
if locale -a 2>/dev/null | grep -qiE '^(C\.UTF-8|en_US.utf8|C.utf8)$'; then
  export LC_ALL="$(locale -a 2>/dev/null | grep -iE '^(C\.UTF-8|C.utf8)$' | head -n1)"
  [[ -z "$LC_ALL" ]] && export LC_ALL=C.UTF-8
else
  export LC_ALL=C
fi
export LANG="${LC_ALL}"
NO_COLOR="${NO_COLOR:-}"
FORCE_COLOR="${FORCE_COLOR:-1}"

SCRIPT_NAME="ipregion-berkut"
SCRIPT_SRC="fork of Davoyan/ipregion"
USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"
SPOTIFY_API_KEY="142b583129b2df829de3656f9eb484e6"
SPOTIFY_CLIENT_ID="9a8d2f0ce77a4e248bb71fefcb557637"

VERBOSE=false
JSON_OUTPUT=false
HTML_OUTPUT=false
GROUPS_TO_SHOW="all"
CURL_TIMEOUT=6
CURL_RETRIES=1
IPV4_ONLY=false
IPV6_ONLY=false
PROXY_ADDR=""
PROXY_DNS="remote"
INTERFACE_NAME=""
EXPECT_CC=""
SHOW_FULL_IP=false
MAX_JOBS=8

IPV4_SUPPORTED=1
IPV6_SUPPORTED=1
EXTERNAL_IPV4=""
EXTERNAL_IPV6=""
ASN=""
ASN_NAME=""
PTR=""
RDAP_ORG=""
RDAP_CC=""
CF_LOC=""
CF_COLO=""
CF_WARP=""
CITY_IPINFO=""
CITY_MAXMIND=""
CITY_2IP=""
CITY_SYPEX=""
FLAG_HOSTING="no"
FLAG_VPN="no"
FLAG_PROXY="no"
FLAG_ANYCAST="no"
FLAG_MOBILE="no"
CONSENSUS_CC=""
CONSENSUS_PCT=0
EXIT_STATUS=0

WORKDIR=""
SPINNER_PID=""
SPINNER_RUNNING=false

declare -A COUNTRY_NAMES=(
  [AD]="Andorra" [AE]="UAE" [AL]="Albania" [AM]="Armenia"
  [AR]="Argentina" [AT]="Austria" [AU]="Australia" [AZ]="Azerbaijan"
  [BA]="Bosnia" [BD]="Bangladesh" [BE]="Belgium" [BG]="Bulgaria"
  [BH]="Bahrain" [BR]="Brazil" [BY]="Belarus" [CA]="Canada"
  [CH]="Switzerland" [CL]="Chile" [CN]="China" [CO]="Colombia"
  [CY]="Cyprus" [CZ]="Czechia" [DE]="Germany" [DK]="Denmark"
  [EE]="Estonia" [EG]="Egypt" [ES]="Spain" [EU]="EU"
  [FI]="Finland" [FR]="France" [GB]="UK" [GE]="Georgia"
  [GR]="Greece" [HK]="Hong Kong" [HR]="Croatia" [HU]="Hungary"
  [ID]="Indonesia" [IE]="Ireland" [IL]="Israel" [IN]="India"
  [IQ]="Iraq" [IR]="Iran" [IS]="Iceland" [IT]="Italy"
  [JP]="Japan" [KG]="Kyrgyzstan" [KR]="Korea" [KZ]="Kazakhstan"
  [LT]="Lithuania" [LU]="Luxembourg" [LV]="Latvia" [MD]="Moldova"
  [MK]="N. Macedonia" [MX]="Mexico" [MY]="Malaysia" [NL]="Netherlands"
  [NO]="Norway" [NZ]="New Zealand" [PH]="Philippines" [PK]="Pakistan"
  [PL]="Poland" [PT]="Portugal" [QA]="Qatar" [RO]="Romania"
  [RS]="Serbia" [RU]="Russia" [SA]="Saudi Arabia" [SE]="Sweden"
  [SG]="Singapore" [SI]="Slovenia" [SK]="Slovakia" [TH]="Thailand"
  [TJ]="Tajikistan" [TM]="Turkmenistan" [TR]="Turkey" [TW]="Taiwan"
  [UA]="Ukraine" [US]="United States" [UZ]="Uzbekistan"
  [VN]="Vietnam" [WW]="Worldwide" [XK]="Kosovo" [ZA]="South Africa"
)

declare -A IATA_CC=(
  [AMS]=NL [RTM]=NL [EIN]=NL [FRA]=DE [MUC]=DE [TXL]=DE [BER]=DE
  [DUS]=DE [HAM]=DE [STR]=DE [LHR]=GB [LGW]=GB [MAN]=GB [EDI]=GB
  [CDG]=FR [ORY]=FR [MRS]=FR [IAD]=US [SJC]=US [LAX]=US
  [JFK]=US [EWR]=US [ORD]=US [DFW]=US [SEA]=US [ATL]=US [MIA]=US
  [DEN]=US [PHX]=US [BOS]=US [IAH]=US [MAD]=ES [BCN]=ES [MXP]=IT
  [FCO]=IT [ARN]=SE [GOT]=SE [HEL]=FI [WAW]=PL [KRK]=PL [PRG]=CZ
  [VIE]=AT [ZRH]=CH [GVA]=CH [BRU]=BE [DUB]=IE [LIS]=PT [BUD]=HU
  [OTP]=RO [SOF]=BG [IST]=TR [SAW]=TR [DXB]=AE [AUH]=AE [SIN]=SG
  [HKG]=HK [NRT]=JP [HND]=JP [KIX]=JP [ICN]=KR [SYD]=AU [MEL]=AU
  [GRU]=BR [SCL]=CL [BOM]=IN [DEL]=IN [LED]=RU [SVO]=RU [DME]=RU
  [VKO]=RU [RIX]=LV [TLL]=EE [KIV]=MD [ALA]=KZ [NQZ]=KZ [TAS]=UZ
  [EVN]=AM [TBS]=GE [MSQ]=BY [KBP]=UA [ODS]=UA [OSL]=NO [CPH]=DK
  [LUX]=LU [VNO]=LT [KUN]=LT [ATH]=GR [LCA]=CY [MLA]=MT [ZAG]=HR
  [BEG]=RS [TIA]=AL [SKP]=MK [TLV]=IL [CAI]=EG [JNB]=ZA [YYZ]=CA
  [YVR]=CA [MEX]=MX [BOG]=CO [LIM]=PE [EZE]=AR [GIG]=BR [AKL]=NZ
)

cc_name() {
  local cc="${1^^}"
  echo "${COUNTRY_NAMES[$cc]:-$cc}"
}

is_cc() {
  [[ "$1" =~ ^[A-Za-z]{2}$ ]]
}

norm_cc() {
  local v="$1"
  v="${v//$'\n'/}"
  v="${v//$'\r'/}"
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  v="${v^^}"
  if is_cc "$v"; then
    echo "$v"
  else
    echo ""
  fi
}

na_or() {
  local v="$1"
  if [[ -z "$v" || "$v" == "null" || "$v" == "N/A" ]]; then
    echo ""
  else
    echo "$v"
  fi
}

use_color() {
  [[ "$JSON_OUTPUT" == true || "$HTML_OUTPUT" == true ]] && return 1
  [[ -n "$NO_COLOR" ]] && return 1
  [[ "$FORCE_COLOR" == "0" ]] && return 1
  return 0
}

color() {
  local n="$1" t="$2"
  if ! use_color; then
    printf "%s" "$t"
    return
  fi
  local c="0"
  case "$n" in
    CYAN) c="1;36" ;;
    GRN) c="0;32" ;;
    BGRN) c="1;32" ;;
    YEL) c="1;33" ;;
    RED) c="1;31" ;;
    DIM) c="0;90" ;;
    WHT) c="1;97" ;;
    BLU) c="1;34" ;;
    MAG) c="1;35" ;;
    INV) c="1;37;44" ;;
  esac
  printf "\033[%sm%s\033[0m" "$c" "$t"
}

hr() {
  color DIM "--------------------------------"
}

section_title() {
  printf "\n%s\n" "$(color CYAN "[ $1 ]")"
}

die() {
  printf "%s %s\n" "$(color RED ERROR)" "$1" >&2
  exit "${2:-2}"
}

log() {
  [[ "$VERBOSE" == true ]] || return 0
  printf "[%s] %s\n" "$(date +%H:%M:%S)" "$*" >&2
}

usage() {
  cat <<EOF
$SCRIPT_NAME - $SCRIPT_SRC

Usage: $0 [options]

  -h, --help
  -v, --verbose
  -j, --json
      --html              HTML tables + CSS
  -g, --group GROUP     primary|custom|cdn|ru|all
  -t, --timeout SEC     default $CURL_TIMEOUT
  -4, --ipv4
  -6, --ipv6
  -p, --proxy HOST:PORT SOCKS5
      --proxy-dns MODE  remote|local
  -i, --interface IF
  -e, --expect CC       expected country
      --full            show full IP
      --jobs N          parallel jobs (default $MAX_JOBS)
      --no-color        disable ANSI colors

Exit: 0 ok, 1 expect miss, 2 fatal
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help) usage; exit 0 ;;
      -v|--verbose) VERBOSE=true; shift ;;
      -j|--json) JSON_OUTPUT=true; shift ;;
      --html|--HTML|-html|html) HTML_OUTPUT=true; shift ;;
      -g|--group)
        GROUPS_TO_SHOW="$2"
        [[ "$GROUPS_TO_SHOW" =~ ^(primary|custom|cdn|ru|all)$ ]] || die "bad group: $2"
        shift 2 ;;
      -t|--timeout)
        [[ "$2" =~ ^[0-9]+$ ]] || die "bad timeout: $2"
        CURL_TIMEOUT="$2"; shift 2 ;;
      -4|--ipv4) IPV4_ONLY=true; shift ;;
      -6|--ipv6) IPV6_ONLY=true; shift ;;
      -p|--proxy) PROXY_ADDR="$2"; shift 2 ;;
      --proxy-dns)
        PROXY_DNS="$2"
        [[ "$PROXY_DNS" =~ ^(remote|local)$ ]] || die "proxy-dns: remote|local"
        shift 2 ;;
      -i|--interface) INTERFACE_NAME="$2"; shift 2 ;;
      -e|--expect)
        EXPECT_CC="$(norm_cc "$2")"
        [[ -n "$EXPECT_CC" ]] || die "bad expect: $2"
        shift 2 ;;
      --full) SHOW_FULL_IP=true; shift ;;
      --jobs)
        [[ "$2" =~ ^[0-9]+$ && "$2" -ge 1 ]] || die "bad jobs: $2"
        MAX_JOBS="$2"; shift 2 ;;
      --no-color) NO_COLOR=1; FORCE_COLOR=0; shift ;;
      *)
        die "unknown option: $1 (use --help). HTML: --html" ;;
    esac
  done
}

need_cmds() {
  command -v curl >/dev/null || die "need curl"
  command -v jq >/dev/null || die "need jq"
}

tmpdir_init() {
  local base="${TMPDIR:-/tmp}"
  [[ -d /data/data/com.termux/files/usr/tmp ]] && base="/data/data/com.termux/files/usr/tmp"
  WORKDIR="$(mktemp -d "$base/ipregion.XXXXXX")"
  trap 'cleanup' EXIT INT TERM
}

cleanup() {
  spinner_stop
  [[ -n "$WORKDIR" && -d "$WORKDIR" ]] && rm -rf "$WORKDIR"
}

mask_ip() {
  local ip="$1"
  if [[ "$SHOW_FULL_IP" == true ]]; then
    echo "$ip"
    return
  fi
  if [[ "$ip" == *:* ]]; then
    echo "$ip" | awk -F: '{
      for(i=1;i<=NF;i++) if($i=="") $i="0"
      printf "%s:%s:%s::\n", $1,$2,$3
    }'
  else
    echo "${ip%.*.*}.*.*"
  fi
}

curl_base() {
  local ipver="${1:-4}"
  local args=(
    --silent --compressed --show-error
    --retry "$CURL_RETRIES" --retry-connrefused
    --connect-timeout "$CURL_TIMEOUT"
    --max-time "$CURL_TIMEOUT"
    -A "$USER_AGENT"
    -w '\n%{http_code}'
  )
  if [[ "$ipver" == 6 ]]; then
    args+=(-6)
  else
    args+=(-4)
  fi
  if [[ -n "$PROXY_ADDR" ]]; then
    if [[ "$PROXY_DNS" == remote ]]; then
      args+=(--proxy "socks5h://$PROXY_ADDR")
    else
      args+=(--proxy "socks5://$PROXY_ADDR")
    fi
  fi
  [[ -n "$INTERFACE_NAME" ]] && args+=(--interface "$INTERFACE_NAME")
  printf '%s\0' "${args[@]}"
}

# stdout: body only. http code discarded unless needed by caller via file.
req() {
  local method="$1" url="$2" ipver="${3:-4}"
  shift 3
  local extra=() hdr=() json="" data=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --header) hdr+=(-H "$2"); shift 2 ;;
      --json) json="$2"; shift 2 ;;
      --data) data="$2"; shift 2 ;;
      *) extra+=("$1"); shift ;;
    esac
  done
  local args=()
  if [[ "$ipver" == 6 ]]; then args+=(-6); else args+=(-4); fi
  args+=(--silent --compressed
    --retry "$CURL_RETRIES" --retry-connrefused
    --connect-timeout "$CURL_TIMEOUT" --max-time "$CURL_TIMEOUT"
    -A "$USER_AGENT" -X "$method" -w '\n%{http_code}')
  if [[ -n "$PROXY_ADDR" ]]; then
    if [[ "$PROXY_DNS" == remote ]]; then
      args+=(--proxy "socks5h://$PROXY_ADDR")
    else
      args+=(--proxy "socks5://$PROXY_ADDR")
    fi
  fi
  [[ -n "$INTERFACE_NAME" ]] && args+=(--interface "$INTERFACE_NAME")
  args+=("${hdr[@]}")
  if [[ -n "$json" ]]; then
    args+=(-H "Content-Type: application/json" --data "$json")
  elif [[ -n "$data" ]]; then
    args+=(-H "Content-Type: application/x-www-form-urlencoded" --data "$data")
  fi
  args+=("$url")
  local raw status body
  raw="$(curl "${args[@]}" 2>/dev/null)" || true
  status="$(printf '%s' "$raw" | tail -n1)"
  body="$(printf '%s' "$raw" | sed '$d')"
  if [[ "$status" == 403 || "$status" == 429 || "$status" == 000 ]]; then
    echo ""
    return 0
  fi
  printf '%s' "$body"
}

req_code() {
  local method="$1" url="$2" ipver="${3:-4}"
  local args=()
  if [[ "$ipver" == 6 ]]; then args+=(-6); else args+=(-4); fi
  args+=(--silent --compressed --output /dev/null
    --connect-timeout "$CURL_TIMEOUT" --max-time "$CURL_TIMEOUT"
    -A "$USER_AGENT" -X "$method" -w '%{http_code}'
    --max-redirs 5 -L)
  if [[ -n "$PROXY_ADDR" ]]; then
    if [[ "$PROXY_DNS" == remote ]]; then
      args+=(--proxy "socks5h://$PROXY_ADDR")
    else
      args+=(--proxy "socks5://$PROXY_ADDR")
    fi
  fi
  [[ -n "$INTERFACE_NAME" ]] && args+=(--interface "$INTERFACE_NAME")
  args+=("$url")
  curl "${args[@]}" 2>/dev/null || echo "000"
}

jget() {
  local json="$1" filter="$2"
  [[ -n "$json" ]] || { echo ""; return; }
  jq -er "$filter" <<<"$json" 2>/dev/null | sed '/^null$/d' | head -n1
}

want_v4() {
  [[ "$IPV6_ONLY" != true && -n "$EXTERNAL_IPV4" ]]
}

want_v6() {
  [[ "$IPV4_ONLY" != true && "$IPV6_SUPPORTED" -eq 0 && -n "$EXTERNAL_IPV6" ]]
}

check_stack() {
  if ip -4 addr show scope global 2>/dev/null | grep -q inet; then
    IPV4_SUPPORTED=0
  else
    IPV4_SUPPORTED=1
  fi
  if ip -6 addr show scope global 2>/dev/null | grep -q inet6; then
    IPV6_SUPPORTED=0
  else
    IPV6_SUPPORTED=1
  fi
  if [[ "$IPV6_ONLY" == true && "$IPV6_SUPPORTED" -ne 0 ]]; then
    die "IPv6 not available"
  fi
}

fetch_one_id() {
  local host="$1" ver="$2"
  local ip
  ip="$(req GET "https://$host" "$ver" | tr -d '[:space:]')"
  if [[ "$ver" == 4 && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "$ip"
  elif [[ "$ver" == 6 && "$ip" == *:* ]]; then
    echo "$ip"
  fi
}

get_external_ip() {
  local hosts=("ident.me" "ifconfig.me" "api64.ipify.org" "icanhazip.com")
  local ip
  if [[ "$IPV6_ONLY" != true ]]; then
    for h in "${hosts[@]}"; do
      ip="$(fetch_one_id "$h" 4)"
      if [[ -n "$ip" ]]; then
        EXTERNAL_IPV4="$ip"
        log "IPv4 $h $ip"
        break
      fi
    done
  fi
  if [[ "$IPV4_ONLY" != true && "$IPV6_SUPPORTED" -eq 0 ]]; then
    for h in "${hosts[@]}"; do
      ip="$(fetch_one_id "$h" 6)"
      if [[ -n "$ip" ]]; then
        EXTERNAL_IPV6="$ip"
        log "IPv6 $h $ip"
        break
      fi
    done
  fi
  if [[ -z "$EXTERNAL_IPV4" && -z "$EXTERNAL_IPV6" ]]; then
    die "cannot detect external IP"
  fi
}

primary_ip() {
  if [[ -n "$EXTERNAL_IPV4" && "$IPV6_ONLY" != true ]]; then
    echo "$EXTERNAL_IPV4"
  else
    echo "$EXTERNAL_IPV6"
  fi
}

primary_ver() {
  if [[ -n "$EXTERNAL_IPV4" && "$IPV6_ONLY" != true ]]; then
    echo 4
  else
    echo 6
  fi
}

get_ptr() {
  local ip="$1"
  local out=""
  if command -v dig >/dev/null; then
    out="$(dig +short +time=2 +tries=1 -x "$ip" 2>/dev/null | head -n1)"
  elif command -v host >/dev/null; then
    out="$(host "$ip" 2>/dev/null | awk '/pointer/ {print $NF; exit}')"
  fi
  out="${out%.}"
  PTR="$out"
}

get_rdap() {
  local ip="$1" ver="$2" body
  body="$(req GET "https://rdap.org/ip/$ip" "$ver")"
  if [[ -z "$body" ]]; then
    body="$(req GET "https://rdap.db.ripe.net/ip/$ip" "$ver")"
  fi
  RDAP_CC="$(norm_cc "$(jget "$body" ".country")")"
  RDAP_ORG="$(jget "$body" '.name')"
  if [[ -z "$RDAP_ORG" ]]; then
    RDAP_ORG="$(jget "$body" '.entities[0].vcardArray[1][1][3]')"
  fi
}

get_asn_and_flags() {
  local ip ver body
  ip="$(primary_ip)"
  ver="$(primary_ver)"

  body="$(req GET "https://ipinfo.check.place/$ip" "$ver")"
  ASN="$(jget "$body" ".ASN.AutonomousSystemNumber")"
  ASN_NAME="$(jget "$body" ".ASN.AutonomousSystemOrganization")"
  if [[ -z "$ASN" || "$ASN" == "null" ]]; then
    body="$(req GET "https://geoip.oxl.app/api/ip/$ip" "$ver")"
    ASN="$(jget "$body" ".asn")"
    ASN_NAME="$(jget "$body" ".organization.name")"
  fi
  ASN="${ASN#AS}"

  # ipinfo widget: city + privacy
  body="$(req GET "https://ipinfo.io/widget/demo/$ip" "$ver" \
    --header "Referer: https://ipinfo.io" \
    --header "Origin: https://ipinfo.io")"
  CITY_IPINFO="$(jget "$body" '.data.city')"
  local region country
  region="$(jget "$body" '.data.region')"
  country="$(norm_cc "$(jget "$body" '.data.country')")"
  if [[ -n "$CITY_IPINFO" && -n "$region" ]]; then
    CITY_IPINFO="$CITY_IPINFO, $region"
  fi
  [[ -n "$country" ]] && CITY_IPINFO="${CITY_IPINFO:+$CITY_IPINFO }($country)"
  local priv
  priv="$(jget "$body" '.data.privacy.hosting')"
  [[ "$priv" == "true" ]] && FLAG_HOSTING=yes
  priv="$(jget "$body" '.data.privacy.vpn')"
  [[ "$priv" == "true" ]] && FLAG_VPN=yes
  priv="$(jget "$body" '.data.privacy.proxy')"
  [[ "$priv" == "true" ]] && FLAG_PROXY=yes
  priv="$(jget "$body" '.data.privacy.anycast')"
  [[ "$priv" == "true" ]] && FLAG_ANYCAST=yes

  body="$(req GET "https://api.ipapi.is/?q=$ip" "$ver")"
  [[ "$(jget "$body" '.is_datacenter')" == "true" ]] && FLAG_HOSTING=yes
  [[ "$(jget "$body" '.is_proxy')" == "true" ]] && FLAG_PROXY=yes
  [[ "$(jget "$body" '.is_vpn')" == "true" ]] && FLAG_VPN=yes
  [[ "$(jget "$body" '.is_crawler')" == "true" ]] && FLAG_PROXY=yes
  local ctype
  ctype="$(jget "$body" '.company.type // .asn.type')"
  case "$ctype" in
    hosting|business) FLAG_HOSTING=yes ;;
    isp) : ;;
  esac
  [[ "$(jget "$body" '.is_mobile')" == "true" ]] && FLAG_MOBILE=yes

  body="$(req GET "https://ipwho.is/$ip" "$ver")"
  [[ "$(jget "$body" '.type')" == "anycast" ]] && FLAG_ANYCAST=yes
  [[ "$(jget "$body" '.connection.domain')" == *mobile* ]] && FLAG_MOBILE=yes

  local org_l
  org_l="$(printf '%s' "$ASN_NAME" | tr '[:upper:]' '[:lower:]')"
  case "$org_l" in
    *cloud*|*host*|*vps*|*server*|*colo*|*ovh*|*hetzner*|*digitalocean*|*linode*|*m247*|*datacamp*|*leaseweb*|*choopa*|*vultr*|*gcore*|*aeza*|*timeweb*|*selectel*|*htz*)
      FLAG_HOSTING=yes ;;
    *vpn*|*mullvad*|*nordvpn*|*proton*)
      FLAG_VPN=yes ;;
  esac
}

# ---------- lookups ----------
save_row() {
  local group="$1" name="$2" v4="$3" v6="$4" seq="${5:-000}" out
  v4="$(printf '%s' "$v4" | tr '\n\t' '  ')"
  v6="$(printf '%s' "$v6" | tr '\n\t' '  ')"
  out="$WORKDIR/row.$seq"
  printf '%s\t%s\t%s\t%s\n' "$group" "$name" "$v4" "$v6" >"$out"
}

run_both() {
  local fn="$1"
  local v4="" v6=""
  if want_v4; then v4="$("$fn" 4)"; fi
  if want_v6; then v6="$("$fn" 6)"; fi
  printf '%s\t%s' "$v4" "$v6"
}

# GeoIP
lk_maxmind() {
  local ver="$1" ip body cc city
  if [[ "$ver" == 6 ]]; then ip="$EXTERNAL_IPV6"; else ip="$EXTERNAL_IPV4"; fi
  body="$(req GET "https://geoip.maxmind.com/geoip/v2.1/city/me" "$ver" \
    --header "Referer: https://www.maxmind.com")"
  cc="$(norm_cc "$(jget "$body" ".country.iso_code")")"
  city="$(jget "$body" '.city.names.en')"
  if [[ "$ver" == 4 && -n "$city" ]]; then
    CITY_MAXMIND="$city"
    local sub
    sub="$(jget "$body" '.subdivisions[0].names.en')"
    [[ -n "$sub" ]] && CITY_MAXMIND="$city, $sub"
  fi
  echo "$cc"
}

lk_ripe() {
  local ver="$1" ip
  if [[ "$ver" == 6 ]]; then ip="$EXTERNAL_IPV6"; else ip="$EXTERNAL_IPV4"; fi
  norm_cc "$(jget "$(req GET "https://rdap.db.ripe.net/ip/$ip" "$ver")" ".country")"
}

lk_ipinfo() {
  local ver="$1" ip
  if [[ "$ver" == 6 ]]; then ip="$EXTERNAL_IPV6"; else ip="$EXTERNAL_IPV4"; fi
  norm_cc "$(jget "$(req GET "https://ipinfo.io/widget/demo/$ip" "$ver")" ".data.country")"
}

lk_cloudflare() {
  local ver="$1" body
  body="$(req GET "https://www.cloudflare.com/cdn-cgi/trace" "$ver")"
  local loc colo warp
  loc="$(sed -n 's/^loc=//p' <<<"$body" | head -n1)"
  colo="$(sed -n 's/^colo=//p' <<<"$body" | head -n1)"
  warp="$(sed -n 's/^warp=//p' <<<"$body" | head -n1)"
  if [[ "$ver" == 4 || -z "$CF_LOC" ]]; then
    CF_LOC="$(norm_cc "$loc")"
    CF_COLO="${colo^^}"
    CF_WARP="$warp"
  fi
  norm_cc "$loc"
}

lk_ipregistry() {
  local ver="$1" ip
  if [[ "$ver" == 6 ]]; then ip="$EXTERNAL_IPV6"; else ip="$EXTERNAL_IPV4"; fi
  norm_cc "$(jget "$(req GET "https://api.ipregistry.co/$ip?hostname=true&key=sb69ksjcajfs4c" "$ver" \
    --header "Origin: https://ipregistry.co")" ".location.country.code")"
}

lk_ipapi_co() {
  local ver="$1" ip
  if [[ "$ver" == 6 ]]; then ip="$EXTERNAL_IPV6"; else ip="$EXTERNAL_IPV4"; fi
  norm_cc "$(jget "$(req GET "https://ipapi.co/$ip/json" "$ver")" ".country")"
}

lk_iplocation() {
  local ver="$1" ip
  if [[ "$ver" == 6 ]]; then ip="$EXTERNAL_IPV6"; else ip="$EXTERNAL_IPV4"; fi
  [[ -z "$ip" ]] && ip="$(primary_ip)"
  norm_cc "$(jget "$(req POST "https://iplocation.com" "$ver" --data "ip=$ip")" ".country_code")"
}

lk_country_is() {
  local ver="$1" ip
  if [[ "$ver" == 6 ]]; then ip="$EXTERNAL_IPV6"; else ip="$EXTERNAL_IPV4"; fi
  norm_cc "$(jget "$(req GET "https://api.country.is/$ip" "$ver")" ".country")"
}

lk_geoapify() {
  local ver="$1" ip
  if [[ "$ver" == 6 ]]; then ip="$EXTERNAL_IPV6"; else ip="$EXTERNAL_IPV4"; fi
  norm_cc "$(jget "$(req GET "https://api.geoapify.com/v1/ipinfo?&ip=$ip&apiKey=b8568cb9afc64fad861a69edbddb2658" "$ver")" ".country.iso_code")"
}

lk_geojs() {
  local ver="$1" ip
  if [[ "$ver" == 6 ]]; then ip="$EXTERNAL_IPV6"; else ip="$EXTERNAL_IPV4"; fi
  norm_cc "$(jget "$(req GET "https://get.geojs.io/v1/ip/country.json?ip=$ip" "$ver")" ".[0].country // .country")"
}

lk_ipapi_is() {
  local ver="$1" ip
  if [[ "$ver" == 6 ]]; then ip="$EXTERNAL_IPV6"; else ip="$EXTERNAL_IPV4"; fi
  norm_cc "$(jget "$(req GET "https://api.ipapi.is/?q=$ip" "$ver")" ".location.country_code")"
}

lk_ipbase() {
  local ver="$1" ip
  if [[ "$ver" == 6 ]]; then ip="$EXTERNAL_IPV6"; else ip="$EXTERNAL_IPV4"; fi
  norm_cc "$(jget "$(req GET "https://api.ipbase.com/v2/info?ip=$ip" "$ver")" ".data.location.country.alpha2")"
}

lk_ipquery() {
  local ver="$1" ip
  if [[ "$ver" == 6 ]]; then ip="$EXTERNAL_IPV6"; else ip="$EXTERNAL_IPV4"; fi
  norm_cc "$(jget "$(req GET "https://api.ipquery.io/$ip" "$ver")" ".location.country_code")"
}

lk_ipwho() {
  local ver="$1" ip
  if [[ "$ver" == 6 ]]; then ip="$EXTERNAL_IPV6"; else ip="$EXTERNAL_IPV4"; fi
  norm_cc "$(jget "$(req GET "https://ipwho.is/$ip" "$ver")" ".country_code")"
}

lk_ipapi_com() {
  local ver="$1" ip
  if [[ "$ver" == 6 ]]; then ip="$EXTERNAL_IPV6"; else ip="$EXTERNAL_IPV4"; fi
  norm_cc "$(jget "$(req GET "https://demo.ip-api.com/json/$ip?fields=countryCode" "$ver" \
    --header "Origin: https://ip-api.com")" ".countryCode")"
}

lk_2ipio() {
  local ver="$1" body cc city
  body="$(req GET "https://api.2ip.io" "$ver")"
  cc="$(norm_cc "$(jget "$body" ".code")")"
  city="$(jget "$body" ".city")"
  if [[ "$ver" == 4 && -n "$city" ]]; then
    CITY_2IP="$city"
  fi
  echo "$cc"
}

lk_2ipru() {
  local ver="$1" ip body
  if [[ "$ver" == 6 ]]; then ip="$EXTERNAL_IPV6"; else ip="$EXTERNAL_IPV4"; fi
  body="$(req GET "https://api.2ip.ua/geo.json?ip=$ip" "$ver")"
  [[ -z "$body" ]] && body="$(req GET "https://2ip.ru" "$ver")"
  local cc
  cc="$(norm_cc "$(jget "$body" ".country_code // .code")")"
  if [[ -z "$cc" ]]; then
    cc="$(sed -n 's/.*country_code":"\([A-Za-z][A-Za-z]\).*/\1/p' <<<"$body" | head -n1)"
    cc="$(norm_cc "$cc")"
  fi
  echo "$cc"
}

lk_sypex() {
  local ver="$1" ip body cc city
  if [[ "$ver" == 6 ]]; then ip="$EXTERNAL_IPV6"; else ip="$EXTERNAL_IPV4"; fi
  body="$(req GET "https://api.sypexgeo.net/json/$ip" "$ver")"
  cc="$(norm_cc "$(jget "$body" ".country.iso")")"
  city="$(jget "$body" ".city.name_en // .city.name_ru")"
  if [[ "$ver" == 4 && -n "$city" ]]; then
    CITY_SYPEX="$city"
  fi
  echo "$cc"
}

# Custom
lk_google() {
  local ver="$1" body cc
  body="$(req GET "https://www.google.com" "$ver")"
  cc="$(sed -n 's/.*"[a-z]\{2\}_\([A-Z]\{2\}\)".*/\1/p' <<<"$body" | head -n1)"
  [[ -z "$cc" ]] && cc="$(sed -n 's/.*"[a-z]\{2\}-\([A-Z]\{2\}\)".*/\1/p' <<<"$body" | tail -n1)"
  if [[ -z "$cc" ]]; then
    body="$(req GET "https://play.google.com/" "$ver")"
    local country
    country="$(grep -oE '<div class="yVZQTb">[^<(]+' <<<"$body" | head -n1 | sed 's/.*>//')"
    case "${country,,}" in
      netherlands) cc=NL ;; united\ states) cc=US ;; germany) cc=DE ;;
      france) cc=FR ;; united\ kingdom|uk) cc=GB ;; russia) cc=RU ;;
      finland) cc=FI ;; sweden) cc=SE ;; poland) cc=PL ;;
      *) cc="" ;;
    esac
  fi
  norm_cc "$cc"
}

lk_google_captcha() {
  local ver="$1" body
  body="$(req GET "https://www.google.com/search?q=cats" "$ver" \
    --header "Accept-Language: en-US,en;q=0.9")"
  [[ -z "$body" ]] && { echo ""; return; }
  if grep -qiE "unusual traffic from|is blocked|unaddressed abuse" <<<"$body"; then
    echo "Yes"
  else
    echo "No"
  fi
}

lk_youtube() {
  local ver="$1" body cc
  body="$(req GET "https://www.youtube.com" "$ver")"
  cc="$(grep -oE '"countryCode":"[A-Za-z]{2}"' <<<"$body" | head -n1 | cut -d'"' -f4)"
  norm_cc "$cc"
}

lk_yt_premium() {
  local ver="$1" body
  body="$(req GET "https://www.youtube.com/premium" "$ver" \
    --header "Cookie: SOCS=CAISNQgDEitib3FfaWRlbnRpdHlmcm9udGVuZHVpc2VydmVyXzIwMjUwNzMwLjA1X3AwGgJlbiACGgYIgPC_xAY" \
    --header "Accept-Language: en-US,en;q=0.9")"
  [[ -z "$body" ]] && { echo ""; return; }
  if grep -qi "youtube premium is not available in your country" <<<"$body"; then
    echo "No"
  else
    echo "Yes"
  fi
}

lk_yt_music() {
  local ver="$1" body
  body="$(req GET "https://music.youtube.com/" "$ver" \
    --header "Cookie: SOCS=CAISNQgDEitib3FfaWRlbnRpdHlmcm9udGVuZHVpc2VydmVyXzIwMjUwNzMwLjA1X3AwGgJlbiACGgYIgPC_xAY" \
    --header "Accept-Language: en-US,en;q=0.9")"
  [[ -z "$body" ]] && { echo ""; return; }
  if grep -qi "YouTube Music is not available in your area" <<<"$body"; then
    echo "No"
  else
    echo "Yes"
  fi
}

lk_twitch() {
  local ver="$1" body
  body="$(req POST "https://gql.twitch.tv/gql" "$ver" \
    --header "Client-Id: kimne78kx3ncx6brgo4mv6wki5h1ko" \
    --json '[{"operationName":"VerifyEmail_CurrentUser","variables":{},"extensions":{"persistedQuery":{"version":1,"sha256Hash":"f9e7dcdf7e99c314c82d8f7f725fab5f99d1df3d7359b53c9ae122deec590198"}}}]')"
  norm_cc "$(jget "$body" ".[0].data.requestInfo.countryCode")"
}

lk_chatgpt() {
  local ver="$1" body
  body="$(req POST "https://ab.chatgpt.com/v1/initialize" "$ver" \
    --header "Statsig-Api-Key: client-zUdXdSTygXJdzoE0sWTkP8GKTVsUMF2IRM7ShVO2JAG")"
  norm_cc "$(jget "$body" ".derived_fields.country")"
}

lk_netflix() {
  local ver="$1" body
  body="$(req GET "https://api.fast.com/netflix/speedtest/v2?https=true&token=YXNkZmFzZGxmbnNkYWZoYXNkZmhrYWxm&urlCount=1" "$ver")"
  norm_cc "$(jget "$body" ".client.location.country")"
}

lk_netflix_lib() {
  local ver="$1"
  local a b
  # 80018499 â widely licensed; 70143836 â US original probe
  a="$(req_code GET "https://www.netflix.com/title/80018499" "$ver")"
  b="$(req_code GET "https://www.netflix.com/title/70143836" "$ver")"
  if [[ "$a" == 404 && "$b" == 404 ]]; then
    echo "No"
  elif [[ "$b" == 200 || "$b" == 301 || "$b" == 302 ]]; then
    echo "Orig"
  elif [[ "$a" == 200 || "$a" == 301 || "$a" == 302 ]]; then
    echo "Proxy"
  else
    echo "No"
  fi
}

lk_spotify() {
  local ver="$1" body
  body="$(req GET "https://accounts.spotify.com/status" "$ver")"
  norm_cc "$(sed -n 's/.*"geoLocationCountryCode":"\([^"]*\)".*/\1/p' <<<"$body" | head -n1)"
}

lk_spotify_signup() {
  local ver="$1" body status launched
  body="$(req GET "https://spclient.wg.spotify.com/signup/public/v1/account/?validate=1&key=$SPOTIFY_API_KEY" "$ver" \
    --header "X-Client-Id: $SPOTIFY_CLIENT_ID")"
  status="$(jget "$body" ".status")"
  launched="$(jget "$body" ".is_country_launched")"
  if [[ "$status" == "120" || "$status" == "320" || "$launched" == "false" ]]; then
    echo "No"
  elif [[ -z "$body" ]]; then
    echo ""
  else
    echo "Yes"
  fi
}

lk_deezer() {
  local ver="$1" body
  body="$(req GET "https://www.deezer.com/en/offers" "$ver")"
  norm_cc "$(sed -n "s/.*'country': '\([^']*\)'.*/\1/p" <<<"$body" | head -n1)"
}

lk_reddit() {
  local ver="$1" body token
  body="$(req POST "https://www.reddit.com/auth/v2/oauth/access-token/loid" "$ver" \
    --header "Authorization: Basic b2hYcG9xclpZdWIxa2c6" \
    --json '{"scopes":["email"]}')"
  token="$(jget "$body" ".access_token")"
  [[ -z "$token" ]] && { echo ""; return; }
  body="$(req POST "https://gql-fed.reddit.com" "$ver" \
    --header "Authorization: Bearer $token" \
    --json '{"operationName":"UserLocation","variables":{},"extensions":{"persistedQuery":{"version":1,"sha256Hash":"f07de258c54537e24d7856080f662c1b1268210251e5789c8c08f20d76cc8ab2"}}}')"
  norm_cc "$(jget "$body" ".data.userLocation.countryCode")"
}

lk_reddit_guest() {
  local ver="$1" body
  body="$(req GET "https://www.reddit.com" "$ver")"
  if [[ -n "$body" ]]; then echo "Yes"; else echo "No"; fi
}

lk_prime() {
  local ver="$1" body region
  body="$(req GET "https://www.primevideo.com" "$ver")"
  if grep -qi 'isServiceRestricted' <<<"$body"; then
    echo "No"
    return
  fi
  region="$(grep -oE '"currentTerritory":"[A-Za-z0-9]+"' <<<"$body" | head -n1 | cut -d'"' -f4)"
  norm_cc "${region:0:2}"
}

lk_apple() {
  local ver="$1"
  norm_cc "$(req GET "https://gspe1-ssl.ls.apple.com/pep/gcc" "$ver")"
}

lk_steam() {
  local ver="$1" hdr
  hdr="$(req GET "https://store.steampowered.com" "$ver")"
  # cookies may be in body if we didn't keep headers; try both via extra HEAD
  local args=()
  if [[ "$ver" == 6 ]]; then args+=(-6); else args+=(-4); fi
  args+=(-sI --max-time "$CURL_TIMEOUT" -A "$USER_AGENT")
  if [[ -n "$PROXY_ADDR" ]]; then
    if [[ "$PROXY_DNS" == remote ]]; then
      args+=(--proxy "socks5h://$PROXY_ADDR")
    else
      args+=(--proxy "socks5://$PROXY_ADDR")
    fi
  fi
  hdr="$(curl "${args[@]}" "https://store.steampowered.com" 2>/dev/null)"
  norm_cc "$(grep -oP 'steamCountry=\K[A-Za-z]{2}' <<<"$hdr" | head -n1)"
}

lk_playstation() {
  local args=() hdr
  if [[ "$1" == 6 ]]; then args+=(-6); else args+=(-4); fi
  args+=(-sI --max-time "$CURL_TIMEOUT" -A "$USER_AGENT")
  if [[ -n "$PROXY_ADDR" ]]; then
    if [[ "$PROXY_DNS" == remote ]]; then
      args+=(--proxy "socks5h://$PROXY_ADDR")
    else
      args+=(--proxy "socks5://$PROXY_ADDR")
    fi
  fi
  hdr="$(curl "${args[@]}" "https://www.playstation.com" 2>/dev/null)"
  norm_cc "$(grep -i 'Set-Cookie: country=' <<<"$hdr" | head -n1 | sed 's/.*country=\([A-Za-z]*\).*/\1/')"
}

lk_tiktok() {
  local ver="$1" body
  body="$(req GET "https://www.tiktok.com/api/v1/web-cookie-privacy/config?appId=1988" "$ver")"
  norm_cc "$(jget "$body" ".body.appProps.region")"
}

lk_ookla() {
  local ver="$1" body
  body="$(req GET "https://www.speedtest.net/api/js/config-sdk" "$ver")"
  norm_cc "$(jget "$body" ".location.countryCode")"
}

lk_jetbrains() {
  local ver="$1" body
  body="$(req GET "https://data.services.jetbrains.com/geo" "$ver")"
  norm_cc "$(jget "$body" ".code")"
}

lk_bing() {
  local ver="$1" body region
  body="$(req GET "https://www.bing.com/search?q=cats" "$ver")"
  if grep -q 'cn.bing.com' <<<"$body"; then
    echo "CN"
    return
  fi
  region="$(grep -oP 'Region\s*:\s*"\K[^"]+' <<<"$body" | head -n1)"
  region="${region:0:2}"
  if [[ "${region^^}" == "WW" || -z "$region" ]]; then
    body="$(req GET "https://login.live.com" "$ver")"
    region="$(grep -oE '"sRequestCountry":"[A-Za-z]{2}"' <<<"$body" | head -n1 | cut -d'"' -f4)"
  fi
  norm_cc "$region"
}

lk_discord() {
  local ver="$1" hdr
  local args=()
  if [[ "$ver" == 6 ]]; then args+=(-6); else args+=(-4); fi
  args+=(-sI --max-time "$CURL_TIMEOUT" -A "$USER_AGENT")
  if [[ -n "$PROXY_ADDR" ]]; then
    if [[ "$PROXY_DNS" == remote ]]; then
      args+=(--proxy "socks5h://$PROXY_ADDR")
    else
      args+=(--proxy "socks5://$PROXY_ADDR")
    fi
  fi
  hdr="$(curl "${args[@]}" "https://discord.com" 2>/dev/null)"
  local cc
  cc="$(grep -i '^cf-ipcountry:' <<<"$hdr" | awk '{print $2}' | tr -d '\r')"
  norm_cc "$cc"
}

lk_telegram() {
  local ver="$1" body dc
  body="$(req GET "https://core.telegram.org/getProxyConfig" "$ver")"
  dc="$(grep -oE 'proxy_for [0-9]+' <<<"$body" | head -n1 | awk '{print $2}')"
  local args=() hdr cc
  if [[ "$ver" == 6 ]]; then args+=(-6); else args+=(-4); fi
  args+=(-sI --max-time "$CURL_TIMEOUT" -A "$USER_AGENT")
  if [[ -n "$PROXY_ADDR" ]]; then
    if [[ "$PROXY_DNS" == remote ]]; then
      args+=(--proxy "socks5h://$PROXY_ADDR")
    else
      args+=(--proxy "socks5://$PROXY_ADDR")
    fi
  fi
  hdr="$(curl "${args[@]}" "https://telegram.org" 2>/dev/null)"
  cc="$(grep -i '^cf-ipcountry:' <<<"$hdr" | awk '{print $2}' | tr -d '\r')"
  cc="$(norm_cc "$cc")"
  if [[ -n "$dc" && -n "$cc" ]]; then
    echo "DC$dc/$cc"
  elif [[ -n "$dc" ]]; then
    echo "DC$dc"
  else
    echo "$cc"
  fi
}

lk_whatsapp() {
  local ver="$1" hdr cc
  local args=()
  if [[ "$ver" == 6 ]]; then args+=(-6); else args+=(-4); fi
  args+=(-sI --max-time "$CURL_TIMEOUT" -A "$USER_AGENT")
  if [[ -n "$PROXY_ADDR" ]]; then
    if [[ "$PROXY_DNS" == remote ]]; then
      args+=(--proxy "socks5h://$PROXY_ADDR")
    else
      args+=(--proxy "socks5://$PROXY_ADDR")
    fi
  fi
  hdr="$(curl "${args[@]}" "https://web.whatsapp.com" 2>/dev/null)"
  cc="$(grep -i '^cf-ipcountry:' <<<"$hdr" | awk '{print $2}' | tr -d '\r')"
  norm_cc "$cc"
}

lk_yandex() {
  local ver="$1" body cc
  body="$(req GET "https://yandex.ru/tune/geo" "$ver")"
  cc="$(grep -oP 'country":"\K[A-Za-z]{2}' <<<"$body" | head -n1)"
  if [[ -z "$cc" ]]; then
    body="$(req GET "https://api.browser.yandex.ru/toolbar/configs/launch/?version=1" "$ver")"
    cc="$(jget "$body" ".region.country // .country")"
  fi
  if [[ -z "$cc" ]]; then
    local args=() hdr
    if [[ "$ver" == 6 ]]; then args+=(-6); else args+=(-4); fi
    args+=(-sI --max-time "$CURL_TIMEOUT" -A "$USER_AGENT")
    if [[ -n "$PROXY_ADDR" ]]; then
      if [[ "$PROXY_DNS" == remote ]]; then
        args+=(--proxy "socks5h://$PROXY_ADDR")
      else
        args+=(--proxy "socks5://$PROXY_ADDR")
      fi
    fi
    hdr="$(curl "${args[@]}" "https://ya.ru" 2>/dev/null)"
    cc="$(grep -iE 'x-yandex-region|x-region' <<<"$hdr" | head -n1)"
    # ya.ru often RU if reachable
    if grep -qi 'ya.ru' <<<"$hdr" && [[ -z "$cc" ]]; then
      # fallback: if export endpoint
      body="$(req GET "https://export.yandex.com/bar/reginfo.xml" "$ver")"
      cc="$(grep -oP 'id="[0-9]+"' <<<"$body" | head -n1)"
      [[ -n "$body" ]] && cc="${cc:-RU}"
    fi
  fi
  norm_cc "$cc"
}

lk_vk() {
  local ver="$1" body cc
  body="$(req GET "https://vk.com" "$ver")"
  cc="$(grep -oE '"countryCode":"[A-Za-z]{2}"' <<<"$body" | head -n1 | cut -d'"' -f4)"
  if [[ -z "$cc" ]]; then
    if grep -qiE 'login.vk.com|index_login' <<<"$body"; then
      cc="RU"
    fi
  fi
  # vk al_country cookie via HEAD
  if [[ -z "$cc" ]]; then
    local args=() hdr
    if [[ "$ver" == 6 ]]; then args+=(-6); else args+=(-4); fi
    args+=(-sI --max-time "$CURL_TIMEOUT" -A "$USER_AGENT")
    if [[ -n "$PROXY_ADDR" ]]; then
      if [[ "$PROXY_DNS" == remote ]]; then
        args+=(--proxy "socks5h://$PROXY_ADDR")
      else
        args+=(--proxy "socks5://$PROXY_ADDR")
      fi
    fi
    hdr="$(curl "${args[@]}" "https://vk.com" 2>/dev/null)"
    cc="$(grep -oP 'remixlang=[0-9]+' <<<"$hdr" | head -n1)"
    [[ -n "$hdr" && -z "$cc" ]] && cc="RU"
  fi
  norm_cc "$cc"
}

lk_kinopoisk() {
  local ver="$1" code
  code="$(req_code GET "https://www.kinopoisk.ru" "$ver")"
  case "$code" in
    200|301|302|303) echo "Yes" ;;
    403|451) echo "No" ;;
    *) echo "" ;;
  esac
}

lk_ivi() {
  local ver="$1" body
  body="$(req GET "https://www.ivi.ru" "$ver")"
  if [[ -z "$body" ]]; then echo ""; return; fi
  if grep -qiE "Ð½ÐµÐ´Ð¾ÑÑÑÐ¿ÐµÐ½|not available|restricted" <<<"$body"; then
    echo "No"
  else
    echo "Yes"
  fi
}

lk_yt_cdn() {
  local ver="$1" body iata cc
  body="$(req GET "https://redirector.googlevideo.com/report_mapping?di=no" "$ver")"
  iata="$(awk '{print $3}' <<<"$body" | head -n1 | cut -f2 -d'-' | cut -c1-3)"
  iata="${iata^^}"
  [[ -z "$iata" ]] && { echo ""; return; }
  cc="${IATA_CC[$iata]}"
  if [[ -n "$cc" ]]; then
    echo "$cc/$iata"
  else
    echo "$iata"
  fi
}

lk_nf_cdn() {
  local ver="$1" body
  body="$(req GET "https://api.fast.com/netflix/speedtest/v2?https=true&token=YXNkZmFzZGxmbnNkYWZoYXNkZmhrYWxm&urlCount=1" "$ver")"
  norm_cc "$(jget "$body" ".targets[0].location.country")"
}

# ---------- scheduler ----------
JOBS_PIDS=()
JOB_SEQ=0

wait_slot() {
  while (( $(jobs -rp 2>/dev/null | wc -l) >= MAX_JOBS )); do
    sleep 0.05
  done
}

job_wrap() {
  local group="$1" label="$2" fn="$3" seq="${4:-000}"
  local v4="" v6=""
  echo "$label" >"$WORKDIR/spin"
  if want_v4; then v4="$("$fn" 4 2>/dev/null || true)"; fi
  if want_v6; then v6="$("$fn" 6 2>/dev/null || true)"; fi
  save_row "$group" "$label" "$v4" "$v6" "$seq"
}

spawn() {
  wait_slot
  JOB_SEQ=$((JOB_SEQ + 1))
  local seq
  seq="$(printf '%03d' "$JOB_SEQ")"
  job_wrap "$1" "$2" "$3" "$seq" &
  JOBS_PIDS+=("$!")
}

wait_jobs() {
  local p
  for p in "${JOBS_PIDS[@]}"; do
    wait "$p" 2>/dev/null || true
  done
  JOBS_PIDS=()
}

spinner_start() {
  [[ "$JSON_OUTPUT" == true || "$HTML_OUTPUT" == true || "$VERBOSE" == true ]] && return
  [[ -t 1 ]] || return
  SPINNER_RUNNING=true
  (
    local s='|/-\\' i=0 cur
    while [[ -f "$WORKDIR/spin" || "$SPINNER_RUNNING" == true ]]; do
      cur=""
      [[ -f "$WORKDIR/spin" ]] && cur="$(cat "$WORKDIR/spin" 2>/dev/null)"
      printf "\r\033[K%s %s" "$(color CYAN "${s:i++%4:1}")" "$(color DIM "$cur")"
      sleep 0.08
    done
  ) &
  SPINNER_PID=$!
}

spinner_stop() {
  SPINNER_RUNNING=false
  if [[ -n "$SPINNER_PID" ]]; then
    kill "$SPINNER_PID" 2>/dev/null || true
    wait "$SPINNER_PID" 2>/dev/null || true
    SPINNER_PID=""
  fi
  [[ -t 1 ]] && printf "\r\033[K"
}

run_groups() {
  rm -f "$WORKDIR"/row.* "$WORKDIR/rows.tsv"
  : >"$WORKDIR/rows.tsv"
  local g="$GROUPS_TO_SHOW"

  if [[ "$g" == all || "$g" == custom ]]; then
    spawn custom "Google" lk_google
    spawn custom "G Captcha" lk_google_captcha
    spawn custom "YouTube" lk_youtube
    spawn custom "YT Premium" lk_yt_premium
    spawn custom "YT Music" lk_yt_music
    spawn custom "Twitch" lk_twitch
    spawn custom "ChatGPT" lk_chatgpt
    spawn custom "Netflix" lk_netflix
    spawn custom "NF library" lk_netflix_lib
    spawn custom "Spotify" lk_spotify
    spawn custom "Spotify SU" lk_spotify_signup
    spawn custom "Deezer" lk_deezer
    spawn custom "Reddit" lk_reddit
    spawn custom "Reddit guest" lk_reddit_guest
    spawn custom "Prime" lk_prime
    spawn custom "Apple" lk_apple
    spawn custom "Steam" lk_steam
    spawn custom "PlayStation" lk_playstation
    spawn custom "TikTok" lk_tiktok
    spawn custom "Speedtest" lk_ookla
    spawn custom "JetBrains" lk_jetbrains
    spawn custom "Bing" lk_bing
    spawn custom "Discord" lk_discord
    spawn custom "Telegram" lk_telegram
    spawn custom "WhatsApp" lk_whatsapp
  fi

  if [[ "$g" == all || "$g" == ru ]]; then
    spawn ru "Yandex" lk_yandex
    spawn ru "VK" lk_vk
    spawn ru "Kinopoisk" lk_kinopoisk
    spawn ru "IVI" lk_ivi
    spawn ru "2ip.ru" lk_2ipru
    spawn ru "Sypex" lk_sypex
  fi

  if [[ "$g" == all || "$g" == primary ]]; then
    spawn primary "maxmind" lk_maxmind
    spawn primary "rdap.ripe" lk_ripe
    spawn primary "ipinfo.io" lk_ipinfo
    spawn primary "cloudflare" lk_cloudflare
    spawn primary "ipregistry" lk_ipregistry
    spawn primary "ipapi.co" lk_ipapi_co
    spawn primary "iplocation" lk_iplocation
    spawn primary "country.is" lk_country_is
    spawn primary "geoapify" lk_geoapify
    spawn primary "geojs.io" lk_geojs
    spawn primary "ipapi.is" lk_ipapi_is
    spawn primary "ipbase" lk_ipbase
    spawn primary "ipquery.io" lk_ipquery
    spawn primary "ipwho.is" lk_ipwho
    spawn primary "ip-api.com" lk_ipapi_com
    spawn primary "2ip.io" lk_2ipio
  fi

  if [[ "$g" == all || "$g" == cdn ]]; then
    spawn cdn "YT CDN" lk_yt_cdn
    spawn cdn "NF CDN" lk_nf_cdn
    spawn cdn "CF trace" lk_cloudflare
  fi

  wait_jobs
  cat "$WORKDIR"/row.[0-9][0-9][0-9] 2>/dev/null >"$WORKDIR/rows.tsv" || true
}

# ---------- output ----------
compute_consensus() {
  local file="$WORKDIR/rows.tsv"
  [[ -s "$file" ]] || return
  local stats
  stats="$(awk -F '\t' '
    {
      for (i=3;i<=4;i++) {
        v=$i
        if (v=="" || v=="N/A" || v=="Yes" || v=="No" || v=="Orig" || v=="Proxy") next
        if (v ~ /^DC[0-9]+\//) { split(v,a,"/"); v=a[2] }
        if (v ~ /^[A-Z]{2}\//) { split(v,a,"/"); v=a[1] }
        if (v ~ /^[A-Z]{2}$/) c[v]++
      }
    }
    END {
      n=0; best=""; bestn=0
      for (k in c) { n+=c[k]; if (c[k]>bestn){bestn=c[k]; best=k} }
      if (n==0) { print ""; print 0; exit }
      printf "%s\n%d\n", best, int(bestn*100/n+0.5)
    }
  ' "$file")"
  CONSENSUS_CC="$(printf '%s' "$stats" | sed -n '1p')"
  CONSENSUS_PCT="$(printf '%s' "$stats" | sed -n '2p')"
  [[ -z "$CONSENSUS_PCT" ]] && CONSENSUS_PCT=0
}

legend_lines() {
  awk -F '\t' '
    {
      for (i=3;i<=4;i++) {
        v=$i
        if (v=="" || v=="N/A" || v=="Yes" || v=="No" || v=="Orig" || v=="Proxy") continue
        if (v ~ /^DC[0-9]+\//) { split(v,a,"/"); v=a[2] }
        if (v ~ /^[A-Z]{2}\//) { split(v,a,"/"); v=a[1] }
        if (v ~ /^[A-Z]{2}$/) c[v]++
      }
    }
    END {
      n=0
      for (k in c) n+=c[k]
      if (n==0) exit
      for (k in c) printf "%d\t%s\t%d\n", c[k], k, int(c[k]*100/n+0.5)
    }
  ' "$WORKDIR/rows.tsv" | sort -nr
}

print_kv() {
  local k="$1" v="$2" ck="${3:-CYAN}" cv="${4:-WHT}"
  [[ -z "$v" ]] && return
  printf " %s %-6s %s\n" "$(color DIM "|")" "$(color "$ck" "$k")" "$(color "$cv" "$v")"
}

val_base_cc() {
  local v="$1" base
  [[ -z "$v" || "$v" == "-" ]] && { echo ""; return; }
  if [[ "$v" == DC*/* ]]; then
    echo "${v##*/}"
    return
  fi
  base="${v%%/*}"
  if [[ "$base" =~ ^[A-Z]{2}$ ]]; then
    echo "$base"
  else
    echo ""
  fi
}

fmt_val() {
  local v="$1"
  [[ -z "$v" ]] && v="-"
  local base target
  base="$(val_base_cc "$v")"
  target="${EXPECT_CC:-$CONSENSUS_CC}"
  if [[ -n "$base" && -n "$target" && "$base" != "$target" ]]; then
    color YEL "$v"
    return
  fi
  case "$v" in
    Yes|Orig) color BGRN "$v" ;;
    No|Proxy) color YEL "$v" ;;
    -) color DIM "$v" ;;
    *)
      if [[ -n "$base" && "$base" == "$target" ]]; then
        color BGRN "$v"
      else
        color WHT "$v"
      fi
      ;;
  esac
}

print_section() {
  local title="$1" group="$2"
  awk -F '\t' -v g="$group" '$1==g{c++} END{exit !(c>0)}' "$WORKDIR/rows.tsv" || return
  section_title "$title"
  awk -F '\t' -v g="$group" '$1==g {print}' "$WORKDIR/rows.tsv" | while IFS=$'\t' read -r _ name v4 v6; do
    local val="$v4"
    want_v4 || val="$v6"
    if want_v4 && want_v6; then
      [[ -z "$v4" ]] && v4="-"
      [[ -z "$v6" ]] && v6="-"
      printf " %-13s %s\n" "$(color WHT "$name")" "$(fmt_val "$v4") $(color DIM "/") $(fmt_val "$v6")"
    else
      [[ -z "$val" ]] && val="-"
      printf " %-13s %s\n" "$(color WHT "$name")" "$(fmt_val "$val")"
    fi
  done
}

print_mismatch() {
  local target="${EXPECT_CC:-$CONSENSUS_CC}"
  [[ -n "$target" ]] || return
  local found=0
  local lines=""
  while IFS=$'\t' read -r grp name v4 v6; do
    local v="$v4"
    want_v4 || v="$v6"
    local base
    base="$(val_base_cc "$v")"
    if [[ -n "$base" && "$base" != "$target" ]]; then
      lines+="$(printf " %-13s %s" "$name" "$(color YEL "$v")")"$'\n'
      found=1
    fi
  done <"$WORKDIR/rows.tsv"
  [[ "$found" -eq 1 ]] || return
  section_title "DIFF vs ${target}"
  printf "%s" "$lines"
}

print_human() {
  local ip flags cf geo_line fl_col
  if want_v4; then
    ip="$(mask_ip "$EXTERNAL_IPV4")"
  else
    ip="$(mask_ip "$EXTERNAL_IPV6")"
  fi

  printf "%s\n" "$(color CYAN "$SCRIPT_NAME")"
  printf "%s\n" "$(color DIM "$SCRIPT_SRC")"
  printf "%s\n" "$(hr)"

  print_kv "IP" "$ip"
  if want_v4 && want_v6; then
    print_kv "IPv6" "$(mask_ip "$EXTERNAL_IPV6")"
  fi
  if [[ -n "$ASN" ]]; then
    print_kv "ASN" "AS${ASN}"
  fi
  if [[ -n "$ASN_NAME" ]]; then
    local org="$ASN_NAME"
    if [[ ${#org} -gt 22 ]]; then
      print_kv "org" "${org:0:22}"
      print_kv "" "${org:22}"
    else
      print_kv "org" "$org"
    fi
  fi
  print_kv "PTR" "$PTR"
  print_kv "RDAP" "${RDAP_ORG:+$RDAP_ORG }${RDAP_CC}"

  flags=""
  [[ "$FLAG_HOSTING" == yes ]] && flags+="hosting "
  [[ "$FLAG_VPN" == yes ]] && flags+="vpn "
  [[ "$FLAG_PROXY" == yes ]] && flags+="proxy "
  [[ "$FLAG_ANYCAST" == yes ]] && flags+="anycast "
  [[ "$FLAG_MOBILE" == yes ]] && flags+="mobile "
  flags="${flags%% }"
  fl_col=YEL
  if [[ -z "$flags" ]]; then
    flags="clear"
    fl_col=BGRN
  fi
  print_kv "flags" "$flags" CYAN "$fl_col"

  cf=""
  if [[ -n "$CF_LOC" || -n "$CF_COLO" ]]; then
    cf="${CF_LOC:-?}"
    [[ -n "$CF_COLO" ]] && cf="$cf colo=$CF_COLO"
    [[ -n "$CF_WARP" && "$CF_WARP" != "off" ]] && cf="$cf warp=$CF_WARP"
  fi
  print_kv "CF" "$cf"

  [[ -n "$CITY_IPINFO" ]] && print_kv "city" "$CITY_IPINFO"
  [[ -n "$CITY_MAXMIND" ]] && print_kv "mm" "$CITY_MAXMIND"
  [[ -n "$CITY_2IP" ]] && print_kv "2ip" "$CITY_2IP"
  [[ -n "$CITY_SYPEX" ]] && print_kv "sx" "$CITY_SYPEX"

  printf "%s\n" "$(hr)"
  if [[ -n "$CONSENSUS_CC" ]]; then
    geo_line="$CONSENSUS_CC  ${CONSENSUS_PCT}%  $(cc_name "$CONSENSUS_CC")"
    printf " %s %s\n" "$(color CYAN "GEO")" "$(color BGRN "$geo_line")"
  fi
  if [[ -n "$EXPECT_CC" ]]; then
    if [[ "$CONSENSUS_CC" == "$EXPECT_CC" ]]; then
      printf " %s %s\n" "$(color CYAN "EXP")" "$(color BGRN "$EXPECT_CC  OK")"
    else
      printf " %s %s\n" "$(color CYAN "EXP")" "$(color RED "$EXPECT_CC  FAIL  got ${CONSENSUS_CC:-?}")"
    fi
  fi
  printf "%s\n" "$(hr)"

  case "$GROUPS_TO_SHOW" in
    custom) print_section "SERVICES" custom ;;
    primary) print_section "GEOIP" primary ;;
    cdn) print_section "CDN" cdn ;;
    ru) print_section "RU" ru ;;
    *)
      print_section "SERVICES" custom
      print_section "RU" ru
      print_section "GEOIP" primary
      print_section "CDN" cdn
      ;;
  esac

  print_mismatch

  local leg
  leg="$(legend_lines)"
  if [[ -n "$leg" ]]; then
    section_title "LEGEND"
    while IFS=$'\t' read -r _ cc pct; do
      [[ -z "$cc" ]] && continue
      local mark=" "
      [[ "$cc" == "$CONSENSUS_CC" ]] && mark="*"
      printf " %s%-3s %-14s %s\n" "$(color DIM "$mark")" "$(color WHT "$cc")" "$(cc_name "$cc")" "$(color DIM "${pct}%")"
    done <<<"$leg"
  fi
  printf "\n%s\n" "$(color DIM "green = GEO, yellow = other")"
}

print_json() {
  local rows_json
  rows_json="$(awk -F '\t' '
    BEGIN{print "["}
    NF>=2 {
      if(n++) printf ","
      gsub(/\\/,"\\\\",$2); gsub(/"/,"\\\"",$2)
      printf "{\"group\":\"%s\",\"service\":\"%s\",\"ipv4\":%s,\"ipv6\":%s}",
        $1,$2,
        ($3==""?"null":"\"" $3 "\""),
        ($4==""?"null":"\"" $4 "\"")
    }
    END{print "]"}
  ' "$WORKDIR/rows.tsv")"

  local mismatch_json="[]"
  if [[ -n "$EXPECT_CC" ]]; then
    mismatch_json="$(awk -F '\t' -v exp="$EXPECT_CC" '
      BEGIN{print "["; n=0}
      {
        v=$3; if(v=="") v=$4
        base=v
        if (v ~ /^DC[0-9]+\//) { split(v,a,"/"); base=a[2] }
        else if (v ~ /^[A-Z]{2}\//) { split(v,a,"/"); base=a[1] }
        if (base ~ /^[A-Z]{2}$/ && base != exp) {
          if(n++) printf ","
          gsub(/"/,"\\\"",$2)
          printf "{\"service\":\"%s\",\"value\":\"%s\"}", $2, v
        }
      }
      END{print "]"}
    ' "$WORKDIR/rows.tsv")"
  fi

  jq -n \
    --arg version "2" \
    --arg ipv4 "$EXTERNAL_IPV4" \
    --arg ipv6 "$EXTERNAL_IPV6" \
    --arg asn "$ASN" \
    --arg org "$ASN_NAME" \
    --arg ptr "$PTR" \
    --arg rdap_org "$RDAP_ORG" \
    --arg rdap_cc "$RDAP_CC" \
    --arg hosting "$FLAG_HOSTING" \
    --arg vpn "$FLAG_VPN" \
    --arg proxy "$FLAG_PROXY" \
    --arg anycast "$FLAG_ANYCAST" \
    --arg mobile "$FLAG_MOBILE" \
    --arg city_ipinfo "$CITY_IPINFO" \
    --arg city_maxmind "$CITY_MAXMIND" \
    --arg city_2ip "$CITY_2IP" \
    --arg city_sypex "$CITY_SYPEX" \
    --arg cf_loc "$CF_LOC" \
    --arg cf_colo "$CF_COLO" \
    --arg cf_warp "$CF_WARP" \
    --arg consensus "$CONSENSUS_CC" \
    --argjson pct "${CONSENSUS_PCT:-0}" \
    --arg expect "$EXPECT_CC" \
    --argjson results "$rows_json" \
    --argjson mismatch "$mismatch_json" '
    {
      version: ($version|tonumber),
      ipv4: ($ipv4|select(length>0)//null),
      ipv6: ($ipv6|select(length>0)//null),
      asn: (if $asn=="" then null else ("AS"+$asn) end),
      org: ($org|select(length>0)//null),
      ptr: ($ptr|select(length>0)//null),
      rdap: {org: ($rdap_org|select(length>0)//null), country: ($rdap_cc|select(length>0)//null)},
      flags: {hosting:($hosting=="yes"), vpn:($vpn=="yes"), proxy:($proxy=="yes"), anycast:($anycast=="yes"), mobile:($mobile=="yes")},
      city: {ipinfo:($city_ipinfo|select(length>0)//null), maxmind:($city_maxmind|select(length>0)//null), "2ip":($city_2ip|select(length>0)//null), sypex:($city_sypex|select(length>0)//null)},
      cloudflare: {loc:($cf_loc|select(length>0)//null), colo:($cf_colo|select(length>0)//null), warp:($cf_warp|select(length>0)//null)},
      consensus: {country:($consensus|select(length>0)//null), percent:$pct},
      expect: ($expect|select(length>0)//null),
      mismatch: $mismatch,
      results: $results
    }'
}

html_esc() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g'
}

html_badge_class() {
  local v="$1" base target
  [[ -z "$v" || "$v" == "-" ]] && { echo "mute"; return; }
  case "$v" in
    Yes|Orig) echo "ok"; return ;;
    No|Proxy) echo "warn"; return ;;
  esac
  base="$(val_base_cc "$v")"
  target="${EXPECT_CC:-$CONSENSUS_CC}"
  if [[ -n "$base" && -n "$target" && "$base" != "$target" ]]; then
    echo "diff"
  elif [[ -n "$base" && "$base" == "$target" ]]; then
    echo "ok"
  else
    echo "val"
  fi
}

html_td() {
  local v="$1" cls
  [[ -z "$v" ]] && v="-"
  cls="$(html_badge_class "$v")"
  printf '<td><span class="b %s">%s</span></td>' "$cls" "$(html_esc "$v")"
}

html_table_group() {
  local title="$1" group="$2"
  awk -F '\t' -v g="$group" '$1==g{c++} END{exit !(c>0)}' "$WORKDIR/rows.tsv" || return
  local dual=0
  want_v4 && want_v6 && dual=1
  printf '<section><h2>%s</h2><div class="wrap"><table>' "$(html_esc "$title")"
  printf '<thead><tr><th>Service</th>'
  if [[ "$dual" -eq 1 ]]; then
    printf '<th>IPv4</th><th>IPv6</th>'
  else
    printf '<th>Result</th>'
  fi
  printf '</tr></thead><tbody>\n'
  awk -F '\t' -v g="$group" '$1==g {print}' "$WORKDIR/rows.tsv" | while IFS=$'\t' read -r _ name v4 v6; do
    printf '<tr><th>%s</th>' "$(html_esc "$name")"
    if [[ "$dual" -eq 1 ]]; then
      html_td "$v4"
      html_td "$v6"
    else
      if want_v4; then html_td "$v4"; else html_td "$v6"; fi
    fi
    printf '</tr>\n'
  done
  printf '</tbody></table></div></section>\n'
}

print_html() {
  local ip flags cf geo_cls exp_cls
  if want_v4; then ip="$(mask_ip "$EXTERNAL_IPV4")"; else ip="$(mask_ip "$EXTERNAL_IPV6")"; fi
  flags=""
  [[ "$FLAG_HOSTING" == yes ]] && flags+="hosting "
  [[ "$FLAG_VPN" == yes ]] && flags+="vpn "
  [[ "$FLAG_PROXY" == yes ]] && flags+="proxy "
  [[ "$FLAG_ANYCAST" == yes ]] && flags+="anycast "
  [[ "$FLAG_MOBILE" == yes ]] && flags+="mobile "
  flags="${flags%% }"
  [[ -z "$flags" ]] && flags="clear"
  cf=""
  if [[ -n "$CF_LOC" || -n "$CF_COLO" ]]; then
    cf="${CF_LOC:-?}"
    [[ -n "$CF_COLO" ]] && cf="$cf colo=$CF_COLO"
    [[ -n "$CF_WARP" && "$CF_WARP" != "off" ]] && cf="$cf warp=$CF_WARP"
  fi
  geo_cls="ok"
  exp_cls="ok"
  [[ -n "$EXPECT_CC" && "$CONSENSUS_CC" != "$EXPECT_CC" ]] && exp_cls="diff"

  cat <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${SCRIPT_NAME}</title>
<style>
:root{
  --bg:#0e1116;--card:#171c24;--line:#2a3340;--tx:#e8edf4;--dim:#8b97a8;
  --ok:#3dd68c;--okbg:#123526;--warn:#f5c84c;--warnbg:#3a3010;
  --diff:#ff8b6b;--diffbg:#3a1c16;--acc:#6ec3ff;
}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--tx);
  font:14px/1.4 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}
.page{max-width:640px;margin:0 auto;padding:16px}
h1{font-size:18px;margin:0 0 4px;color:var(--acc)}
.sub{color:var(--dim);font-size:12px;margin-bottom:16px}
h2{font-size:13px;letter-spacing:.08em;text-transform:uppercase;
  color:var(--dim);margin:20px 0 8px}
.cards{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.card{background:var(--card);border:1px solid var(--line);
  border-radius:10px;padding:10px 12px}
.card b{display:block;color:var(--dim);font-size:11px;
  font-weight:600;text-transform:uppercase;margin-bottom:4px}
.card span{word-break:break-word}
.geo{grid-column:1/-1;display:flex;align-items:center;gap:10px}
.geo .big{font-size:28px;font-weight:700;color:var(--ok)}
.wrap{overflow-x:auto;border:1px solid var(--line);border-radius:10px;
  background:var(--card)}
table{width:100%;border-collapse:collapse;min-width:280px}
th,td{padding:8px 10px;text-align:left;border-bottom:1px solid var(--line)}
thead th{font-size:11px;color:var(--dim);text-transform:uppercase;
  letter-spacing:.06em;background:#12171e}
tbody th{font-weight:600;width:42%}
tbody tr:last-child th,tbody tr:last-child td{border-bottom:0}
.b{display:inline-block;min-width:2.4em;padding:2px 8px;border-radius:999px;
  font-weight:700;font-size:12px}
.b.ok{background:var(--okbg);color:var(--ok)}
.b.warn{background:var(--warnbg);color:var(--warn)}
.b.diff{background:var(--diffbg);color:var(--diff)}
.b.val{background:#223044;color:var(--tx)}
.b.mute{background:#1b212a;color:var(--dim)}
.legend{display:flex;flex-wrap:wrap;gap:6px}
.chip{background:var(--card);border:1px solid var(--line);border-radius:999px;
  padding:4px 10px;font-size:12px}
.chip em{color:var(--dim);font-style:normal;margin-left:6px}
.foot{margin-top:18px;color:var(--dim);font-size:11px}
@media(max-width:420px){
  .cards{grid-template-columns:1fr}
  body{font-size:13px}
}
</style>
</head>
<body>
<div class="page">
<h1>$(html_esc "$SCRIPT_NAME")</h1>
<div class="sub">$(html_esc "$SCRIPT_SRC")</div>
<div class="cards">
<div class="card geo">
  <div>
    <b>GEO</b>
    <div class="big">$(html_esc "${CONSENSUS_CC:-?}")</div>
  </div>
  <div>
    <b>consensus</b>
    <span>$(html_esc "${CONSENSUS_PCT:-0}% $(cc_name "$CONSENSUS_CC")")</span>
EOF
  if [[ -n "$EXPECT_CC" ]]; then
    printf '<div style="margin-top:6px"><b>expect</b> <span class="b %s">%s</span></div>\n' \
      "$exp_cls" "$(html_esc "$EXPECT_CC")"
  fi
  cat <<EOF
  </div>
</div>
<div class="card"><b>IP</b><span>$(html_esc "$ip")</span></div>
<div class="card"><b>ASN</b><span>$(html_esc "${ASN:+AS$ASN}")</span></div>
<div class="card"><b>org</b><span>$(html_esc "$ASN_NAME")</span></div>
<div class="card"><b>flags</b><span>$(html_esc "$flags")</span></div>
<div class="card"><b>PTR</b><span>$(html_esc "$PTR")</span></div>
<div class="card"><b>RDAP</b><span>$(html_esc "${RDAP_ORG:+$RDAP_ORG }${RDAP_CC}")</span></div>
<div class="card"><b>CF</b><span>$(html_esc "$cf")</span></div>
<div class="card"><b>city</b><span>$(html_esc "${CITY_MAXMIND:-$CITY_IPINFO}")</span></div>
</div>
EOF

  case "$GROUPS_TO_SHOW" in
    custom) html_table_group "Services" custom ;;
    primary) html_table_group "GeoIP" primary ;;
    cdn) html_table_group "CDN" cdn ;;
    ru) html_table_group "RU" ru ;;
    *)
      html_table_group "Services" custom
      html_table_group "RU" ru
      html_table_group "GeoIP" primary
      html_table_group "CDN" cdn
      ;;
  esac

  local leg
  leg="$(legend_lines)"
  if [[ -n "$leg" ]]; then
    printf '<section><h2>Legend</h2><div class="legend">\n'
    while IFS=$'\t' read -r _ cc pct; do
      [[ -z "$cc" ]] && continue
      printf '<span class="chip"><b>%s</b> %s<em>%s%%</em></span>\n' \
        "$(html_esc "$cc")" "$(html_esc "$(cc_name "$cc")")" "$(html_esc "$pct")"
    done <<<"$leg"
    printf '</div></section>\n'
  fi

  cat <<EOF
<p class="foot">green = GEO match, yellow = other / blocked</p>
</div>
</body>
</html>
EOF
}

main() {
  parse_args "$@"
  need_cmds
  tmpdir_init
  check_stack
  get_external_ip
  local pip pver
  pip="$(primary_ip)"
  pver="$(primary_ver)"
  get_ptr "$pip"
  get_rdap "$pip" "$pver"
  get_asn_and_flags

  spinner_start
  run_groups
  spinner_stop

  # refresh cities/flags written by workers in same process only;
  # parallel jobs cannot update parent vars. Re-run cheap city sources here.
  lk_cloudflare "$(primary_ver)" >/dev/null || true
  lk_maxmind "$(primary_ver)" >/dev/null || true
  lk_2ipio "$(primary_ver)" >/dev/null || true
  lk_sypex "$(primary_ver)" >/dev/null || true
  # ipinfo city already in get_asn_and_flags

  compute_consensus
  if [[ -n "$EXPECT_CC" && "$CONSENSUS_CC" != "$EXPECT_CC" ]]; then
    EXIT_STATUS=1
  fi

  if [[ "$JSON_OUTPUT" == true ]]; then
    print_json
  elif [[ "$HTML_OUTPUT" == true ]]; then
    print_html
  else
    print_human
  fi
  exit "$EXIT_STATUS"
}

main "$@"