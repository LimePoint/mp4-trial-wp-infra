Dir.glob(::File.expand_path('../../files/default/vendor/gems/**/lib', __FILE__)).each { |d| $:.unshift(d) unless $:.include?(d) }

		$:.unshift ::File.dirname(__FILE__)
    require 'base64'
    begin
    require 'live_ast/full'
# Monkey patch this to actually work for us...
module Kernel
  def eval(*args)
    LiveAST::Common.check_arity(args, 1..4)
    if args[1].nil?
      args[1]=binding.of_caller(1)
    end
    LiveAST.eval(*args)
  end
end
    rescue LoadError
    end
		require_relative 'loader'
    require 'EnvironmintCrypt'
		extend EnvironmintCrypt
    EnvironmintRun(Base64.decode64('3Ni+cBpV1VkSdeIkh8Uq4vTR7zh6WqEo0QZ+Bnuedtknmh/jrhg+NFLS5WQM
hn+HVg2Fd27T9qRQrPomPjwwEiazPgHDszCH+xI6dEvF9ROslATB61ut01fK
oIiKs8mbBti9FdLkntqlAxjdt3Ge9x/vZpVNhQEC6w81tOCQeQ3hpzelb+RD
f1FE/KJt29RAAAAAAAAAAAAAAAAAAAAAAJAAAAA=
'), __FILE__)
  