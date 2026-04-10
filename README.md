# Heimdall Snitch

Passive network observation toolkit for headless Linux servers.

## What it does

Heimdall Snitch is an interactive Bash script for inspecting outbound connections and traffic on Linux servers without blocking anything.

It uses familiar tools such as:

- `ss`
- `lsof`
- `watch`
- `tcpdump`
- `nethogs` (optional)
- `bpftrace` (optional)

## Why it exists

Interactive desktop firewalls are not a great idea on headless remote servers. Heimdall Snitch is a safer, passive alternative for answering the eternal question:

**which process is phoning home, and where?**

## Features

- live TCP connection view
- established connection watcher
- process-based socket inspection
- per-process bandwidth view with `nethogs`
- DNS traffic inspection with `tcpdump`
- general traffic inspection with `tcpdump`
- optional `bpftrace` connect logger

## Requirements

Base tools:

- `iproute2`
- `lsof`
- `procps-ng`
- `tcpdump`

Optional:

- `nethogs`
- `bpftrace`

## Install dependencies on Arch Linux

```bash
sudo pacman -S iproute2 lsof procps-ng tcpdump
sudo pacman -S nethogs bpftrace

RUN
chmod +x heimdall-snitch.sh
./heimdall-snitch.sh

Safety

This tool is passive. It does not modify firewall rules and does not block connections.

License

MIT License

Copyright (c) 2026 body007hun

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
