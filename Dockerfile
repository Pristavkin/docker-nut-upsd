FROM alpine:3.19.1

LABEL maintainer="alexey@pristavk.in"

ENV UPS_NAME="ups"
ENV UPS_DESC="UPS"
ENV UPS_DRIVER="usbhid-ups"
ENV UPS_PORT="auto"

ENV API_PASSWORD=""
ENV ADMIN_PASSWORD=""

ENV SHUTDOWN_CMD="echo 'System shutdown not configured!'"

RUN set -ex; \
	# run dependencies
	apk add --no-cache \
		openssh-client \
		libusb-compat \
		nut ;\
	# make run directory
	install -d -m 750 -o nut -g nut /var/run/nut

COPY src/docker-entrypoint /usr/local/bin/
ENTRYPOINT ["docker-entrypoint"]

WORKDIR /var/run/nut

EXPOSE 3493
