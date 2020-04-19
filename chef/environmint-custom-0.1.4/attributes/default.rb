Dir.glob(::File.expand_path('../../files/default/vendor/gems/**/lib', __FILE__)).each { |d| $:.unshift(d) unless $:.include?(d) }
#
# Cookbook Name:: environmint-custom
# Attributes::default
#
# Copyright 2014, LimePoint Pty Ltd
#
# All rights reserved - Do Not Redistribute
#