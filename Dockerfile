# Set via build-arg
ARG BASE_OS=yeak/zm-base-os
ARG VERSION=rockylinux9

FROM ${BASE_OS}:${VERSION}

ARG DOWNLOAD
ARG ZCS
ARG KEYSTROKES

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

WORKDIR /root

COPY ${KEYSTROKES} install.txt

RUN cat install.txt | cut -d' ' -f1 > /tmp/keystrokes \
  && curl -LO ${DOWNLOAD} \
  && tar xf ${ZCS}.tgz \
  && cd ${ZCS} \
  && sed -i '/checkRequired/d' install.sh \
  && ./install.sh -s < /tmp/keystrokes \
  && sed -i 's/@@BUILD_PLATFORM@@/RHEL9_64/' /opt/zimbra/.platform \
  && cp -a /var/log/zimbra.log /var/log/zimbra-stats.log \
  && mv /tmp/install.log.* /opt/zimbra/log/ \
  && rm -f /tmp/install.log \
  && cd .. \
  && rm -rf ${ZCS} \
  && rm -f ${ZCS}.tgz \
  && rm -f /tmp/keystrokes
