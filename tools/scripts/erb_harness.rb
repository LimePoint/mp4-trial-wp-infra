require 'erb'
require 'json'

class ERBContext
  def initialize(hash)
    hash.each_pair do |key, value|
      instance_variable_set('@' + key.to_s, value)
    end
  end

  def get_binding
    binding
  end
end

class QuickTemplate
   attr_reader :args, :text
   def initialize(file)
      @text = File.read(file)
   end
   def exec(args={})
      template = ERB.new(@text, 0, "%<>")

      b = ERBContext.new(args).get_binding

      result = template.result(b)

      # Chomp the trailing newline
      result.gsub(/\n$/,'')
   end
end

###################################################################################
## Usage:
##    ruby erb_harness.rb <input erb file> <input JSON params>
##
###################################################################################

## First arg is a path to ERB file to test
erb_filename = ARGV[0]

## Second arg is a path to JSON file for context
## Convert JSON file to Hash
vars = JSON.parse(File.read(ARGV[1]))

puts  JSON.pretty_generate(JSON.parse(QuickTemplate.new(erb_filename).exec(vars)))

