"""Fetch the versioned official Lottie schema once; later checks are offline."""

import hashlib
from pathlib import Path
from urllib.request import urlopen

URL = "https://lottie.github.io/lottie-spec/1.0.1/lottie.schema.json"
SHA256 = "a6adf87565bfbc94c73b1a5310569fbe53dd7d54df0060dada00559c2a030296"
TARGET = Path(__file__).resolve().parent / ".render/lottie.schema.json"


def main():
    data = TARGET.read_bytes() if TARGET.exists() else None
    if data is None or hashlib.sha256(data).hexdigest() != SHA256:
        with urlopen(URL, timeout=30) as response:
            data = response.read(1_000_000)
    if hashlib.sha256(data).hexdigest() != SHA256:
        raise SystemExit(
            "Schema checksum mismatch; review the upstream change before updating the pin."
        )
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_bytes(data)
    print("Lottie 1.0.1 schema cached and SHA-256 verified.")


if __name__ == "__main__":
    main()
