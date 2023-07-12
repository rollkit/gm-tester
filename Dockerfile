FROM golang:1.20.3
COPY script.sh /script.sh
RUN chmod +x /script.sh
ENTRYPOINT COSMOS_CHECKOUT=$COSMOS_CHECKOUT /script.sh
