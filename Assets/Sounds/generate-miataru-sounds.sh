#!/bin/bash

python3 sfxgen.py --wave sine --freq 1500 --sweep -900 --dur 0.10 --attack 0.002 --decay 0.03 --sustain 0 --release 0.04 --noise 0.01 --softclip 1.2 --out handshake_call.wav
python3 sfxgen.py --wave sine --freq 1150 --sweep -650 --dur 0.12 --attack 0.002 --decay 0.04 --sustain 0 --release 0.05 --noise 0.01 --softclip 1.2 --out handshake_resp.wav

python3 sfxgen.py \
  --wave triangle \
  --freq 980 \
  --sweep -180 \
  --dur 0.22 \
  --attack 0.018 \
  --decay 0.07 \
  --sustain 0 \
  --release 0.12 \
  --noise 0.015 \
  --softclip 0.8 \
  --out handshake_call_3.wav

python3 sfxgen.py \
  --wave triangle \
  --freq 720 \
  --sweep -120 \
  --dur 0.26 \
  --attack 0.020 \
  --decay 0.09 \
  --sustain 0 \
  --release 0.14 \
  --noise 0.018 \
  --softclip 0.8 \
  --out handshake_resp_3.wav

python3 sfxgen.py \
  --wave triangle \
  --freq 820 \
  --sweep -140 \
  --dur 0.32 \
  --attack 0.025 \
  --decay 0.10 \
  --sustain 0 \
  --release 0.16 \
  --noise 0.02 \
  --softclip 0.7 \
  --out handshake_single_3.wav

python3 sfxgen.py \
  --wave sine \
  --freq 1450 \
  --sweep -700 \
  --dur 0.16 \
  --attack 0.003 \
  --decay 0.05 \
  --sustain 0 \
  --release 0.07 \
  --noise 0.008 \
  --softclip 1.3 \
  --out handshake_call_2.wav

python3 sfxgen.py \
  --wave sine \
  --freq 1100 \
  --sweep -500 \
  --dur 0.18 \
  --attack 0.003 \
  --decay 0.06 \
  --sustain 0 \
  --release 0.08 \
  --noise 0.008 \
  --softclip 1.3 \
  --out handshake_resp_2.wav

python3 sfxgen.py \
  --wave triangle \
  --freq 1250 \
  --sweep -450 \
  --dur 0.26 \
  --attack 0.004 \
  --decay 0.09 \
  --sustain 0 \
  --release 0.12 \
  --noise 0.006 \
  --softclip 1.2 \
  --out handshake_single.wav


afconvert handshake_resp.wav handshake_resp.caf -f caff -d LEI16@44100 -c 1
afconvert handshake_resp.wav handshake_resp_2.caf -f caff -d LEI16@44100 -c 1
afconvert handshake_resp.wav handshake_call.caf -f caff -d LEI16@44100 -c 1
afconvert handshake_resp.wav handshake_call_2.caf -f caff -d LEI16@44100 -c 1
afconvert handshake_resp.wav handshake_single.caf -f caff -d LEI16@44100 -c 1
afconvert handshake_resp.wav handshake_call_3.caf -f caff -d LEI16@44100 -c 1
afconvert handshake_resp.wav handshake_resp_3.caf -f caff -d LEI16@44100 -c 1
afconvert handshake_resp.wav handshake_single_3.caf -f caff -d LEI16@44100 -c 1

afconvert 836449__feraly__simple-or-cute-ui-ux-interface-cancel-sound.wav cancel.caf -f caff -d LEI16@44100 -c 1
afconvert 836450__feraly__simple-or-cute-ui-ux-interface-confirm-sound.wav confirm.caf -f caff -d LEI16@44100 -c 1
