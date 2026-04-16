action :check_oracle_docs, description: 'Check Oracle Docs' do
  exec_command 'curl -L https://updates.oracle.com'
end
