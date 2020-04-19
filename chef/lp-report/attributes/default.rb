
default['report']['stage']['on-prem'] = '/environmint/tmp/report_files'
default['report']['stage']['cloud'] = '/environmint/tmp/report_files'

default['report']['stage']['remote']['on-prem']  = ''
default['report']['stage']['remote']['cloud']  = '/home/opc/ml_pod/data-demo/build_reports'

default['report']['ssh']['remote']['host']['on-prem']  = ''
default['report']['ssh']['remote']['host']['cloud']  = 'opc@reports1.wpdev.mintpress.io'

default['report']['ssh']['remote']['key']['on-prem']  = ''
default['report']['ssh']['remote']['key']['cloud']  = '~/.ssh/wpac-ocloud'

default['manifest']['repo']['on-prem'] = '/environmint/gitrepos/buildmanifest'
default['manifest']['repo']['cloud'] = '/oracle/gitrepos/buildmanifest'

