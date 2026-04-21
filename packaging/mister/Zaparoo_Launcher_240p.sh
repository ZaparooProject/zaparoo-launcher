#!/bin/bash
# 240p for CRT - uses 320x240 resolution
vmode -r 320 240 rgb32
QT_QPA_PLATFORM=linuxfb /media/fat/Scripts/zaparoo-launcher
