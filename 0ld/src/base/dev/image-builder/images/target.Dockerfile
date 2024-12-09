ARG BUILDER_IMAGE
ARG SOURCE_IMAGE

FROM ${BUILDER_IMAGE} AS builder
COPY resources /resources
ARG ENVSUBST_TARGET_FOLDERS="/resources"
RUN /envsubst.sh

FROM ${SOURCE_IMAGE} AS target
COPY --from=builder /resources /
