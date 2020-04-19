if node['password_vault']==nil
  override['password_vault']={}
end
override['password_vault']['minimum_password_length']=20
override['password_vault']['symbol_set']='_'
override['password_vault']['include_symbols']=true
override['password_vault']['require_caps']=true
