-- Extend the already-installed private dispatcher without embedding credentials.
do $$
declare definition text;
begin
  definition := pg_get_functiondef('shebbak_private.dispatch_pipeline()'::regprocedure);
  if position('renaissance scene elcinema vox' in definition)=0 then
    raise exception 'Dispatcher layout changed; review source schedule before applying';
  end if;
  definition := replace(definition,'''renaissance scene elcinema vox''','''renaissance scene elcinema vox premiere''');
  definition := replace(definition,'''renaissance scene vox''','''renaissance scene vox premiere''');
  execute definition;
end $$;
