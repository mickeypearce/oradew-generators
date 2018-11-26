CREATE OR REPLACE PACKAGE "UTL_GENERATE" 
as
  function updateStatement(
    object_type IN VARCHAR2,
    name IN VARCHAR2,
    schema IN VARCHAR2,
    selected_object IN VARCHAR2
  ) return clob;
  
  function insertStatement(
    object_type IN VARCHAR2,
    name IN VARCHAR2,
    schema IN VARCHAR2,
    selected_object IN VARCHAR2
  ) return clob;

  function runScript(
    object_type IN VARCHAR2,
    name IN VARCHAR2,
    schema IN VARCHAR2,
    selected_object IN VARCHAR2
  ) return clob;  
end UTL_GENERATE;