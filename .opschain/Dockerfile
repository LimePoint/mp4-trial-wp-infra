# syntax = docker/dockerfile:1.4

ARG OPSCHAIN_BASE_RUNNER

# The repo (including the .git directory) is extracted into a scratch layer for improved caching.
FROM scratch as repo
ADD ./repo.tar .

# The repo (including the .git directory) is extracted into a scratch layer for improved caching.
FROM scratch as trust_store
# ADD ./opschain-trust-store.tar .

# OpsChain Step Runner Docker images must be based on an opschain-runner(-*) base image.
FROM ${OPSCHAIN_BASE_RUNNER}

# Run any Dockerfile commands that don't rely on the contents of the Git repository here to avoid rerunning them when the Git repo changes.

# The step below adds the OpsChain trust store CA certificates to the image.
COPY --link --chown=10001:10001 --from=trust_store / /etc/pki/ca-trust/source/anchors

# The step below adds the Project Git repository (including the .git directory).
# Specific files can be copied instead, e.g. `COPY --from=repo /Gemfile* .`, to improve caching and build performance.
COPY --link --chown=10001:10001 --from=repo / /opt/opschain/

# Optional - the Git rev this change was created with. Useful when running scheduled changes to know the current branch.
ARG GIT_REV
ENV GIT_REV=$GIT_REV

# The following steps are an internal OpsChain requirement to configure the Git repository and trust_store. These must
# be present after adding the repo and trust store files.
ARG GIT_SHA
RUN opschain_configure_project_repo.sh "$GIT_SHA"

# Run any Dockerfile commands that rely on the contents of the Git repository here.

# Run any Dockerfile commands that rely on using `opschain-exec` here. Copy the --mount used in the "opschain-exec bundle install" RUN
# command below if you require access to OpsChain secrets and/or properties environment variables.
RUN gem install knife -v 18.5.0
RUN export __checking_licence=1

# Run `bundle install` to install the Ruby dependencies into the image.
# The use of `opschain-exec` with the env_context_zip secret, means that any OpsChain secrets, or properties environment variables
# will be available for Bundler configuration (eg for authentication details).
# By default, the OpsChain lint command will be run to look for errors before execution. To skip linting, pass "false" to the
# `bundle_and_lint.sh` script.
USER opschain
# COPY ../cinc-client.rpm /opt/opschain/cinc-client.rpm
# COPY ../.oci_platform_configs.yaml /opt/opschain/.oci_platform_configs.yaml

# COPY /Volumes/D/resources/source/opschain-soa-template-private/cinc-client.rpm /opt/opschain/cinc-client.rpm
# COPY /Volumes/D/resources/source/opschain-soa-template-private/.oci_platform_configs.yaml /opt/opschain/.oci_platform_configs.yaml

#RUN --mount=type=secret,required=true,id=env_context_zip,uid=10001,gid=10001,target=/opt/opschain/.mintpress/step_context.json.zip \
#     --mount=type=secret,required=false,id=mintpress_license,uid=10001,gid=10001,target=/opt/opschain/.environmint/mintpress.license \
#     bundle_and_lint.sh
# RUN bundle_and_lint.sh

# Run any Dockerfile commands that rely on using Ruby/Bundler here.
