#!/usr/bin/env python -u
import sys
import os
import importlib

WORKDIR = os.getenv('WORKDIR', os.environ['HOME'])
CCPREFIX = os.getenv('CCPREFIX', WORKDIR + "/tools/arm-bcm2708/arm-bcm2708-linux-gnueabi/bin/arm-bcm2708-linux-gnueabi-")

if len(sys.argv) < 3:
	sys.stderr.write("Usage: python -u task.py branch task(s)\nEx:\n  python -u task.py master all\n")
	exit(1)

try:
	branch = importlib.import_module(sys.argv[1])
except ImportError:
	sys.stderr.write("No such branch: %s\n" % sys.argv[1])
	exit(1)

tasks = branch.Tasks(WORKDIR, ccprefix=CCPREFIX)

for arg in sys.argv[2:]:
	tasks(arg)
