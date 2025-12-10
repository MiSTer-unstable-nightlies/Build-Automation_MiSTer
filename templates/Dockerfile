FROM <<DOCKER_IMAGE>> AS builder
WORKDIR /project
ADD . /project
RUN <<COMPILATION_COMMAND>>

FROM scratch AS artifact
COPY --from=builder /project/<<COMPILATION_OUTPUT>> /project/<<COMPILATION_OUTPUT>>
