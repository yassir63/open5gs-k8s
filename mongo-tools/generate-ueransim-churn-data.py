import argparse
import json
from pathlib import Path

DEFAULT_KEY = "fec86ba6eb707ed08905757b1bb44b8f"
DEFAULT_OPC = "C42449363BBAD02B66D16BC975D77CC1"
UNIT_GBPS = 3
TYPE_IPV4 = 1
STATUS_DISABLED = 1


def slice_data():
    return {
        "slice_1": {
            "sst": 1,
            "sd": "000001",
            "default_indicator": True,
            "session": [
                {
                    "name": "internet",
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
            "sst": 1,
            "sd": "000002",
            "default_indicator": True,
            "session": [
                {
                    "name": "streaming",
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

    slices = slice_data()
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


if __name__ == "__main__":
    main()
