# Oradew Code Generators

PL/SQL Generators to use with Oradew extension for VSCode:

- `updateStatement` - Generate an Update statement for a table
- `insertStatement` - Generate an Insert statement for a table
- `runScript` - Generate a run script to execute procedure or function. Useful to print refcursors, etc.


## Install

Generators are stored as functions in a package named `UTL_GENERATE`. The package has to be saved (compiled) on your development DB (DEV environment) before usage:

- Create `dbconfig.json` file
- Run `Oradew: Package` and then
- Run `Oradew: Deploy` to save the package to DB

## Usage

Add generator definitions to `oradewrc.json` file of your project and run generator with `Oradew: Generate...` command on a selected object.
```json
{
  "generator.define": [
    {
      "label": "Update Statement",
      "function": "utl_generate.updateStatement",
      "description": "Generate an Update statement for a table"
    },
    {
      "label": "Insert Statement",
      "function": "utl_generate.insertStatement",
      "description": "Generate an Insert statement for a table"
    },    
    {
      "label": "Run Script",
      "function": "utl_generate.runScript",
      "description": "Generate a Run script to execute procedure or function"
    }
  ]
}
```

## Specification

The DB generator function has the following signature:

```sql
FUNCTION updateStatement(
  object_type IN VARCHAR2,    -- derived from path of ${file}
  name IN VARCHAR2,           -- derived from path of ${file}
  schema IN VARCHAR2,         -- derived from path of ${file}
  selected_object IN VARCHAR2 -- ${selectedText} in editor
) RETURN CLOB;
```

The first three function parameters (`object_type`, `name`, `schema`) are derived from path of the currently opened file: `${file}` as `./src/${schema}/${object_type}/${name}.sql`. Whereas `selected_object` is the currently selected text in the editor: `${selectedText}`.