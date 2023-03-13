FROM flant/shell-operator:v1.2.0
ENV SHELL_OPERATOR_PROMETHEUS_METRICS_PREFIX ebs_params_controller_
RUN apk add --no-cache aws-cli
ADD ebs-params.sh /hooks
