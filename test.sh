#!/bin/bash
#set -x

docker run -it --rm -d \
	-h mail.example.test \
	yeak/zimbra-aio:10.1.15.p1
