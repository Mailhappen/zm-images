#!/bin/bash
#set -x

# Simple test
docker run -it --rm -d \
	-h mail.example.test \
	yeak/zimbra-aio:10.1.15.p1
