CREATE OR REPLACE PACKAGE BODY "UTL_GENERATE" 
/**
 *	Oradew Code Generators.
 *
 *  @return Generated content
 *  @param  object_type       Object type derived from path of ${file}
 *  @param  name              Object name derived from path of ${file}
 *  @param  schema            Objects schema derived from path of ${file}
 *  @param  selected_object   ${selectedText} in editor
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
end UTL_GENERATE;