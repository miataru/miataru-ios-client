#!/bin/bash

python3 sfxgen.py --wave sine --freq 1500 --sweep -900 --dur 0.10 --attack 0.002 --decay 0.03 --sustain 0 --release 0.04 --noise 0.01 --softclip 1.2 --out handshake_call.wav
python3 sfxgen.py --wave sine --freq 1150 --sweep -650 --dur 0.12 --attack 0.002 --decay 0.04 --sustain 0 --release 0.05 --noise 0.01 --softclip 1.2 --out handshake_resp.wav

