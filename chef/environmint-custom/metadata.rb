name             'environmint-custom'
maintainer       'LimePoint Pty Ltd'
maintainer_email 'info@limepoint.com'
license          'ENVIRONMINT(TM) End-User License. Copyright (c) LimePoint Pty Ltd 2014. All rights reserved.'
description      'Installs/Configures environmint-custom'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version '1.0.0'

depends 'obp-environmint-custom'
depends 'oci-common'
depends 'csh-deployments'
