FROM alpine AS base
RUN echo ddddd
ARG TEST_ARG
RUN echo hi

FROM base AS dependencies
RUN echo hi stage 2


FROM base
COPY --from=dependencies /tmp /tmp2
RUN echo test