FROM flant/shell-operator:v1.6.1
ENV SHELL_OPERATOR_PROMETHEUS_METRICS_PREFIX=ebs_params_controller_
RUN apk --no-cache add aws-cli
ADD ebs-params.sh /hooks
