FROM registry.access.redhat.com/ubi8/podman:latest 

# These should be overridden in template deployment to interact with Azure service
ENV AZP_URL=https://dev.azure.com/Kyndryl-Sandbox \
    AZP_POOL=openshift-agent \
    AZP_TOKEN=23drcb4x543x4gaoalpiujjxiscrkzsfuzgdmz6n7clqobdw72oq \
    AZP_AGENT_NAME=myagent
# If a working directory was specified, create that directory
ENV AZP_WORK=/_work
ARG AZP_AGENT_VERSION=3.230.0
ARG OPENSHIFT_VERSION=4.15.12
ENV OPENSHIFT_BINARY_FILE="openshift-client-linux-${OPENSHIFT_VERSION}.tar.gz"
ENV OPENSHIFT_4_CLIENT_BINARY_URL=https://mirror.openshift.com/pub/openshift-v4/clients/ocp/${OPENSHIFT_VERSION}/${OPENSHIFT_BINARY_FILE}
ENV _BUILDAH_STARTED_IN_USERNS="" \
    BUILDAH_ISOLATION=chroot \
    STORAGE_DRIVER=vfs \
    HOME=/home/podman

USER root

# Setup for azure and tools
RUN dnf upgrade -y && \
    dnf install -y --setopt=tsflags=nodocs git skopeo podman-docker --exclude container-selinux && \
    dnf clean all && \
    chown -R podman:0 /home/podman && \
    chmod -R 775 /home/podman && \
    chmod -R 775 /etc/alternatives && \
    chmod -R 775 /var/lib/alternatives && \
    chmod -R 775 /usr/bin && \
    chmod 775 /usr/share/man/man1 && \
    mkdir -p /var/lib/origin && \
    chmod 775 /var/lib/origin && \
    chmod u-s /usr/bin/newuidmap && \
    chmod u-s /usr/bin/newgidmap && \
    rm -f /var/logs/* && \
    mkdir -p "$AZP_WORK" && \
    mkdir -p /azp/agent/_diag && \
    mkdir -p /usr/local/bin

WORKDIR /azp/agent

# Get the oc binary
RUN curl  ${OPENSHIFT_4_CLIENT_BINARY_URL} > ${OPENSHIFT_BINARY_FILE} && \
    tar xzf ${OPENSHIFT_BINARY_FILE} -C /usr/local/bin && \
    rm -rf ${OPENSHIFT_BINARY_FILE} && \
    chmod +x /usr/local/bin/oc

# Download and extract the agent package
RUN curl https://vstsagentpackage.azureedge.net/agent/$AZP_AGENT_VERSION/vsts-agent-osx-arm64-$AZP_AGENT_VERSION.tar.gz > vsts-agent-linux-x64-$AZP_AGENT_VERSION.tar.gz && \
    tar zxvf vsts-agent-osx-arm64-$AZP_AGENT_VERSION.tar.gz && \
    rm -rf vsts-agent-osx-arm64-$AZP_AGENT_VERSION.tar.gz 

# Install the agent software
RUN /bin/bash -c 'chmod +x ./bin/installdependencies.sh' && \
    /bin/bash -c './bin/installdependencies.sh' && \
    chmod -R 775 "$AZP_WORK" && \
    chown -R podman:root "$AZP_WORK" && \
    chmod -R 775 /azp && \
    chown -R podman:root /azp

WORKDIR $HOME
USER 1000

# AgentService.js understands how to handle agent self-update and restart
ENTRYPOINT /bin/bash -c '/azp/agent/bin/Agent.Listener configure --unattended \
  --agent "${AZP_AGENT_NAME}-${MY_POD_NAME}" \
  --url "$AZP_URL" \
  --auth PAT \
  --token "$AZP_TOKEN" \
  --pool "${AZP_POOL}" \
  --work /_work \
  --replace \
  --acceptTeeEula && \
   /azp/agent/externals/node/bin/node /azp/agent/bin/AgentService.js interactive --once'
