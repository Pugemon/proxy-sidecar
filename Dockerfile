FROM alpine:latest

RUN apk add --no-cache redsocks iptables sed

COPY redsocks.conf.template /etc/redsocks/redsocks.conf.template
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
