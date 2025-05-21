FROM alpine

RUN apk update && apk add docker-cli jq iproute2
COPY --chmod=0755 router.sh /

CMD ["/router.sh"]
