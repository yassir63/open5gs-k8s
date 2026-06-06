import argparse
import json
from pathlib import Path

DEFAULT_KEY = "fec86ba6eb707ed08905757b1bb44b8f"
DEFAULT_OPC = "C42449363BBAD02B66D16BC975D77CC1"
UNIT_GBPS = 3
TYPE_IPV4 = 1
STATUS_DISABLED = 1


def normalize_sd(value):
    sd = str(value).strip().lower().replace("0x", "")
    if not sd or sd in {"empty", "none", "null"}:
        return "ffffff"
    if len(sd) > 6 or any(char not in "0123456789abcdef" for char in sd):
        raise argparse.ArgumentTypeError(
            f"invalid SD {value!r}; expected EMPTY or up to 6 hexadecimal digits"
        )
    return sd.zfill(6)


def slice_data(args):
    return {
        "slice_1": {
            "sst": args.slice1_sst,
            "sd": normalize_sd(args.slice1_sd),
            "default_indicator": True,
            "session": [
                {
                    "name": args.slice1_dnn,
                    "type": TYPE_IPV4,
                    "pcc_rule": [],
                    "ambr": {
                        "uplink": {"value": 1, "unit": UNIT_GBPS},
                        "downlink": {"value": 1, "unit": UNIT_GBPS},
                    },
                    "qos": {
                        "index": 9,
                        "arp": {
                            "priority_level": 8,
                            "pre_emption_capability": STATUS_DISABLED,
                            "pre_emption_vulnerability": STATUS_DISABLED,
                        },
                    },
                }
            ],
        },
        "slice_2": {
            "sst": args.slice2_sst,
            "sd": normalize_sd(args.slice2_sd),
            "default_indicator": True,
            "session": [
                {
                    "name": args.slice2_dnn,
                    "type": TYPE_IPV4,
                    "pcc_rule": [],
                    "ambr": {
                        "uplink": {"value": 1, "unit": UNIT_GBPS},
                        "downlink": {"value": 1, "unit": UNIT_GBPS},
                    },
                    "qos": {
                        "index": 9,
                        "arp": {
                            "priority_level": 8,
                            "pre_emption_capability": STATUS_DISABLED,
                            "pre_emption_vulnerability": STATUS_DISABLED,
                        },
                    },
                }
            ],
        },
    }


def subscriber(imsi, slice_info):
    return {
        "_id": "",
        "imsi": imsi,
        "subscribed_rau_tau_timer": 12,
        "network_access_mode": 0,
        "subscriber_status": 0,
        "access_restriction_data": 32,
        "slice": [slice_info],
        "ambr": {
            "uplink": {"value": 1, "unit": UNIT_GBPS},
            "downlink": {"value": 1, "unit": UNIT_GBPS},
        },
        "security": {
            "k": DEFAULT_KEY,
            "amf": "8000",
            "op": None,
            "opc": DEFAULT_OPC,
        },
        "schema_version": 1,
        "__v": 0,
    }


def main():
    parser = argparse.ArgumentParser(
        description="Generate Open5GS subscriber data for scalable UERANSIM attach/detach churn tests."
    )
    parser.add_argument("--count", type=int, required=True, help="Number of churn UEs to generate.")
    parser.add_argument(
        "--imsi-prefix",
        default="0010100001",
        help="First 10 digits of the 15-digit IMSI. Default gives 001010000100000+.",
    )
    parser.add_argument("--start-suffix", type=int, default=0, help="Numeric suffix for the first IMSI.")
    parser.add_argument("--data-dir", default="data", help="Directory for slices.yaml and subscribers.yaml.")
    parser.add_argument("--slice1-sst", type=int, default=1)
    parser.add_argument("--slice1-sd", default="ffffff")
    parser.add_argument("--slice1-dnn", default="internet")
    parser.add_argument("--slice2-sst", type=int, default=1)
    parser.add_argument("--slice2-sd", default="100000")
    parser.add_argument("--slice2-dnn", default="streaming")
    args = parser.parse_args()

    if args.count < 1:
        raise SystemExit("--count must be >= 1")
    if len(args.imsi_prefix) != 10 or not args.imsi_prefix.isdigit():
        raise SystemExit("--imsi-prefix must be exactly 10 digits")
    if args.start_suffix < 0 or args.start_suffix > 99999:
        raise SystemExit("--start-suffix must be between 0 and 99999")
    if args.start_suffix + args.count - 1 > 99999:
        raise SystemExit("IMSI suffix range exceeds 99999")

    data_dir = Path(args.data_dir)
    data_dir.mkdir(parents=True, exist_ok=True)

    slices = slice_data(args)
    subscribers = {}
    for ordinal in range(args.count):
        suffix = args.start_suffix + ordinal
        imsi = f"{args.imsi_prefix}{suffix:05d}"
        slice_name = "slice_1" if ordinal % 2 == 0 else "slice_2"
        subscribers[f"churn_ue_{ordinal:05d}"] = subscriber(imsi, slices[slice_name])

    with (data_dir / "slices.yaml").open("w") as f:
        json.dump(slices, f, indent=2)
        f.write("\n")
    with (data_dir / "subscribers.yaml").open("w") as f:
        json.dump(subscribers, f, indent=2)
        f.write("\n")

    print(f"Wrote {len(subscribers)} subscribers to {data_dir / 'subscribers.yaml'}")
    print(
        "IMSI range: "
        f"{args.imsi_prefix}{args.start_suffix:05d} - "
        f"{args.imsi_prefix}{args.start_suffix + args.count - 1:05d}"
    )
    print(
        "Slices: "
        f"slice_1={slices['slice_1']['sst']}:{slices['slice_1']['sd']}"
        f"/{args.slice1_dnn}, "
        f"slice_2={slices['slice_2']['sst']}:{slices['slice_2']['sd']}"
        f"/{args.slice2_dnn}"
    )


if __name__ == "__main__":
    main()
