CREATE OR REPLACE PACKAGE BODY "UTL_GENERATE" 
/**
 *	Oradew Code Generators.
 *
 *  @return Generated content
 *  @param  object_type       Object type derived from path of ${file}
 *  @param  name              Object name derived from path of ${file} (ex. package name)
 *  @param  schema            Objects schema derived from path of ${file}
 *  @param  selected_object   ${selectedText} in editor (ex. procedure name in package)
 *
 */
as
/**
 * Generate an Update statement for a table
 */
  function updateStatement(
    object_type IN VARCHAR2,
    name IN VARCHAR2,
    schema IN VARCHAR2,
    selected_object IN VARCHAR2
  ) return clob
  is
    v_clob CLOB := NULL;
  begin
    select 'UPDATE '|| schema || '.' || selected_object
    || chr(10) || 'SET '
    || chr(10) || listagg(chr(9) || column_name || ' = :' || column_name, ',' || chr(10)) within group (order by column_id)
    || chr(10) || ';'
    into
      v_clob
    from all_tab_columns
    where owner = schema
    and table_name = selected_object
    ;
    return v_clob;
  end updateStatement;
  
/**
 * Generate an Insert statement for a table
 */
  function insertStatement(
    object_type IN VARCHAR2,
    name IN VARCHAR2,
    schema IN VARCHAR2,
    selected_object IN VARCHAR2
  ) return clob
  is
    v_clob CLOB := NULL;
  begin
    select 'INSERT INTO '|| schema || '.' || selected_object || ' ('
    || chr(10) || listagg(chr(9) || column_name, ',' || chr(10)) within group (order by column_id)
    || chr(10) || ') VALUES ('
    || chr(10) || listagg(chr(9) || ':' || column_name, ',' || chr(10)) within group (order by column_id)
    || chr(10) || ');'
    into
      v_clob
    from all_tab_columns
    where owner = schema
    and table_name = selected_object
    ;
    return v_clob;
  end insertStatement;
 
 /**
 * Generate a Run script to execute procedure or function
 */ 
  function runScript(
    object_type IN VARCHAR2,
    name IN VARCHAR2,
    schema IN VARCHAR2,
    selected_object IN VARCHAR2
    ) return clob
  is
    v_clob CLOB := NULL;
    v_clobTemp CLOB := NULL;
    v_object VARCHAR2(100);
    is_function VARCHAR2(1);
  begin

  --Func/Proc can be overloaded, so we loop over overloads...
  for cur in (
    select distinct nvl(overload, 1) as overload
    from all_arguments
    where owner = schema
    and object_name = selected_object
    and (package_name = name or package_name is null)
  ) loop

    --Functions have null argument_name
    select
      case when count(1) > 0 then '1' else '0' end
    into
      is_function
    from all_arguments
    where owner = schema
    and object_name = selected_object
    and (package_name = name or package_name is null)
    and argument_name is null
    and nvl(overload, 1) = cur.overload
    ;

    --Func/Proc in packages have package name prefix
    v_object := case when object_type in ('PACKAGE_SPEC', 'PACKAGE_BODY') then name || '.' || selected_object else name end;

    select
      'SET FEEDBACK OFF'
      -- Variables declaration of arguments
      -- 200 default varchar2 length, refcursor insted of "ref cursors", varchar2 for date
      || chr(10) || to_clob(listagg('VAR ' || NVL(argument_name, 'v_Return') || overload || ' ' ||
        case data_type
          when 'VARCHAR2' then data_type || '(200)'
          when 'REF CURSOR' then 'REFCURSOR'
          when 'DATE' then 'VARCHAR2(30)'
          --when 'OPAQUE/XMLTYPE' then 'CLOB'
          else data_type
        end ||';', chr(10)) within group (order by position))
      -- Assignments only for INPUT arguments
      || chr(10) || chr(10) ||to_clob(listagg(case when IN_OUT = 'IN' then 'EXEC :' || argument_name || overload || ' := ' ||
        'NULL'
        --case data_type
        --  when 'DATE' then 'to_date(sysdate)'
        --  when 'NUMBER' then to_char(position)
        --  else '''' || to_char(position) || ''''
        --end
        || ';' else null end, chr(10)) within group (order by position))
      -- Execution of object
      || chr(10) || chr(10) || 'EXEC '
      -- Function has v_Return assignment
      || case when is_function = '1' then ':v_Return'||max(overload) ||' := ' else null end
      || schema || '.' || v_object || '('
      || to_clob(listagg(case when argument_name is not null then ':' || NVL(argument_name, 'v_Return')|| overload else null end, ',') within group (order by position))
      || ');'
      --printing OUTPUT variables
      || chr(10) || chr(10) ||to_clob(listagg(case when IN_OUT = 'OUT' then 'PRINT ' || NVL(argument_name, 'v_Return')|| overload || ';' else null end, chr(10)) within group (order by position))
      || chr(10)
    into
      v_clobTemp
    from all_arguments
    where owner = schema
    and object_name = selected_object
    and (package_name = name or package_name is null)
    and nvl(overload, 1) = cur.overload
    ;
    v_clob := v_clob || v_clobTemp;
  end loop;

  return v_clob;
  end runScript;
  
  /**
 * Generate shell script to import dependency objects
 */
  function scriptImportDependencies(
    object_type IN VARCHAR2,
    name IN VARCHAR2,
    schema IN VARCHAR2,
    selected_object IN VARCHAR2
  ) return clob
  is
    v_clob CLOB := NULL;
    v_clobTemp CLOB := NULL;
  begin
    --listagg string too long! :|
  
    for rec in (
      select 'call oradew importObject --object ' || referenced_owner || '.' ||referenced_name ||chr(10) as pcall
      from (
        select distinct referenced_owner, referenced_name
        from USER_DEPENDENCIES
        where referenced_owner not in (user, 'SYS', 'WMSYS', 'PUBLIC')
        -- we cannot import these types yet
        and referenced_type not in ('VIEW', 'TRIGGER', 'TABLE')
        order by referenced_owner
      )
    )loop
    
      v_clob := v_clob || rec.pcall;
    end loop;

    return v_clob;
  end scriptImportDependencies;
  
  
  /**
  * Generate proc/func parameters to debug/log
  */
  -- adapted from https://asktom.oracle.com/pls/apex/f?p=100:11:0::::P11_QUESTION_ID:9532095900346470307
  function paramDebug(
    object_type IN VARCHAR2,
    name IN VARCHAR2,
    schema IN VARCHAR2,
    selected_object IN VARCHAR2
  ) return clob is
  
     l_owner   varchar2(30);
     l_clob    clob;
     l_prev_obj varchar2(30) := '*';
     l_msg varchar2(20) := 'DBMS_OUTPUT.PUT_LINE';
 
     procedure wrt(m varchar2) is
       x int := length(m);
     begin
       dbms_lob.writeappend( l_clob,x,m);
     end;
   begin
     dbms_lob.createtemporary(l_clob,true);
 
     select owner into l_owner
     from  all_objects     
     where object_name = upper(name)
     and (          
          ( schema is not null and owner = upper(schema) )
          or ( schema is null )
         )
     and   object_type in ('PROCEDURE','FUNCTION','PACKAGE');
 
     for i in ( select rownum r, d.* , max(case when argument_name is not null             and
                                                     data_type not in ('REF','REF CURSOR') and                                                     
                                                     data_level = 0 then
                                                           length(argument_name) else 0 end) over (partition by subprogram_id) +
                                       max(case when argument_name is not null  and
                                                data_type  in (  'PL/SQL TABLE'
                                                                   ,'TABLE'
                                                                   ,'VARRAY')    and                                                
                                                data_level = 0 then
                                                6 else 0 end) over (partition by subprogram_id) as arglen
                from all_arguments d
                where                 
                (package_name = name or package_name is null)
                and   owner = l_owner
                and object_name = selected_object 
                order by in_out, subprogram_id, position
              ) loop
      if to_char(i.in_out) != l_prev_obj then
          wrt(chr(10)||'  '||l_msg||'(''' || i.in_out ||': '||i.object_name||''');'||chr(10));
          l_prev_obj := i.in_out;
       end if;
 
       if i.argument_name is not null             and
          i.data_type not in ('REF','REF CURSOR') and          
          i.data_level = 0 then
 
           if i.data_type in (  'BINARY_DOUBLE'
                               ,'BINARY_FLOAT'  
                               ,'BINARY_INTEGER'
                               ,'PLS_INTEGER'
                               ,'CHAR'
                               ,'FLOAT'
                               ,'INTERVAL DAY TO SECOND'
                               ,'INTERVAL YEAR TO MONTH'
                               ,'NUMBER'
                               ,'RAW'
                               ,'ROWID'
                               ,'TIME'
                               ,'TIME WITH TIME ZONE'
                               ,'TIMESTAMP'
                               ,'TIMESTAMP WITH LOCAL TIME ZONE'
                               ,'TIMESTAMP WITH TIME ZONE'
                               ,'VARCHAR2'
                               ,'UROWID') then
             wrt('  '||l_msg||'('''||rpad(lower(i.argument_name),i.arglen)||'=>''||'||lower(i.argument_name)||');'||chr(10));
           elsif i.data_type = 'DATE' then
             wrt('  '||l_msg||'('''||rpad(lower(i.argument_name),i.arglen)||'=>''||to_char('||lower(i.argument_name)||',''yyyy-mm-dd hh24:mi:ss''));'||chr(10));
           elsif i.data_type = 'PL/SQL BOOLEAN' then
             wrt('  '||l_msg||'('''||rpad(lower(i.argument_name),i.arglen)||'=>''||case '||lower(i.argument_name)||' when false then ''FALSE'' when true then ''TRUE'' else ''NULL'' end);'||chr(10));
           elsif i.data_type in (  'PL/SQL TABLE'
                               ,'TABLE'
                               ,'VARRAY') then
             wrt('  '||l_msg||'('''||rpad(lower(i.argument_name||'.count'),i.arglen)||'=>''||'||lower(i.argument_name)||'.count);'||chr(10));
 
           else
            wrt('  '||l_msg||'('''||rpad(lower(i.argument_name),i.arglen)||'=>***please fill in***'');'||chr(10));
           end if;
      end if;
    end loop;
     return l_clob;
  exception
    when too_many_rows then
        return 'More than one copy of package '||name||' found.  Please specify an owner as well '||chr(10)||
              'for example, PARAM_DEBUG(''MY_PKG'',''SCOTT'')';
   end paramDebug;
   
   function getDdl(
    object_type IN VARCHAR2, 
    name IN VARCHAR2, 
    schema IN VARCHAR2 DEFAULT NULL
  ) return clob is
    l_clob    clob := NULL;
    l_clob_header clob := 'CREATE OR REPLACE ';
    l_name VARCHAR2(100) := name;
    l_object_type VARCHAR2(100) := case object_type 
      when 'PACKAGE_SPEC' then 'PACKAGE' 
      when 'PACKAGE_BODY' then 'PACKAGE BODY' 
      when 'TYPE_SPEC' then 'TYPE' 
      when 'TYPE_BODY' then 'TYPE BODY' 
      else object_type
    end;
  begin
  
    -- dbms_metadata.get_ddl doesn't return objects outside my home schema
    -- all_source does (?)
    -- this is why we are going down this path
    
    dbms_lob.createtemporary(l_clob,true);
            
    if l_object_type in ('VIEW', 'TRIGGER', 'TABLE') then         
      /*for rec in (
        select text
        from all_views
        where
          view_name = l_name
          and owner = schema    
      )loop    
        l_clob := rec.text;
       end loop;  */
       
       -- too hard !! for now as these object has different headers
       l_clob := dbms_metadata.get_ddl(l_object_type, name, schema);
    else
      for rec in (
        select text, line
        from all_source
        where
        name = l_name
        and owner = schema
        and type = l_object_type
        order by line      
      )loop      
        if rec.line = 1 then        
          --Add "create or replace" and schema
          --\s* - white spaces  
          l_clob := REGEXP_REPLACE (rec.text, '^(' || l_object_type|| '\s*)', l_clob_header || l_object_type|| ' "' || schema || '".', 1, 0, 'i'); 
          --Add " to object name, if it doesn't exists already
          --  1, 0,'i' - case insensitive
          l_clob := REGEXP_REPLACE (l_clob, '"?' || l_name || '"?', '"' || l_name || '"', 1, 0, 'i');         
        else
          dbms_lob.writeappend(l_clob, length(rec.text), rec.text);
        end if;
      end loop;    
    end if;
    return l_clob;
  end getDdl;
  
end UTL_GENERATE;