# zm-images

This build the Zimbra ZCS into docker images.

## The ZCS installer files

The ZCS installer we used is from [Maldua Zimbra FOSS Builder](https://maldua.github.io/zimbra-foss-builder/downloads.html).

## Type of images

1. aio - Standalone all-in-one Zimbra server
2. ldap - For multiserver, ldap component
3. mta - For multiserver, mta component
4. proxy - For multiserver, proxy component
5. logger - For multiserver, logger component
6. mailbox - For multiserver, mailbox component

## How to use

Refer to `test.sh` file for how to start it. Once started, type `/opt/zimbra/libexec/zmsetup.pl` to begin configuring it.

## Updates

Whenever there is a new update, modify the `build.sh` script to change the new URL and run the build again.

## Docker Hub

We may push the image to the docker repositories for public use. In short, once the image is built and make available at the docker hub, the deployment will be easy.

## What's next

The images will be used by project **zm-docker** to run Zimbra in container.

