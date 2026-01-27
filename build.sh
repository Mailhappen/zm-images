#!/bin/bash
#set -x

# Base OS we are using
base_os_name="yeak/zm-base-os"
base_os_version="rockylinux9"
final_image_prefix="yeak/zimbra"
vendor_name="Mailhappen"

# We use zcs from Maldua now
url=https://github.com/maldua/zimbra-foss/releases/download/zimbra-foss-build-rhel-9/10.1.15.p1/zcs-10.1.15_GA_4200001.RHEL9_64.20260110181427.tgz

# Build function
build() {
	final_image_name="$final_image_prefix-$1"
	zcs=$(basename $url)
	zcs=${zcs%.tgz}
	ver=$(dirname $url)
	ver=$(basename $ver)

	zcs_tgz=/tmp/$zcs.tgz
	curl -s -C - -L $url -o $zcs_tgz

	echo "Build docker image: $final_image_name:$ver"
	echo "Wait 5 sec before continuing..."
	sleep 5

	# publish our tgz in a temp webserver
	cid="/tmp/build.$$"
	docker run -d -p 9980:80 --rm --cidfile $cid \
		-v $zcs_tgz:/usr/share/nginx/html/$zcs.tgz nginx
	docker build --progress plain $2 \
		-t $final_image_name:$ver \
		--add-host=host.docker.internal:host-gateway \
		--label zimbra.image.name=$final_image_name \
		--label zimbra.image.version=$ver \
		--label zimbra.image.vendor=$vendor_name \
		--label zimbra.image.license=GPL-3.0-or-later \
		--build-arg BASE_OS=$base_os_name \
		--build-arg VERSION=$base_os_version \
		--build-arg ZCS=$zcs \
		--build-arg DOWNLOAD=http://host.docker.internal:9980/$zcs.tgz \
		--build-arg KEYSTROKES=keystrokes/$1 \
		.
	docker rm -f `cat $cid`
	rm -f $cid
}

# Usage: build [aio|ldap|mta|proxy|mailbox]
type=$1
if [ -n "$type" ]; then
	build $type $2
else
	for type in aio ldap mta proxy logger mailbox; do
		build $type $2
	done
fi
