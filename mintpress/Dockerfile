# syntax = docker/dockerfile:1.19

ARG OPSCHAIN_BASE_RUNNER

# The repo (including the .git directory) is extracted into a scratch layer for improved caching.
FROM scratch as repo
ADD ./repo.tar .

# The repo (including the .git directory) is extracted into a scratch layer for improved caching.
FROM scratch as trust_store
ADD ./opschain-trust-store.tar .

# OpsChain Step Runner Docker images must be based on an opschain-runner(-*) base image.
FROM ${OPSCHAIN_BASE_RUNNER}

COPY --chown=mintpress:opschain --chmod=664 <<'EOH' /opt/mintpress/embedded/lib/ruby/gems/3.4.0/gems/opschain-mintmodel-executor-0.1.0.153/lib/opschain/mintmodel_executor/jobs/base_run_change_step_job.rb
# frozen_string_literal: true

require 'forwardable'
require 'que'
require 'active_support/isolated_execution_state'
require 'active_support/core_ext/time/zones'
require 'active_support/core_ext/date_time/calculations'
require 'opschain/core/que_job_middleware'

require_relative '../error'
require_relative '../exec_system_command'
require_relative '../logger/fluent_io'

module HackMP
  refine Array do
    def to_s = ''
  end
end

module OpsChain
  module MintModelExecutor
    module Jobs
      class BaseRunChangeStepJob < Que::Job
        extend Forwardable

        def run(step_id:, action:)
          @step_id = FluentIO.step_id = step_id
          @action = action
          run_job
        end

        def handle_error(exception)
          log("Failed to run #{step_description} - the following exception was raised:")
          log("Error: #{exception.message}")
          log("Backtrace: #{exception.backtrace.join("\n")}") unless exception.respond_to?(:execute_error) && exception.execute_error
          notify_status(:error)
          super
        end

        private

        attr_reader :step_id, :action

        def_delegators OpsChain::MintModelExecutor::FluentIO, :log, :log_step_status

        def run_job
          action_status = :success
          call_command!
        rescue StandardError => e
          action_status = :error
          raise e
        ensure
          post_command_processing
          state = (action_status == :success ? :finished : :failed_during)
          log_step_status(action:, state:, phase: :step_processing_for)
          notify_status(action_status)
        end

        def call_command!
          notify_status(:started)
          log_step_status(action:, state: :starting, phase: :step_processing_for)
          pre_command_processing
          raise MintModelExecutor::Error.new('Command returned a non-zero return code - see command output for more information', execute_error: true) unless run_command
        end

        def run_command
          using HackMP
# require 'opschain'
require 'las-rpc-utils'
require 'mintpress-common'
require 'mintpress-infrastructure'
require 'mintpress-infrastructure-oci'
require 'mintpress-logger'
require 'mintpress-utils'
require 'mintpress-utils/proxy-object'
require 'oci'
require 'parallel'
require 'pp'
require 'resolv'
require 'timeout'
require 'yaml'

          read_pipe, write_pipe = IO.pipe
          pid = fork do
            read_pipe.close
            ENV.merge!(run_environment)
            $stdout.reopen(write_pipe)
            $stderr.reopen(write_pipe)

            Dir.chdir(run_options[:chdir]) if run_options[:chdir]
            ARGV.clear
            [*positional_arguments, *keyword_arguments].compact.each { ARGV << it }

            require 'opschain'
            $LOADED_FEATURES.grep('resource_types.rb').each { load it }

            load Gem.bin_path('opschain-core', 'opschain-action')
          rescue Exception => e
            $stderr.write(e.full_message)
            write_pipe.close
            exit!(e.respond_to?(:status) ? e.status : 1)
          ensure
            write_pipe.close
            exit!(0)
          end
          write_pipe.close
          read_pipe.each_line { FluentIO.log(it.chomp) }
          Process.wait2(pid).last.success?
        end

        def pre_command_processing; end

        def post_command_processing; end

        def run_change_step_command
          [run_environment, *executable_path, *positional_arguments, *keyword_arguments, run_options].compact
        end

        def keyword_arguments
          []
        end

        def run_environment
          MaskedEnvironmentVariablesStore.masked_variables
        end

        def run_options; end

        def notify_status(action_status)
          notify_kwargs = { step_id:, action_status:, status_at: DateTime.current.utc.iso8601 }
          Que.execute("NOTIFY change_status, '#{notify_kwargs.to_json}'")
          Que.execute('insert into step_status_events(step_id, action_status, status_at, retry_count) values ($1, $2, $3, $4)', notify_kwargs.values.append(0))
        end
      end
    end
  end
end
EOH

# Run any Dockerfile commands that don't rely on the contents of the Git repository here to avoid rerunning them when the Git repo changes.

# The step below adds the OpsChain trust store CA certificates to the image.
COPY --link --chown=10001:10001 --from=trust_store / /etc/pki/ca-trust/source/anchors

# The step below adds the Git repository (optionally including the .git directory).
# Specific files can be copied instead (e.g. `COPY ... /Gemfile* .`) or excluded (e.g. `COPY ... --exclude=.git / .`, as done by default) to improve caching and build performance.
COPY --link --chown=10001:10001 --from=repo --exclude=.git / /opt/opschain/

# Optional - the Git rev this change was created with. Useful when running automated changes to know the current branch.
ARG GIT_REV
# ENV GIT_REV=$GIT_REV

# The following steps are an internal OpsChain requirement to configure the Git repository and trust_store. These must
# be present after adding the repo and trust store files.
ARG GIT_SHA
RUN opschain_configure_project_repo.sh "$GIT_SHA"

# Run any Dockerfile commands that rely on the contents of the Git repository here.

# Run any Dockerfile commands that rely on using `opschain-exec` here. Copy the --mount lines used in the "bundle_and_lint.sh" RUN
# command below if you require access to OpsChain secrets and/or properties environment variables.

# Run `bundle install` to install the Ruby dependencies into the image.
# The use of `opschain-exec` with the env_context_zip secret, means that any OpsChain secrets, or properties environment variables
# will be available for Bundler configuration (eg for authentication details).
# By default, the OpsChain lint command will be run to look for errors before execution. To skip linting, pass "false" to the
# `bundle_and_lint.sh` script.

USER mintpress
RUN --mount=type=secret,required=true,id=env_context_zip,uid=10001,gid=10001,target=/opt/opschain/.opschain/step_context.json.zip \
    --mount=type=secret,required=false,id=mintpress_license,uid=10001,gid=10001,target=/opt/opschain/.environmint/mintpress.license \
    bundle_and_lint.sh

# Run any Dockerfile commands that rely on using Ruby/Bundler here.
RUN ls -l /opt/mintpress/bin/../embedded//bin/ruby
RUN /opt/mintpress/bin/ruby -e 'puts "a"' || true
