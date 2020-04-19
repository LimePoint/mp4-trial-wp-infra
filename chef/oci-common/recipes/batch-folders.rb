%w[ /oracle/app/batch /oracle/app/batch/odi /oracle/app/batch/odi/OracleDataLZ /oracle/app/batch/odi/OracleDataLZ/BatchInterface /oracle/app/batch/odi/OracleDataLZ/BatchInterface/DIGITALACCEPTANCE /oracle/app/batch/odi/OracleDataLZ/BatchInterface/DIGITALACCEPTANCE/Logs /oracle/app/batch/odi/OracleDataLZ/BatchInterface/DIGITALACCEPTANCE/Schema /oracle/app/batch/odi/OracleDataLZ/BatchInterface/DIGITALACCEPTANCE/Error /oracle/app/batch/odi/OracleDataLZ/BatchInterface/DIGITALACCEPTANCE/Inbound /oracle/app/batch/odi/OracleDataLZ/BatchInterface/DIGITALACCEPTANCE/Archive /oracle/app/batch/odi/OracleDataLZ/BatchInterface/DIGITALACCEPTANCE/Outbound /oracle/app/batch/odi/OracleDataLZ/BatchInterface/DIGITALACCEPTANCE/Staging /oracle/app/batch/odi/OracleDataLZ/BatchInterface/DIGITALACCEPTANCE/Logs/Audit].each do |path|
	directory path do
		owner "oracle"
		group "oinstall"
		mode '755'
		action :create
		
		ignore_failure true
	end
end
