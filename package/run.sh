#!/bin/bash

set -x
set -eE

defaultCMName=cis-$(date +"%Y-%m-%d-%H-%M-%S-%N")
OUTPUT_CONFIGMAPNAME=${OUTPUT_CONFIGMAPNAME:-${defaultCMName}}

OUTPUT_NS=${OUTPUT_NS:-sonobuoy}
SONOBUOY_POD_NAME=${SONOBUOY_POD_NAME:-sonobuoy}

DONE_ANNOTATION_KEY="field.cattle.io/sonobuoyDone"
DONE_ANNOTATION_VALUE="true"
ERROR_ANNOTATION_VALUE="error"
ERROR_LOG_FILE="/tmp/kbs.error.log"

USER_SKIP_LOCATION="/etc/kbs/userskip/config.json"
NA_SKIP_LOCATION="/etc/kbs/notapplicable/config.json"
DS_SKIP_LOCATION="/etc/kbs/defaultskip/config.json"

KUBEBENCH_RESULTS_DIR=${KUBEBENCH_RESULTS_DIR:-/tmp/results}

CONFIG_DIR="${CONFIG_DIR:-/etc/kube-bench/cfg}"

handle_error() {
  if [[ "${DEBUG}" == "true" ]]; then
      sleep infinity
  fi
  # Annotate self (pod) to signal "error"
  if [[ -s "${ERROR_LOG_FILE}" ]]; then
      if ! kubectl -n "${OUTPUT_NS}" \
        annotate pod "${SONOBUOY_POD_NAME}" \
        ${DONE_ANNOTATION_KEY}="$(cat ${ERROR_LOG_FILE})"
      then
        echo "error annotating self pod"
      fi
  else
      if ! kubectl -n "${OUTPUT_NS}" \
        annotate pod "${SONOBUOY_POD_NAME}" \
        ${DONE_ANNOTATION_KEY}=${ERROR_ANNOTATION_VALUE}
      then
        echo "error annotating self pod"
      fi
  fi
  sleep infinity
}

trap 'handle_error' ERR

echo "Rancher: Running CIS Benchmarks"

# Clean up the results directory, just in case
rm -rf "${KUBEBENCH_RESULTS_DIR}"/*.json

# Run kube-bench first
run_kubebench.sh

KBS_OUTPUT_DIR=${KBS_OUTPUT_DIR:-/tmp/kb-summarizer/output}
KBS_OUTPUT_FILENAME=output.json
mkdir -p "${KBS_OUTPUT_DIR}"

PLUGIN_NAME=${PLUGIN_NAME:-rancher-kube-bench}


get_k8s_api_version() {
  set +x # don't print the token
  KUBE_TOKEN=$(</var/run/secrets/kubernetes.io/serviceaccount/token)
  api_version=$(curl -sSk \
      -H "Authorization: Bearer $KUBE_TOKEN" \
      "https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_PORT_443_TCP_PORT}/version" | jq -r '.major + "." +.minor')
  if pgrep rke2 &>/dev/null; then
    api_version=$(curl -sSk \
      -H "Authorization: Bearer $KUBE_TOKEN" \
      "https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_PORT_443_TCP_PORT}/version" | jq -r '.gitVersion')
  fi
  set -x
  echo "${api_version}"
}

if [[ "${RANCHER_K8S_VERSION}" == "" ]]; then
  K8S_API_VERSION=$(get_k8s_api_version)
  RANCHER_K8S_VERSION="${K8S_API_VERSION}"
  echo "Calculated Rancher Kubernetes Version: ${RANCHER_K8S_VERSION}"
else
  echo "Provided Rancher Kubernetes Version: ${RANCHER_K8S_VERSION}"
fi

if [[ -f "${NA_SKIP_LOCATION}" ]]; then
  echo "using not applicable config from configmap: ${NA_SKIP_LOCATION}"
  if [[ "${DEBUG}" == "true" ]]; then
    cat ${NA_SKIP_LOCATION}
  fi
  export NOT_APPLICABLE_CONFIG_FILE="${NA_SKIP_LOCATION}"
fi

if [[ -f "${DS_SKIP_LOCATION}" ]]; then
  echo "using default skip config from configmap: ${DS_SKIP_LOCATION}"
  if [[ "${DEBUG}" == "true" ]]; then
    cat ${DS_SKIP_LOCATION}
  fi
  export DEFAULT_SKIP_CONFIG_FILE="${DS_SKIP_LOCATION}"
fi

if [[ -f "${USER_SKIP_LOCATION}" ]]; then
  echo "using user skip config from configmap"
  if [[ "${DEBUG}" == "true" ]]; then
    cat ${USER_SKIP_LOCATION}
  fi
  export USER_SKIP_CONFIG_FILE="${USER_SKIP_LOCATION}"
fi


# Run summarizer
# Env Vars:
#   - SKIP_CONFIG_FILE
if [[ "${OVERRIDE_BENCHMARK_VERSION}" != "" ]]; then
  echo "using OVERRIDE_BENCHMARK_VERSION: ${OVERRIDE_BENCHMARK_VERSION}"
  if ! kb-summarizer \
        --benchmark-version "${OVERRIDE_BENCHMARK_VERSION}" \
        --controls-dir "${CONFIG_DIR}" \
        --input-dir "${KUBEBENCH_RESULTS_DIR}" \
        --output-dir "${KBS_OUTPUT_DIR}" \
        --output-filename "${KBS_OUTPUT_FILENAME}" 2> "${ERROR_LOG_FILE}"
  then
    echo "error running kb-summarizer using override benchmark version" | tee -a "${ERROR_LOG_FILE}"
    exit 1
  fi
else
  if ! kb-summarizer \
        --k8s-version "${RANCHER_K8S_VERSION}" \
        --input-dir "${KUBEBENCH_RESULTS_DIR}" \
        --output-dir "${KBS_OUTPUT_DIR}" \
        --output-filename "${KBS_OUTPUT_FILENAME}" 2> "${ERROR_LOG_FILE}"
  then
    echo "error running kb-summarizer" | tee -a "${ERROR_LOG_FILE}"
    exit 1
  fi
fi

# Create a config map with results
if ! kubectl -n "${OUTPUT_NS}" \
  create cm  "${OUTPUT_CONFIGMAPNAME}" \
  --from-file "${KBS_OUTPUT_DIR}"/${KBS_OUTPUT_FILENAME} 2> ${ERROR_LOG_FILE}
then
  echo "error creating configmap for storing the report" | tee -a ${ERROR_LOG_FILE}
  exit 1
fi

if [[ "${DEBUG}" == "true" ]]; then
  sleep "${DEBUG_TIME_IN_SEC}"
fi

# Annotate self (pod) to signal "done"
if [[ "${OUTPUT_NS}" == "sonobuoy" ]]; then 
  if ! kubectl -n "${OUTPUT_NS}" \
    annotate pod "${SONOBUOY_POD_NAME}" \
    ${DONE_ANNOTATION_KEY}=${DONE_ANNOTATION_VALUE} 2> ${ERROR_LOG_FILE}
  then
    echo "error annotating self pod" | tee -a ${ERROR_LOG_FILE}
    exit 1
  fi
  # Wait
  # The controller will remove this chart once the done annotation is detected
  sleep infinity
else 
  exit 0
fi
