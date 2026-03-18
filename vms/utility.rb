# utility methods
def update_security_rules(host_obj, security_rules)
  ref_security_rules = []
  security_rules = Array(security_rules)
  security_rules.each do|security_rule|
    ref_security_rules << ref(security_rule).controller
  end
  puts "updated network_security_groups = #{ref_security_rules}"
  host_obj.network_security_groups = ref_security_rules

end