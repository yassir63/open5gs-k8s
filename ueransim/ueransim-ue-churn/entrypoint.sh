#!/bin/bash
set -euo pipefail

ordinal="${POD_NAME##*-}"
if ! [[ "$ordinal" =~ ^[0-9]+$ ]]; then
  echo "Could not derive StatefulSet ordinal from POD_NAME=${POD_NAME}" >&2
  exit 1
fi

imsi_prefix="${UE_IMSI_PREFIX:-0010100001}"
suffix_start="${UE_IMSI_SUFFIX_START:-0}"
suffix=$((10#$suffix_start + 10#$ordinal))
supi="$(printf 'imsi-%s%05d' "$imsi_prefix" "$suffix")"

if [ $((ordinal % 2)) -eq 0 ]; then
  apn="${UE_SLICE1_APN:-internet}"
  sd="${UE_SLICE1_SD:-000001}"
else
  apn="${UE_SLICE2_APN:-streaming}"
  sd="${UE_SLICE2_SD:-000002}"
fi

mkdir -p /dev/net
if [ ! -e /dev/net/tun ]; then
  mknod /dev/net/tun c 10 200
fi

cat > /tmp/open5gs-ue.yaml <<EOF
supi: '${supi}'
mcc: '001'
mnc: '01'
key: '${UE_KEY:-fec86ba6eb707ed08905757b1bb44b8f}'
op: '${UE_OPC:-C42449363BBAD02B66D16BC975D77CC1}'
opType: 'OPC'
amf: '8000'
imei: '356938035643803'
imeiSv: '4370816125816151'

gnbSearchList:
  - ${UE_GNB_HOST:-gnb-service}

uacAic:
  mps: false
  mcs: false

uacAcc:
  normalClass: 0
  class11: false
  class12: false
  class13: false
  class14: false
  class15: false

sessions:
  - type: 'IPv4'
    apn: '${apn}'
    slice:
      sst: 1
      sd: ${sd}

configured-nssai:
  - sst: 1
    sd: ${sd}

default-nssai:
  - sst: 1
    sd: ${sd}

integrity:
  IA1: true
  IA2: true
  IA3: true

ciphering:
  EA1: true
  EA2: true
  EA3: true

integrityMaxRate:
  uplink: 'full'
  downlink: 'full'
EOF

echo "Starting UERANSIM UE ordinal=${ordinal} supi=${supi} apn=${apn} sd=${sd}"
exec /ueransim/nr-ue -c /tmp/open5gs-ue.yaml
