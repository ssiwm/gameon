"""Relay ENet UDP: 75 ms w każdą stronę i deterministyczna strata co 13. datagramu.

Wyłącznie test lokalny; nie zmienia pakietów ani kodu gry. Biblioteka standardowa.
Uruchom relay, serwer na 18974 i klienta z --motion-port=19074.
"""
import argparse
import heapq
import select
import socket
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--listen", type=int, default=19074)
    parser.add_argument("--server", type=int, default=18974)
    parser.add_argument("--seconds", type=float, default=12.0)
    args = parser.parse_args()
    upstream = ("127.0.0.1", args.server)
    client = None
    pending = []
    count = dropped = forwarded = 0
    started = time.monotonic()
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as relay:
        relay.bind(("127.0.0.1", args.listen))
        print("READY enemy motion relay", flush=True)
        while time.monotonic() - started < args.seconds:
            now = time.monotonic()
            while pending and pending[0][0] <= now:
                _, _, data, target = heapq.heappop(pending)
                relay.sendto(data, target)
                forwarded += 1
            timeout = min(0.02, max(0.0, pending[0][0] - now)) if pending else 0.02
            if not select.select([relay], [], [], timeout)[0]:
                continue
            try:
                data, source = relay.recvfrom(65535)
            except ConnectionResetError:
                # Windows zgłasza ICMP po zamknięciu już zaliczonego klienta.
                continue
            if source == upstream:
                target = client
            else:
                if client is None:
                    client = source
                if source != client:
                    continue
                target = upstream
            if target is None:
                continue
            count += 1
            if count > 30 and count % 13 == 0:
                dropped += 1
                continue
            heapq.heappush(pending, (time.monotonic() + 0.075, count, data, target))
    ok = forwarded > 30 and dropped > 0
    print(f"{'PASS' if ok else 'FAIL'} enemy motion relay: forwarded={forwarded} dropped={dropped} delay=75ms/direction", flush=True)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
