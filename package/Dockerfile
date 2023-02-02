FROM registry.suse.com/bci/bci-base:15.4 as intermediate

#Label the image for cleaning after build process
LABEL stage=intermediate

RUN zypper --non-interactive update \
    && zypper --non-interactive install \
    git

RUN git clone -b v0.6.10 --depth 1 https://github.com/aquasecurity/kube-bench.git

FROM registry.suse.com/bci/bci-base:15.4
ARG kube_bench_tag=0.6.10
ARG sonobuoy_version=0.56.7

RUN zypper --non-interactive update \
    && zypper --non-interactive install \
    curl \
    jq \
    gzip \
    vim \
    systemd \
    tar \
    awk
RUN curl -sLf https://dl.k8s.io/release/v1.26.0/bin/linux/amd64/kubectl > /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl
RUN curl -sLf https://github.com/aquasecurity/kube-bench/releases/download/v${kube_bench_tag}/kube-bench_${kube_bench_tag}_linux_amd64.tar.gz | tar -xvzf - -C /usr/bin

COPY --from=intermediate /kube-bench/cfg /etc/kube-bench/cfg/

COPY package/cfg/ /etc/kube-bench/cfg/
COPY package/run.sh \
    package/run_kubebench.sh \
    bin/kb-summarizer \
    package/helper_scripts/check_files_permissions.sh \
    package/helper_scripts/check_files_owner_in_dir.sh \
    package/helper_scripts/check_encryption_provider_config.sh \
    package/helper_scripts/check_for_network_policies.sh \
    package/helper_scripts/check_for_default_sa.sh \
    package/helper_scripts/check_for_default_ns.sh \
    package/helper_scripts/check_for_k3s_etcd.sh \
    package/helper_scripts/check_for_rke2_network_policies.sh \
    package/helper_scripts/check_for_rke2_cni_net_policy_support.sh \
    package/helper_scripts/check_cafile_permissions.sh \
    package/helper_scripts/check_cafile_ownership.sh \
    /usr/bin/

CMD ["run.sh"]
# For debugging purposes
# CMD exec /bin/bash -c "trap : TERM INT; sleep infinity & wait"

