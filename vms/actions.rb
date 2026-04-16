action :check_oracle_docs do
  exec_command 'curl -L https://updates.oracle.com'
end
